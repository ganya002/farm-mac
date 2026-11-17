import AppKit
import FarmCore

/// Puts the window in one fixed state for the screenshots in docs/screenshots:
///   FarmMac --demo <empty|picked|collecting|review|uploading|done|notfound>
///           [--demo-files <folder of .blend files>] [--appearance light|dark]
/// Nothing is searched for, collected or uploaded.
@MainActor enum Demo {
    static func start(_ model: AppModel) -> Bool {
        guard let state = value("--demo") else { return false }
        if let look = value("--appearance") { NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua) }
        if let folder = value("--demo-files") { model.library.showFolder(URL(fileURLWithPath: folder)) }
        model.finder.demo(state == "notfound" ? .notFound : .connected)
        guard let first = model.library.blends.first?.url, !["empty", "notfound"].contains(state) else { return true }
        model.selection = first
        guard state != "picked" else { return true }
        let job = SendJob(blend: first, model: model)
        switch state {
        case "collecting": job.phase = .collecting(done: 9, total: 14)
        case "uploading":
            job.phase = .uploading
            job.demoUpload = (sent: 38_400_000, total: 61_200_000)
        case "done": job.phase = .done(id: "demo")
        case "review":
            func item(_ name: String, _ status: CollectReport.Item.Status) -> CollectReport.Item {
                .init(type: "image", block: name, name: name, original: "//textures/\(name)", status: status)
            }
            job.report = CollectReport(blend: "demo.blend", source: "", items:
                (1...11).map { item("tex\($0).png", .collected) } + [item("rock_wall_diff_4k.jpg", .missing), item("grass_02.png", .missing)])
            job.phase = .review
        default: job.phase = .failed("Can't reach the farm. Check you're on the school Wi-Fi.")
        }
        model.job = job
        return true
    }

    private static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
