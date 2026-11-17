import Foundation
import Testing
@testable import FarmCore

// Shape copied from a real Tests/run_collect.sh run (Blender 5.2), paths shortened.
let sampleOutput = """
Blender 5.2.2 LTS (hash d13f752e3b9c built 2026-09-15 01:49:19)
Read blend: "/Users/student/Art/scene.blend"
FARM_PROGRESS 0 3
FARM_PROGRESS 1 3
Warning: something unrelated
FARM_PROGRESS 3 3
Info: Saved copy as "scene.blend"
FARM_COLLECT {"blend": "scene.blend", "source": "/Users/student/Art/scene.blend", "items": [{"type": "image", "block": "wood", "name": "udim_tex.<UDIM>.png", "original": "//udim/udim_tex.<UDIM>.png", "status": "collected", "staged": "textures/1/udim_tex.<UDIM>.png", "files": 2, "bytes": 156}, {"type": "image", "block": "moved", "name": "rock.png", "original": "//old/rock.png", "status": "found", "source": "/Users/student/Downloads/rock.png", "staged": "textures/2/rock.png", "files": 1, "bytes": 78}, {"type": "image", "block": "gone", "name": "gone.png", "original": "//nowhere/gone.png", "status": "missing"}]}
Blender quit
"""

@Test func parsesReportFromBlenderOutput() throws {
    let report = try #require(CollectLine.report(in: sampleOutput))
    #expect(report.blend == "scene.blend")
    #expect(report.items.count == 3)
    #expect(report.collected.map(\.name) == ["udim_tex.<UDIM>.png"])
    #expect(report.found.first?.source == "/Users/student/Downloads/rock.png")
    #expect(report.missing.map(\.block) == ["gone"])
    #expect(report.missing.first?.staged == nil && report.missing.first?.files == nil)
    #expect(report.collected.first?.files == 2 && report.collected.first?.bytes == 156)
    #expect(report.collected.first?.pickedName == "udim_tex.1001.png")
}

@Test func parsesProgressLines() {
    #expect(CollectLine("FARM_PROGRESS 4 14") == .progress(done: 4, total: 14))
    #expect(CollectLine("FARM_PROGRESS x 14") == .other)
    #expect(CollectLine("FARM_COLLECT {not json") == .other)
    #expect(CollectLine("Info: Saved") == .other)
}

@Test func noReportWhenBlenderCrashed() {
    #expect(CollectLine.report(in: "FARM_PROGRESS 1 3\nSegmentation fault\n") == nil)
}

@Test func chunksCoverFileExactlyOnce() {
    let size: Int64 = 20 * 1024 * 1024 + 5
    var offset: Int64 = 0
    var pieces: [Range<Int64>] = []
    while let piece = UploadProtocol.chunk(at: offset, fileSize: size) {
        pieces.append(piece)
        offset = piece.upperBound
    }
    #expect(pieces.count == 3)
    #expect(pieces.map(\.count) == [8 << 20, 8 << 20, 4 << 20 | 5])
    #expect(pieces.first?.lowerBound == 0 && pieces.last?.upperBound == size)
    #expect(UploadProtocol.chunk(at: size, fileSize: size) == nil)
    #expect(UploadProtocol.chunk(at: 0, fileSize: 0) == nil)
    #expect(UploadProtocol.chunk(at: 100, fileSize: 120) == 100..<120)
}

@Test func putResults() {
    let chunk: Int64 = 8 << 20
    #expect(UploadProtocol.interpret(status: 200, body: Data(#"{"ok":true}"#.utf8), offset: chunk, length: chunk) == .next(2 * chunk))
    // Wi-Fi dropped mid-piece: the server kept part of it and says how much.
    #expect(UploadProtocol.interpret(status: 409, body: Data(#"{"message":"Part of that file is already on the farm.","size":12345}"#.utf8), offset: 0, length: chunk) == .next(12345))
    #expect(UploadProtocol.interpret(status: nil, body: Data(), offset: 0, length: chunk) == .retry)
    #expect(UploadProtocol.interpret(status: 503, body: Data(), offset: 0, length: chunk) == .retry)
    #expect(UploadProtocol.interpret(status: 408, body: Data(), offset: 0, length: chunk) == .retry)
    #expect(UploadProtocol.interpret(status: 401, body: Data(#"{"message":"Sign in again."}"#.utf8), offset: 0, length: chunk) == .failed("Sign in again."))
    #expect(UploadProtocol.interpret(status: 400, body: Data("<html>".utf8), offset: 0, length: chunk) == .failed(UploadProtocol.stopped))
    #expect(UploadProtocol.interpret(status: 409, body: Data(), offset: 0, length: chunk) == .failed(UploadProtocol.stopped))
}

@Test func backoffDoublesToThirtySeconds() {
    var delay: TimeInterval = 1
    var seen: [TimeInterval] = []
    for _ in 0..<7 { delay = UploadProtocol.nextDelay(after: delay); seen.append(delay) }
    #expect(seen == [2, 4, 8, 16, 30, 30, 30])
}

@Test func encodesLikeEncodeURIComponent() {
    #expect(UploadProtocol.encode("textures/1/My Wood (2).png") == "textures%2F1%2FMy%20Wood%20(2).png")
    #expect(UploadProtocol.encode("udim.<UDIM>.png") == "udim.%3CUDIM%3E.png")
    #expect(UploadProtocol.encode("Café") == "Caf%C3%A9")
    #expect(UploadProtocol.jobID(Data(#"{"id":"abc123"}"#.utf8)) == "abc123")
}

@Test func listsStagingFilesBlendFirst() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("farm-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let fm = FileManager.default
    try fm.createDirectory(at: root.appendingPathComponent("textures/1"), withIntermediateDirectories: true)
    try Data("a".utf8).write(to: root.appendingPathComponent("textures/1/a.png"))
    try Data("b".utf8).write(to: root.appendingPathComponent("scene.blend"))
    try Data("c".utf8).write(to: root.appendingPathComponent(".DS_Store"))
    try Data().write(to: root.appendingPathComponent("empty.txt"))
    let files = try UploadProtocol.files(in: root)
    #expect(files.map(\.path) == ["scene.blend", "textures/1/a.png"])
    #expect(files.map(\.size) == [1, 1])
}
