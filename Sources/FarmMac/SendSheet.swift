import AppKit
import FarmCore
import SwiftUI

/// One "Send to farm": collect the textures, show what is still missing, upload, open the job page.
@MainActor @Observable
final class SendJob: Identifiable {
    enum Phase: Equatable {
        case collecting(done: Int, total: Int)
        /// Some files are not on this Mac: the student can find them, or send anyway.
        case review
        case uploading
        case failed(String)
    }

    let id = UUID()
    let blend: URL
    private(set) var phase = Phase.collecting(done: 0, total: 0)
    private(set) var report: CollectReport?
    private(set) var uploader: Uploader?
    private(set) var picked: Set<String> = []
    private var staging: URL?
    private var task: Task<Void, Never>?
    private unowned let model: AppModel

    init(blend: URL, model: AppModel) {
        self.blend = blend
        self.model = model
    }

    var stillMissing: [CollectReport.Item] { report?.missing.filter { !picked.contains($0.id) } ?? [] }

    func start() {
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
            phase = .failed("Can't find the farm. Check this Mac is on the school Wi-Fi.")
            return
        }
        phase = .uploading
        let cookies = await model.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let uploader = Uploader(server: server, cookies: cookies)
        self.uploader = uploader
        do {
            let id = try await uploader.upload(staging, label: blend.deletingPathExtension().lastPathComponent)
            model.showJob(id)
            close()
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

    func close() {
        task?.cancel()
        if let staging { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        staging = nil
        model.job = nil
    }
}

struct SendSheet: View {
    let job: SendJob

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sending \(job.blend.deletingPathExtension().lastPathComponent)").font(.title2.bold())
            switch job.phase {
            case .collecting(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1))) {
                    Text(total > 0 ? "Collecting textures… \(done) of \(total)" : "Opening in Blender…")
                }
            case .review:
                review
            case .uploading:
                uploading
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: job.close).keyboardShortcut(.cancelAction)
                if case .failed = job.phase { Button("Try Again", action: job.retry).keyboardShortcut(.defaultAction) }
                if job.phase == .review {
                    Button(job.stillMissing.isEmpty ? "Send" : "Send Anyway", action: job.sendAnyway)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var review: some View {
        if let report = job.report {
            let ready = report.collected.count + report.found.count + job.picked.count
            Text("\(ready) of \(report.items.count) files are ready.")
            if job.stillMissing.isEmpty {
                Label("Every file is found.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("These aren't on this Mac. The farm will look in the school library and on Poly Haven, or you can find them yourself:")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(job.stillMissing) { item in
                            HStack {
                                Image(systemName: "questionmark.square.dashed")
                                Text(item.name).lineLimit(1).truncationMode(.middle).help(item.original)
                                Spacer()
                                Button("Find…") { job.find(item) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    @ViewBuilder private var uploading: some View {
        if let uploader = job.uploader {
            ProgressView(value: uploader.fraction) {
                Text(uploader.retrying ? "Waiting for the Wi-Fi…" : "Uploading…")
            } currentValueLabel: {
                Text("\(ByteCountFormatter.string(fromByteCount: uploader.sent, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: uploader.total, countStyle: .file))")
            }
            if let found = job.report?.found, !found.isEmpty {
                Text("Found \(found.count) file\(found.count == 1 ? "" : "s") somewhere else on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ProgressView("Uploading…")
        }
    }
}
