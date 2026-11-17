import AppKit
import SwiftUI
import WebKit

@main
struct FarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Render Farm", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Finder "Open With" and files dropped on the Dock icon arrive here (.blend is a document type).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { urls.forEach(AppModel.shared.open) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let finder = ServerFinder()
    let library = BlendLibrary()
    let webView = SiteView.make()
    var selection: URL?
    var job: SendJob?
    private var started = false
    private var loadedServer: URL?

    func start() {
        guard !started else { return }
        started = true
        finder.start()
        library.start()
    }

    /// Loads the site's home page when the farm is first found (or its address changed).
    func serverChanged() {
        guard let url = finder.url, url != loadedServer else { return }
        loadedServer = url
        webView.load(URLRequest(url: url))
    }

    /// A .blend from Finder, the Dock or a drop: select it and send it right away.
    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "blend" else { return }
        selection = library.remember(url).url
        send()
    }

    func send() {
        guard let selection, job == nil else { return }
        let job = SendJob(blend: selection, model: self)
        self.job = job
        job.start()
    }

    func showJob(_ id: String) {
        guard let url = finder.url else { return }
        webView.load(URLRequest(url: url.appending(path: "jobs/\(id)")))
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "blend") ?? .data]
        panel.message = "Choose the Blender file to render"
        if panel.runModal() == .OK, let url = panel.url { selection = library.remember(url).url }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Your Blender files") {
                    ForEach(model.library.blends) { blend in
                        BlendRow(blend: blend).tag(blend.url)
                    }
                }
            }
            .overlay {
                if model.library.blends.isEmpty {
                    ContentUnavailableView("No Blender files yet", systemImage: "cube", description: Text("Drag a .blend here, or choose one below."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("Choose File…", action: model.choose).frame(maxWidth: .infinity)
                    Button(action: model.send) {
                        Label("Send to farm", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selection == nil)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if model.finder.url != nil {
                SiteView(webView: model.webView)
            } else {
                ContentUnavailableView {
                    Label("Looking for the farm…", systemImage: "network")
                } description: {
                    Text("Make sure this Mac is on the school Wi-Fi. If it still isn't found, type the farm's address in Settings.")
                } actions: {
                    SettingsLink { Text("Open Settings") }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let blends = urls.filter { $0.pathExtension.lowercased() == "blend" }
            blends.prefix(1).forEach(model.open)
            return !blends.isEmpty
        }
        .sheet(item: $model.job) { job in SendSheet(job: job) }
        .onChange(of: model.finder.url, initial: true) { model.serverChanged() }
        .onAppear { model.start() }
    }
}

struct BlendRow: View {
    @Environment(AppModel.self) private var model
    let blend: BlendLibrary.Blend

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.library.thumbnails[blend.url] ?? NSWorkspace.shared.icon(forFile: blend.url.path))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(blend.name).lineLimit(1)
                Text("\(blend.modified, format: .relative(presentation: .named)) · \(blend.folder)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .help(blend.url.path)
        .task(id: blend.url) { await model.library.loadThumbnail(for: blend.url) }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ServerFinder.manualKey) private var manual = ""

    var body: some View {
        Form {
            TextField("Farm address", text: $manual, prompt: Text("Found automatically"))
                .onSubmit { Task { await model.finder.refresh() } }
            Text(model.finder.url.map { "Using \($0.absoluteString)" } ?? "Not found yet")
                .font(.caption).foregroundStyle(.secondary)
            Text("Leave the address empty to find the farm on the school network by itself.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: manual) { Task { await model.finder.refresh() } }
    }
}
