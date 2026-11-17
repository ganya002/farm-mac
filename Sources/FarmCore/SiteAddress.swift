import Foundation

/// Turns what Bonjour or the student typed into the farm site's root URL.
public enum SiteAddress {
    /// A resolved Bonjour host and port → `http://host[:port]/`.
    /// Handles the forms mDNS hands back: a trailing dot (`farm.local.`), an interface scope on an
    /// address (`192.0.2.9%en0`, `fe80::1%en0`) and bare IPv6. Port 80 is left out of the URL.
    public static func url(host: String, port: UInt16) -> URL? {
        var name = host.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        if let scope = name.firstIndex(of: "%") { name = String(name[..<scope]) }
        while name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, port > 0 else { return nil }
        if name.contains(":") { name = "[\(name)]" }   // IPv6 literal
        return URL(string: port == 80 ? "http://\(name)/" : "http://\(name):\(port)/")
    }

    /// "farm.local" or "http://farm-server:8080/x" (typed in Settings) → a site root URL.
    public static func parse(_ text: String?) -> URL? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text), url.host() != nil, ["http", "https"].contains(url.scheme ?? "") else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.path = "/"
        parts?.query = nil
        parts?.fragment = nil
        return parts?.url
    }
}
