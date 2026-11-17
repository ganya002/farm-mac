import Foundation

/// Decides which .blend files Spotlight finds are worth showing a student as "recent".
/// Hides farm job copies, test fixtures, build folders, caches and Blender's own splash files.
public enum BlendFilter {
    /// Folders that never hold a student's own work.
    static let junkFolders: Set<String> = [
        "library", "caches", "cache", "tmp", "temp", "deriveddata", "node_modules", "fixtures",
        "project",                    // the farm's job copies: <job id>/project/...
        "__macosx", "trash",
    ]

    public static func isJunk(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard name.hasSuffix(".blend") else { return true }
        if name.hasPrefix("blender-") && name.contains("splash") { return true }   // blender-5.3-splash.blend
        guard path.hasPrefix(home + "/") else { return true }                        // /tmp, /private, other users
        let folders = path.dropFirst(home.count + 1).split(separator: "/").dropLast()
        return folders.contains { folder in
            let lower = folder.lowercased()
            return folder.hasPrefix(".") || junkFolders.contains(lower) || looksGenerated(lower)
        }
    }

    /// A folder name made by a program, not a person: a UUID, a hash, or a mktemp suffix.
    static func looksGenerated(_ folder: String) -> Bool {
        let hex = Set("0123456789abcdef")
        let runs = folder.split(whereSeparator: { !hex.contains($0) })
        // Any run of 12+ hex digits that has both digits and letters (UUID tail, git hash, job id).
        if runs.contains(where: { $0.count >= 12 && $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }) { return true }
        // A UUID-shaped name, even a short one: 8-4-4-...
        let parts = folder.split(separator: "-")
        if parts.count >= 3, parts.allSatisfy({ $0.count >= 4 && $0.allSatisfy(hex.contains) }), folder.contains(where: \.isNumber) { return true }
        // mktemp: name.XXXXXX, the random part has a digit.
        if let dot = folder.lastIndex(of: ".") {
            let suffix = folder[folder.index(after: dot)...]
            if suffix.count == 6, suffix.contains(where: \.isNumber) { return true }
        }
        return false
    }

    /// The newest `limit` files worth showing, newest first.
    public static func recent<T>(_ items: [T], path: (T) -> String, date: (T) -> Date, limit: Int = 8, home: String = NSHomeDirectory()) -> [T] {
        Array(items.filter { !isJunk(path($0), home: home) }.sorted { date($0) > date($1) }.prefix(limit))
    }
}
