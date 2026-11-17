import Foundation

/// What `collect.py` found for one .blend: every external file, where it came from, where it was staged.
public struct CollectReport: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public enum Status: String, Codable, Sendable {
            /// The file was where the .blend said.
            case collected
            /// The saved path was gone; Spotlight found the file somewhere else on this Mac.
            case found
            /// Not on this Mac. The farm still tries its school library and Poly Haven.
            case missing
        }

        public var type: String
        public var block: String
        public var name: String
        public var original: String
        public var status: Status
        public var source: String?
        public var staged: String?
        public var files: Int?
        public var bytes: Int64?

        public var id: String { "\(type):\(block)" }

        /// A file name to give a file the student picks with Find…; the farm relinks missing files by name.
        public var pickedName: String {
            name.replacingOccurrences(of: "<UDIM>", with: "1001").replacingOccurrences(of: "<UVTILE>", with: "u1_v1")
        }
    }

    public var blend: String
    public var source: String
    public var items: [Item]

    public var collected: [Item] { items.filter { $0.status == .collected } }
    public var found: [Item] { items.filter { $0.status == .found } }
    public var missing: [Item] { items.filter { $0.status == .missing } }
}

/// One line of `collect.py` output.
public enum CollectLine: Equatable, Sendable {
    case progress(done: Int, total: Int)
    case report(CollectReport)
    case other

    public static let progressPrefix = "FARM_PROGRESS "
    public static let reportPrefix = "FARM_COLLECT "

    public init(_ line: Substring) {
        if line.hasPrefix(Self.progressPrefix) {
            let numbers = line.dropFirst(Self.progressPrefix.count).split(separator: " ").compactMap { Int($0) }
            self = numbers.count == 2 ? .progress(done: numbers[0], total: numbers[1]) : .other
        } else if line.hasPrefix(Self.reportPrefix),
                  let report = try? JSONDecoder().decode(CollectReport.self, from: Data(line.dropFirst(Self.reportPrefix.count).utf8)) {
            self = .report(report)
        } else {
            self = .other
        }
    }

    /// The report in a whole run's output (the last one wins), or nil if Blender stopped before printing it.
    public static func report(in output: String) -> CollectReport? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            if case .report(let report) = CollectLine(line) { return report }
        }
        return nil
    }
}
