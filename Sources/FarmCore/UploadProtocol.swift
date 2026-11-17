import Foundation

/// The farm site's resumable folder upload, as its own web page does it (site/src/routes/+page.svelte):
/// `POST /api/upload` (x-folder, x-size) returns `{id}`; then each file goes up with
/// `PUT /api/jobs/<id>/files` (x-path, x-offset) in 8 MB pieces. A 409 carries `{size}`: what the
/// server already has, so a piece cut off by a Wi-Fi drop is never sent twice.
public enum UploadProtocol {
    public static let chunkSize: Int64 = 8 * 1024 * 1024
    /// Stop retrying when nothing got through for this long (same as the site).
    public static let giveUp: TimeInterval = 15 * 60
    public static let stopped = "The upload stopped. Check the Wi-Fi and press Send again; it continues where it stopped."

    /// JavaScript's encodeURIComponent, which the server undoes with decodeURIComponent.
    public static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The next piece of a file to send, or nil when the server has all of it.
    public static func chunk(at offset: Int64, fileSize: Int64) -> Range<Int64>? {
        guard offset < fileSize else { return nil }
        return max(0, offset)..<min(fileSize, max(0, offset) + chunkSize)
    }

    public enum PutResult: Equatable, Sendable {
        /// Continue from this offset.
        case next(Int64)
        /// Network trouble or a busy server: wait and send the same piece again.
        case retry
        /// The server said no; show the student its message.
        case failed(String)
    }

    /// What to do after `PUT` of the piece `offset..<offset+length` came back with `status` and `body`.
    /// `status` nil means the request never got an answer (Wi-Fi dropped).
    public static func interpret(status: Int?, body: Data, offset: Int64, length: Int64) -> PutResult {
        guard let status else { return .retry }
        if status == 409, let size = json(body)?["size"] as? NSNumber { return .next(size.int64Value) }
        if status >= 500 || status == 408 { return .retry }
        if (200..<300).contains(status) { return .next(offset + length) }
        return .failed(message(body))
    }

    /// Wait before the next retry: doubles from 1 s up to 30 s.
    public static func nextDelay(after delay: TimeInterval) -> TimeInterval { min(max(delay, 0.5) * 2, 30) }

    /// The server's `{message}`, or a general "it stopped".
    public static func message(_ body: Data) -> String {
        (json(body)?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? stopped
    }

    public static func jobID(_ body: Data) -> String? {
        (json(body)?["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public struct File: Equatable, Sendable {
        /// Path inside the project, with "/" separators (x-path).
        public var path: String
        public var url: URL
        public var size: Int64
    }

    /// Every file in a staging folder, .blend first. Hidden files are skipped: the server refuses them.
    public static func files(in folder: URL) throws -> [File] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let base = folder.standardizedFileURL.path + "/"
        var out: [File] = []
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            out.append(File(path: String(path.dropFirst(base.count)), url: url, size: Int64(values.fileSize ?? 0)))
        }
        let sorted = out.filter { $0.size > 0 }.sorted { $0.path < $1.path }
        let isMain = { (file: File) in file.path.hasSuffix(".blend") && !file.path.contains("/") }
        return sorted.filter(isMain) + sorted.filter { !isMain($0) }
    }
}
