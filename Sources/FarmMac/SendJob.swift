import AppKit
import FarmCore

/// One "Send to farm": collect the textures, let the student find what is still missing, upload,
/// then hand over to the farm's job page.
@MainActor @Observable
final class SendJob: Identifiable {
    enum Phase: Equatable {
        case collecting(done: Int, total: Int)
        /// Some files are not on this Mac: the student can find them, or send anyway.
        case review
        case uploading
        case done(id: String)
        case failed(String)
    }

    let id = UUID()
    let blend: URL
    var phase = Phase.collecting(done: 0, total: 0)
    var report: CollectReport?
    var uploader: Uploader?
    /// Fixed upload numbers for Demo screenshots.
    var demoUpload: (sent: Int64, total: Int64)?
    private(set) var picked: Set<String> = []
    private var staging: URL?
    private var task: Task<Void, Never>?
    private unowned let model: AppModel

    init(blend: URL, model: AppModel) {
        self.blend = blend
        self.model = model
    }

    var name: String { blend.deletingPathExtension().lastPathComponent }
    var stillMissing: [CollectReport.Item] { report?.missing.filter { !picked.contains($0.id) } ?? [] }
    var sent: Int64 { demoUpload?.sent ?? uploader?.sent ?? 0 }
    var total: Int64 { demoUpload?.total ?? uploader?.total ?? 0 }
    var retrying: Bool { uploader?.retrying ?? false }
    var isBusy: Bool {
        switch phase {
        case .collecting, .uploading: true
        default: false
        }
    }

    func start() {
        phase = .collecting(done: 0, total: 0)
        task = Task {
            do {
                let (report, staging) = try await Packer.collect(blend) { done, total in
                    Task { @MainActor in
                        if case .collecting = self.phase { self.phase = .collecting(done: done, total: total) }
                    }
                }
                self.report = report
                self.staging = staging
                if report.missing.isEmpty { await upload() } else { phase = .review }
            } catch is CancellationError {
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func upload() async {
        guard let staging else { return start() }
        guard let server = model.finder.url else {
            phase = .failed("Can't find the farm. Check this Mac is on the school Wi-Fi, then try again.")
            return
        }
        phase = .uploading
        let cookies = await model.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let uploader = Uploader(server: server, cookies: cookies)
        self.uploader = uploader
        do {
            let id = try await uploader.upload(staging, label: name)
            removeStaging()
            phase = .done(id: id)
            model.finished(self, job: id)
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retry() {
        if staging == nil { start() } else { task = Task { await upload() } }
    }

    func sendAnyway() { task = Task { await upload() } }

    func find(_ item: CollectReport.Item) {
        guard let staging else { return }
        let panel = NSOpenPanel()
        panel.message = "Find \(item.name)"
        panel.prompt = "Use This File"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Packer.add(url, as: item, to: staging)
            picked.insert(item.id)
        } catch {
            NSSound.beep()
        }
    }

    func cancel() {
        task?.cancel()
        removeStaging()
        model.job = nil
    }

    private func removeStaging() {
        if let staging { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        staging = nil
    }
}
