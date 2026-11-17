import AppKit
import FarmCore
import Foundation
import Network
import dnssd
import os

let farmLog = Logger(subsystem: "io.github.ganya002.farm-mac", category: "farm")

/// Finds the farm's website: a manual address from Settings wins, then Bonjour (`_farmrender._tcp`,
/// advertised by avahi on the server), then the last address that worked.
@MainActor @Observable
final class ServerFinder {
    enum Status: Equatable {
        case searching
        case connected
        /// Looked for a while and found nothing (wrong Wi-Fi, or the farm is off).
        case notFound
        /// macOS Local Network permission is off for this app, so Bonjour can't see anything.
        case denied
    }

    static let serviceType = "_farmrender._tcp"
    private static let lastGoodKey = "lastGoodURL"
    static let manualKey = "manualURL"
    /// Give up the spinner after this long; browsing goes on in the background.
    private static let patience: Duration = .seconds(8)

    private(set) var url: URL?
    private(set) var status = Status.searching
    private var browser: NWBrowser?
    private var discovered: URL?
    private var patienceTask: Task<Void, Never>?

    func start() {
        browser?.cancel()
        status = url == nil ? .searching : .connected
        Task { await refresh() }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            farmLog.info("browser \(String(describing: state), privacy: .public)")
            let denied: Bool
            switch state {
            case .waiting(let error), .failed(let error): denied = Self.isPolicyDenied(error)
            default: denied = false
            }
            if denied { MainActor.assumeIsolated { self?.deny() } }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            farmLog.info("bonjour results \(results.count)")
            for result in results {
                guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
                Self.resolve(name: name, type: type, domain: domain) { url, code in
                    farmLog.info("resolved \(name, privacy: .public) -> \(url?.absoluteString ?? "nil", privacy: .public) code \(code)")
                    MainActor.assumeIsolated {
                        if let url { Task { await self?.offer(url, fromBonjour: true) } }
                        if code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) { self?.deny() }
                    }
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        patienceTask?.cancel()
        patienceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.patience)
            guard let self, !Task.isCancelled, self.status == .searching else { return }
            self.status = .notFound
        }
    }

    /// Re-reads the manual address (after Settings changed it) and checks the saved one.
    func refresh() async {
        if let manual = SiteAddress.parse(UserDefaults.standard.string(forKey: Self.manualKey)) {
            url = manual
            status = .connected
            return
        }
        url = discovered
        if url != nil { status = .connected }
        if url == nil, let saved = SiteAddress.parse(UserDefaults.standard.string(forKey: Self.lastGoodKey)) {
            await offer(saved, fromBonjour: false)
        }
    }

    /// Fixed state for Demo screenshots.
    func demo(_ status: Status) {
        self.status = status
    }

    /// Opens System Settings › Privacy & Security › Local Network.
    static func openLocalNetworkSettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
        NSWorkspace.shared.open(pane)
    }

    private func deny() {
        if url == nil { status = .denied }
    }

    private func offer(_ candidate: URL, fromBonjour: Bool) async {
        guard await Self.reachable(candidate) else {
            farmLog.info("not reachable: \(candidate.absoluteString, privacy: .public)")
            return
        }
        if fromBonjour { discovered = candidate }
        if SiteAddress.parse(UserDefaults.standard.string(forKey: Self.manualKey)) != nil { return }
        if url == nil || fromBonjour { url = candidate }
        status = .connected
        UserDefaults.standard.set(candidate.absoluteString, forKey: Self.lastGoodKey)
    }

    private static func reachable(_ url: URL) async -> Bool {
        let request = URLRequest(url: url, timeoutInterval: 5)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
    }

    private nonisolated static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }

    /// One pending DNSServiceResolve; resolved or timed out exactly once, always on the main queue.
    private final class Resolution: @unchecked Sendable {
        let done: (URL?, DNSServiceErrorType) -> Void
        var ref: DNSServiceRef?
        var finished = false
        init(_ done: @escaping (URL?, DNSServiceErrorType) -> Void) { self.done = done }

        func finish(_ url: URL?, _ code: DNSServiceErrorType) {
            guard !finished else { return }
            finished = true
            if let ref { DNSServiceRefDeallocate(ref) }
            ref = nil
            done(url, code)
            Unmanaged.passUnretained(self).release()   // balances passRetained in resolve
        }
    }

    /// Resolves a Bonjour service to its host name (`farm.local`), so the address survives the
    /// server's IP changing and the site's login cookie stays on one host.
    private nonisolated static func resolve(name: String, type: String, domain: String,
                                            done: @escaping (URL?, DNSServiceErrorType) -> Void) {
        let resolution = Resolution(done)
        let context = Unmanaged.passRetained(resolution).toOpaque()
        var ref: DNSServiceRef?
        let error = DNSServiceResolve(&ref, 0, 0, name, type, domain, { _, _, _, code, _, host, port, _, _, context in
            let resolution = Unmanaged<Resolution>.fromOpaque(context!).takeUnretainedValue()
            let url = host.flatMap { SiteAddress.url(host: String(cString: $0), port: UInt16(bigEndian: port)) }
            resolution.finish(code == DNSServiceErrorType(kDNSServiceErr_NoError) ? url : nil, code)
        }, context)
        guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
            resolution.finish(nil, error)
            return
        }
        resolution.ref = ref
        DNSServiceSetDispatchQueue(ref, .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { resolution.finish(nil, DNSServiceErrorType(kDNSServiceErr_Timeout)) }
    }
}
