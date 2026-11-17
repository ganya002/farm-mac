import AppKit
import QuickLookThumbnailing

/// Every .blend in the student's home folder (Spotlight), newest first. Backups (.blend1),
/// the Trash and ~/Library are left out.
@MainActor @Observable
final class BlendLibrary {
    struct Blend: Identifiable, Hashable {
        var url: URL
        var modified: Date
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
        var folder: String { url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    }

    private(set) var blends: [Blend] = []
    private(set) var thumbnails: [URL: NSImage] = [:]
    /// Files picked or dropped by hand, kept on top across Spotlight updates.
    private var picked: [Blend] = []
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private static let limit = 300

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

    private func reload() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        let home = NSHomeDirectory()
        let hidden = [home + "/.Trash/", home + "/Library/"]
        var out: [Blend] = []
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !hidden.contains(where: path.hasPrefix), !path.contains("/.Trash/") else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            out.append(Blend(url: URL(fileURLWithPath: path), modified: date))
            if out.count == Self.limit { break }
        }
        blends = picked + out.filter { blend in !picked.contains { $0.url == blend.url } }
    }

    /// Adds a file picked or dropped by hand, so it shows (selected) even if Spotlight hasn't seen it.
    func remember(_ url: URL) -> Blend {
        if let known = blends.first(where: { $0.url == url }) { return known }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        let blend = Blend(url: url, modified: date)
        picked.insert(blend, at: 0)
        blends.insert(blend, at: 0)
        return blend
    }

    /// The .blend's own preview (Blender saves one), via QuickLook. Loaded once per file.
    func loadThumbnail(for url: URL) async {
        guard thumbnails[url] == nil else { return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64),
                                                   scale: 2, representationTypes: .thumbnail)
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnails[url] = representation.nsImage
        }
    }
}
