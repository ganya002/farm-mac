import Foundation
import Network

/// Finds the farm's website: a manual address from Settings wins, then Bonjour (`_farmrender._tcp`,
/// advertised by avahi on the server), then the last address that worked.
@MainActor @Observable
final class ServerFinder {
    static let serviceType = "_farmrender._tcp"
    private static let lastGoodKey = "lastGoodURL"
    static let manualKey = "manualURL"

    private(set) var url: URL?
    private(set) var searching = false
    private var browser: NWBrowser?
    private var discovered: URL?

    func start() {
        searching = true
        Task { await refresh() }
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            for result in results { Self.resolve(result.endpoint) { url in Task { @MainActor in await self.offer(url, fromBonjour: true) } } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Re-reads the manual address (after Settings changed it) and checks the saved one.
    func refresh() async {
        if let manual = Self.parse(UserDefaults.standard.string(forKey: Self.manualKey)) {
            url = manual
            searching = false
            return
        }
        url = discovered
        if url == nil, let saved = Self.parse(UserDefaults.standard.string(forKey: Self.lastGoodKey)) {
            await offer(saved, fromBonjour: false)
        }
    }

    private func offer(_ candidate: URL, fromBonjour: Bool) async {
        guard await Self.reachable(candidate) else { return }
        if fromBonjour { discovered = candidate }
        if Self.parse(UserDefaults.standard.string(forKey: Self.manualKey)) != nil { return }
        if url == nil || fromBonjour { url = candidate }
        searching = false
        UserDefaults.standard.set(candidate.absoluteString, forKey: Self.lastGoodKey)
    }

    /// "farm.local" or "http://farm-server:8080/" → a site root URL.
    static func parse(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text), url.host() != nil, ["http", "https"].contains(url.scheme ?? "") else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.path = "/"
        parts?.query = nil
        return parts?.url
    }

    private static func reachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
    }

    /// Resolves a Bonjour service to an http:// address by connecting once over IPv4.
    private nonisolated static func resolve(_ endpoint: NWEndpoint, found: @escaping @Sendable (URL) -> Void) {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    let name: String
                    switch host {
                    case .ipv4(let address): name = "\(address)"
                    case .ipv6(let address): name = "[\(address)]"
                    case .name(let text, _): name = text
                    @unknown default: name = "\(host)"
                    }
                    if let url = URL(string: port.rawValue == 80 ? "http://\(name)/" : "http://\(name):\(port.rawValue)/") { found(url) }
                }
                connection.cancel()
            case .failed, .waiting:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
}
