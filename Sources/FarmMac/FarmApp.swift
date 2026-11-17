import AppKit
import SwiftUI
import WebKit

@main
struct FarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    init() { Theme.registerFonts() }

    var body: some Scene {
        Window("Render Farm", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 980, height: 760)
        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Finder "Open With" and files dropped on the Dock icon arrive here (.blend is a document type).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.prefix(1).forEach { AppModel.shared.open($0, send: true) } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor @Observable
final class AppModel {
    enum Tab: Hashable { case send, renders }

    static let shared = AppModel()

    let finder = ServerFinder()
    let library = BlendLibrary()
    let webView = SiteView.make()
    var tab = Tab.send
    var selection: URL?
    var job: SendJob?
    private var started = false
    private var loadedServer: URL?

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func start() {
        guard !started else { return }
        started = true
        if Demo.start(self) { return }
        finder.start()
        library.start()
    }

    /// Loads the site's home page when the farm is first found (or its address changed).
    func serverChanged() {
        guard let url = finder.url, url != loadedServer else { return }
        loadedServer = url
        webView.load(URLRequest(url: url))
    }

    /// A .blend from Finder, the Dock or a drop. Finder and the Dock mean "send this"; a drop selects it.
    func open(_ url: URL, send: Bool) {
        guard url.pathExtension.lowercased() == "blend", job == nil || job?.isBusy == false else { return }
        job = nil
        withAnimation(Motion.settle(Self.reduceMotion)) {
            tab = .send
            selection = library.remember(url).url
        }
        if send { self.send() }
    }

    func send() {
        guard let selection, job == nil else { return }
        let job = SendJob(blend: selection, model: self)
        withAnimation(Motion.settle(Self.reduceMotion)) { self.job = job }
        job.start()
    }

    /// Upload done: open the job page, then switch to it after a moment so "Sent!" is seen.
    func finished(_ job: SendJob, job id: String) {
        showJob(id)
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard self.job === job else { return }
            withAnimation(Motion.settle(Self.reduceMotion)) {
                self.job = nil
                self.selection = nil
                self.tab = .renders
            }
        }
    }

    func showJob(_ id: String) {
        guard let url = finder.url else { return }
        webView.load(URLRequest(url: url.appending(path: "jobs/\(id)")))
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "blend") ?? .data]
        panel.message = "Choose the Blender file to render"
        if panel.runModal() == .OK, let url = panel.url { open(url, send: false) }
    }
}
