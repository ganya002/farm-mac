import Foundation
import Observation

/// Sends a staging folder to the farm with the site's own resumable folder upload (see UploadProtocol).
/// Uses the cookies of the signed-in web view, so the student never signs in twice.
@MainActor @Observable
public final class Uploader {
    public struct Failure: LocalizedError {
        public var errorDescription: String?
    }

    public private(set) var sent: Int64 = 0
    public private(set) var total: Int64 = 0
    /// True while waiting for the Wi-Fi to come back.
    public private(set) var retrying = false

    public var fraction: Double { total > 0 ? min(1, Double(sent) / Double(total)) : 0 }

    private let server: URL
    private let session: URLSession
    private let cookieHeader: [String: String]

    public init(server: URL, cookies: [HTTPCookie]) {
        self.server = server
        cookieHeader = HTTPCookie.requestHeaderFields(with: cookies.filter { Self.matches($0, server) })
        let config = URLSessionConfiguration.ephemeral
        // Cookies are sent by hand: filling the ephemeral cookie store with setCookies hangs.
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Uploads every file in `folder` as one project named `label`, asks the farm to check it,
    /// and returns the job id.
    public func upload(_ folder: URL, label: String) async throws -> String {
        let files = try UploadProtocol.files(in: folder)
        total = files.reduce(0) { $0 + $1.size }
        sent = 0

        var start = URLRequest(url: server.appending(path: "api/upload"))
        start.httpMethod = "POST"
        start.setValue(UploadProtocol.encode(label), forHTTPHeaderField: "x-folder")
        start.setValue(String(total), forHTTPHeaderField: "x-size")
        let (startBody, startResponse) = try await send(start)
        guard startResponse.statusCode == 200, let id = UploadProtocol.jobID(startBody) else {
            throw Failure(errorDescription: startResponse.statusCode == 401 ? "Sign in to the farm first (in this window), then press Send again." : UploadProtocol.message(startBody))
        }

        var done: Int64 = 0
        for file in files {
            try await sendFile(file, job: id, before: done)
            done += file.size
        }

        var check = URLRequest(url: server.appending(path: "api/jobs/\(id)/check"))
        check.httpMethod = "POST"
        check.setValue("application/json", forHTTPHeaderField: "content-type")
        check.httpBody = Data("{}".utf8)
        let (checkBody, checkResponse) = try await send(check)
        guard checkResponse.statusCode == 200 else { throw Failure(errorDescription: UploadProtocol.message(checkBody)) }
        return id
    }

    private func sendFile(_ file: UploadProtocol.File, job: String, before: Int64) async throws {
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        var offset: Int64 = 0
        var delay: TimeInterval = 1
        var lastGood = Date()
        while let piece = UploadProtocol.chunk(at: offset, fileSize: file.size) {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(piece.lowerBound))
            let data = try handle.read(upToCount: piece.count) ?? Data()
            var request = URLRequest(url: server.appending(path: "api/jobs/\(job)/files"))
            request.httpMethod = "PUT"
            request.setValue(UploadProtocol.encode(file.path), forHTTPHeaderField: "x-path")
            request.setValue(String(piece.lowerBound), forHTTPHeaderField: "x-offset")
            request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
            var status: Int?
            var body = Data()
            do {
                let (answer, response) = try await session.upload(for: signed(request), from: data)
                status = (response as? HTTPURLResponse)?.statusCode
                body = answer
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                status = nil   // Wi-Fi dropped or the server went away: retry below
            }
            switch UploadProtocol.interpret(status: status, body: body, offset: piece.lowerBound, length: Int64(data.count)) {
            case .next(let next):
                offset = next
                sent = before + min(next, file.size)
                lastGood = Date()
                delay = 1
                retrying = false
            case .retry:
                if Date().timeIntervalSince(lastGood) > UploadProtocol.giveUp { throw Failure(errorDescription: UploadProtocol.stopped) }
                retrying = true
                try await Task.sleep(for: .seconds(delay))
                delay = UploadProtocol.nextDelay(after: delay)
            case .failed(let message):
                throw Failure(errorDescription: status == 401 ? "Sign in to the farm again (in this window), then press Send again." : message)
            }
        }
    }

    /// A cookie of the web view that belongs to the farm's host.
    public nonisolated static func matches(_ cookie: HTTPCookie, _ server: URL) -> Bool {
        guard let host = server.host()?.lowercased() else { return false }
        let domain = cookie.domain.lowercased().trimmingPrefix(".")
        return host == domain || host.hasSuffix("." + domain)
    }

    private func signed(_ request: URLRequest) -> URLRequest {
        var request = request
        for (name, value) in cookieHeader { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: signed(request))
            guard let http = response as? HTTPURLResponse else { throw Failure(errorDescription: UploadProtocol.stopped) }
            return (data, http)
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure(errorDescription: "Can't reach the farm. Check you're on the school Wi-Fi.")
        }
    }
}
