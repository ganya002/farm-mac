import SwiftUI
import WebKit

/// The farm's website. The default data store is persistent, so the student's login sticks between
/// launches, and Uploader borrows its cookies.
struct SiteView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}

    @MainActor static func make() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        return view
    }
}
