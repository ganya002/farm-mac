import AppKit
import FarmCore
import QuickLookThumbnailing

/// The student's most recent .blend files (Spotlight, home folder), newest first. Farm job copies,
/// test fixtures, caches, backups and Blender's splash files are hidden (BlendFilter).
@MainActor @Observable
final class BlendLibrary {
    struct Blend: Identifiable, Hashable {
        var url: URL
        var modified: Date
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
        var folder: String { url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    }

    static let shown = 6

    private(set) var blends: [Blend] = []
    private(set) var thumbnails: [URL: NSImage] = [:]
    /// Files picked or dropped by hand, kept on top across Spotlight updates.
    private var picked: [Blend] = []
    private var found: [Blend] = []
    /// Demo folders carry a rendered "<file>.blend.png" next to each file.
    private var sidecars = false
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []

    func start() {
        // "*.blend" also rules out backups like scene.blend1.
        query.predicate = NSPredicate(format: "%K LIKE[c] '*.blend'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        query.start()
    }

    /// Shows the .blend files of one folder instead of Spotlight's (screenshots for the docs).
    func showFolder(_ folder: URL) {
        query.stop()
        sidecars = true
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        found = urls.filter { $0.pathExtension == "blend" }.map { url in
            Blend(url: url, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified > $1.modified }
        merge()
    }

    private func reload() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var all: [Blend] = []
        for case let item as NSMetadataItem in query.results.prefix(500) {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            all.append(Blend(url: URL(fileURLWithPath: path), modified: date))
        }
        found = BlendFilter.recent(all, path: \.url.path, date: \.modified, limit: Self.shown)
        merge()
    }

    private func merge() {
        let rest = found.filter { blend in !picked.contains { $0.url == blend.url } }
        blends = Array((picked + rest).prefix(max(Self.shown, picked.count)))
    }

    /// Adds a file picked or dropped by hand, so it shows even if Spotlight hasn't seen it.
    func remember(_ url: URL) -> Blend {
        if let known = blends.first(where: { $0.url == url }) { return known }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let blend = Blend(url: url, modified: date)
        picked.insert(blend, at: 0)
        merge()
        return blend
    }

    /// The preview Blender saved inside the .blend. Read by Resources/thumbnail.py with Blender's
    /// own Python (cached by path and date); QuickLook as a fallback. Loaded once per file.
    func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil else { return }
        if sidecars, let image = NSImage(contentsOf: url.appendingPathExtension("png")) {
            thumbnails[url] = image
            return
        }
        if let image = await Self.embeddedPreview(url) {
            thumbnails[url] = image
            return
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 320, height: 240),
                                                   scale: 2, representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnails[url] = representation.nsImage
        }
    }

    private nonisolated static func embeddedPreview(_ url: URL) async -> NSImage? {
        guard let python = Packer.blenderPython(), let script = Packer.resource("thumbnail", "py") else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.ganya002.farm-mac/thumbnails", isDirectory: true)
        let key = "\(url.path)|\(modified.timeIntervalSince1970)".data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").suffix(120)
        let png = caches.appendingPathComponent(key + ".png")
        if let cached = NSImage(contentsOf: png) { return cached }
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = python
        process.arguments = ["-I", script.path, url.path, png.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = await withCheckedContinuation { done in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { done.resume(returning: -1) }
        }
        return status == 0 ? NSImage(contentsOf: png) : nil
    }
}
