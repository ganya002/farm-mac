import Foundation
import Testing
@testable import FarmCore

/// Runs Tests/mock_farm.py (the site's upload API with a Wi-Fi drop and a busy server built in).
final class MockFarm {
    let process = Process()
    let root: URL
    let url: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("farm-mock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Tests/mock_farm.py")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", script.path, root.appendingPathComponent("server").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        var line = Data()
        while !line.contains(UInt8(ascii: "\n")), let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty { line.append(byte) }
        let port = String(decoding: line, as: UTF8.self).split(separator: " ").last.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        url = URL(string: "http://127.0.0.1:\(try #require(port))/")!
    }

    func log() async throws -> [[String: Any]] {
        let (data, _) = try await URLSession.shared.data(from: url.appending(path: "log"))
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    deinit {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }
}

private func staging(in root: URL) throws -> URL {
    let folder = root.appendingPathComponent("staging/scene")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("textures/1"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("textures/2"), withIntermediateDirectories: true)
    try Data("BLENDER-v500 fake".utf8).write(to: folder.appendingPathComponent("scene.blend"))
    var big = Data(count: 20 * 1024 * 1024 + 123)
    big.withUnsafeMutableBytes { raw in for i in raw.indices { raw[i] = UInt8(truncatingIfNeeded: i &* 31 &+ i >> 13) } }
    try big.write(to: folder.appendingPathComponent("textures/1/big.bin"))
    try Data("png".utf8).write(to: folder.appendingPathComponent("textures/2/My Wood (2).png"))
    return folder
}

private let cookie = HTTPCookie(properties: [.name: "farm_session", .value: "test", .domain: "127.0.0.1", .path: "/"])!

@MainActor @Test(.timeLimit(.minutes(1)))
func uploadsThroughWifiDropAndBusyServer() async throws {
    let farm = try MockFarm()
    let folder = try staging(in: farm.root)
    let uploader = Uploader(server: farm.url, cookies: [cookie])
    let id = try await uploader.upload(folder, label: "scene")
    #expect(id == "job1")
    #expect(uploader.sent == uploader.total && uploader.total == 20 * 1024 * 1024 + 123 + 17 + 3)

    for path in ["scene.blend", "textures/1/big.bin", "textures/2/My Wood (2).png"] {
        let sent = try Data(contentsOf: folder.appendingPathComponent(path))
        let got = try Data(contentsOf: farm.root.appendingPathComponent("server").appendingPathComponent(path))
        #expect(sent == got, "\(path) arrived intact")
    }
    let log = try await farm.log()
    #expect(log.first?["start"] as? String == "scene")
    #expect(log.first?["size"] as? Int == Int(uploader.total))
    #expect(log.contains { $0["drop"] != nil }, "the Wi-Fi drop happened")
    #expect(log.contains { $0["busy"] != nil }, "the busy answer happened")
    #expect(log.contains { $0["conflict"] != nil }, "the resend after the drop was told the real offset")
    #expect(log.last?["check"] as? Bool == true)
}

@MainActor @Test func signedOutSaysSo() async throws {
    let farm = try MockFarm()
    let folder = try staging(in: farm.root)
    await #expect(throws: Uploader.Failure.self) { try await Uploader(server: farm.url, cookies: []).upload(folder, label: "scene") }
}

@Test func onlyTheFarmsCookiesAreSent() {
    let farm = URL(string: "http://farm.local/")!
    let make = { (domain: String) in HTTPCookie(properties: [.name: "s", .value: "1", .domain: domain, .path: "/"])! }
    #expect(Uploader.matches(make("farm.local"), farm))
    #expect(Uploader.matches(make(".local"), farm))
    #expect(!Uploader.matches(make("example.com"), farm))
    #expect(!Uploader.matches(make("arm.local"), farm))
}
