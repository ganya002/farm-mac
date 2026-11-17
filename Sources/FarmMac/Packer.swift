import AppKit
import FarmCore
import Synchronization

/// Runs the student's own Blender on a copy of their .blend to collect every file it needs
/// (Resources/collect.py) into a staging folder. The student's file is opened read-only.
enum Packer {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    static func blender() -> URL? {
        let standard = URL(fileURLWithPath: "/Applications/Blender.app/Contents/MacOS/Blender")
        if FileManager.default.isExecutableFile(atPath: standard.path) { return standard }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.blenderfoundation.blender")?
            .appendingPathComponent("Contents/MacOS/Blender")
    }

    static func script() -> URL? {
        if let bundled = Bundle.main.url(forResource: "collect", withExtension: "py") { return bundled }
        // `swift run` from the repo: Sources/FarmMac/Packer.swift -> Resources/collect.py
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dev = repo.appendingPathComponent("Resources/collect.py")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// Collects `blend` into a new staging folder. `progress` gets (done, total) as files are copied.
    static func collect(_ blend: URL, progress: @escaping @Sendable (Int, Int) -> Void) async throws -> (CollectReport, URL) {
        guard let blender = blender() else { throw Failure(errorDescription: "Blender isn't in Applications. Install Blender, then try again.") }
        guard let script = script() else { throw Failure(errorDescription: "The app is missing collect.py. Install it again.") }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("farm-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(blend.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = blender
        process.arguments = ["--background", "--factory-startup", "--disable-autoexec", blend.path,
                             "--python", script.path, "--", staging.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = Mutex(Data())
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            let lines: [Substring] = output.withLock { buffer in
                buffer.append(chunk)
                guard let text = String(data: buffer, encoding: .utf8), let cut = text.lastIndex(of: "\n") else { return [] }
                return text[..<cut].split(separator: "\n").filter { $0.hasPrefix(CollectLine.progressPrefix) }
            }
            if case .progress(let done, let total) = lines.last.map(CollectLine.init) { progress(done, total) }
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { process.terminate() }
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = output.withLock { String(decoding: $0 + rest, as: UTF8.self) }
        guard let report = CollectLine.report(in: text) else {
            try? FileManager.default.removeItem(at: staging.deletingLastPathComponent())
            NSLog("collect.py failed (exit %d):\n%@", status, String(text.suffix(4000)))
            throw Failure(errorDescription: "Blender couldn't open that file. Open it in Blender, save it, and try again.")
        }
        return (report, staging)
    }

    /// Puts a file the student found by hand into the staging folder under the name the .blend wants;
    /// the farm relinks missing files by name.
    static func add(_ picked: URL, as item: CollectReport.Item, to staging: URL) throws {
        let folder = staging.appendingPathComponent("found", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(item.pickedName)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: picked, to: target)
    }
}
