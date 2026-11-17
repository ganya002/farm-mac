import AppKit
import FarmCore
import SwiftUI

/// Beginner path: drop or pick a file, press Send. The steps play out in the big card.
struct SendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send a render").font(Theme.font(32, .medium)).kerning(-0.4)
                    Text("Drop your Blender file. The app finds its textures and sends everything to the farm.")
                        .font(Theme.font(15)).foregroundStyle(Theme.onSurfaceVariant)
                }
                if model.finder.status == .notFound || model.finder.status == .denied {
                    FarmProblem(status: model.finder.status, compact: true)
                        .transition(Motion.rise(reduce))
                }
                Hero()
                if let job = model.job {
                    Steps(phase: job.phase).transition(Motion.rise(reduce))
                }
                if model.job == nil {
                    RecentFiles().transition(Motion.rise(reduce))
                }
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(Motion.settle(reduce), value: model.finder.status)
        .animation(Motion.settle(reduce), value: model.job == nil)
    }
}

// MARK: - The big card

struct Hero: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var space
    @State private var targeted = false

    var body: some View {
        ZStack {
            if let job = model.job {
                JobCard(job: job, space: space).transition(.opacity)
            } else if let url = model.selection {
                PickedCard(url: url, space: space).transition(.opacity)
            } else {
                DropZone(targeted: targeted).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .background {
            RoundedRectangle(cornerRadius: Theme.panel, style: .continuous)
                .fill(targeted ? Theme.primaryContainer : Theme.card)
        }
        .overlay {
            if model.job == nil && model.selection == nil {
                RoundedRectangle(cornerRadius: Theme.panel, style: .continuous)
                    .strokeBorder(targeted ? Theme.primary : Theme.outlineVariant,
                                  style: StrokeStyle(lineWidth: 2, dash: targeted ? [] : [8, 7]))
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(Motion.spatial(reduce), value: targeted)
        .animation(Motion.settle(reduce), value: model.selection)
        .animation(Motion.settle(reduce), value: model.job?.phase)
        .dropDestination(for: URL.self) { urls, _ in
            guard let blend = urls.first(where: { $0.pathExtension.lowercased() == "blend" }) else { return false }
            model.open(blend, send: false)
            return true
        } isTargeted: { targeted = $0 }
    }
}

struct DropZone: View {
    let targeted: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false

    var body: some View {
        Button(action: model.choose) {
            VStack(spacing: 14) {
                Image(systemName: targeted ? "arrow.down" : "arrow.down.doc.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(targeted ? Theme.card : Theme.primaryContainer))
                    .scaleEffect(targeted ? 1.12 : (hover ? 1.05 : 1))
                    .contentTransition(.symbolEffect(.replace))
                Text(targeted ? "Let go to add it" : "Drop your Blender file here")
                    .font(Theme.font(22, .medium))
                    .contentTransition(.opacity)
                Text("or click to choose one, or pick a recent file below")
                    .font(Theme.font(14)).foregroundStyle(Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .animation(Motion.spatial(reduce), value: hover)
        .animation(Motion.spatial(reduce), value: targeted)
    }
}

/// A file is chosen: its preview, where it is, and the one button that matters.
struct PickedCard: View {
    let url: URL
    let space: Namespace.ID
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            BlendThumb(url: url, width: 240)
                .matchedGeometryEffect(id: "thumb", in: space)
            VStack(alignment: .leading, spacing: 6) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(Theme.font(26, .medium)).lineLimit(2)
                    .matchedGeometryEffect(id: "title", in: space)
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(url.deletingLastPathComponent().lastPathComponent)
                    if let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                        Text("·")
                        Text("edited \(date, format: .relative(presentation: .named))")
                    }
                }
                .font(Theme.font(13)).foregroundStyle(Theme.onSurfaceVariant).lineLimit(1)
                .help(url.path)
                Text("Ready to go. Textures are collected for you.")
                    .font(Theme.font(14)).foregroundStyle(Theme.onSurfaceVariant)
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    Button(action: model.send) {
                        Label("Send to farm", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .matchedGeometryEffect(id: "action", in: space)
                    Button("Choose Another…", action: model.choose)
                        .buttonStyle(PillButtonStyle(prominent: false, large: false))
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .overlay(alignment: .topTrailing) {
            Button { model.selection = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .help("Clear")
                .padding(14)
        }
    }
}

/// Sending: collecting → (missing files) → uploading → done, all in place.
struct JobCard: View {
    let job: SendJob
    let space: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            ZStack(alignment: .bottomTrailing) {
                BlendThumb(url: job.blend, width: 200)
                    .matchedGeometryEffect(id: "thumb", in: space)
                if case .done = job.phase {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.success))
                        .overlay(Circle().stroke(Theme.card, lineWidth: 4))
                        .offset(x: 14, y: 14)
                        .transition(reduce ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text(job.name).font(Theme.font(24, .medium)).lineLimit(1)
                    .matchedGeometryEffect(id: "title", in: space)
                phase
                    .transition(Motion.rise(reduce))
                    .id(phaseKey)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(26)
    }

    /// Changes only when the step changes (not on every progress tick), so steps rise in once.
    private var phaseKey: String {
        switch job.phase {
        case .collecting: "collecting"
        case .review: "review"
        case .uploading: "uploading"
        case .done: "done"
        case .failed: "failed"
        }
    }

    @ViewBuilder private var phase: some View {
        switch job.phase {
        case .collecting(let done, let total):
            HStack(spacing: 16) {
                ProgressRing(fraction: total > 0 ? Double(done) / Double(total) : nil, size: 64,
                             label: total > 0 ? "\(done)" : nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(total > 0 ? "Collecting textures…" : "Opening your file…").font(Theme.font(17, .medium))
                    Text(total > 0 ? "\(done) of \(total) files" : "Blender is reading it in the background")
                        .font(Theme.font(14)).foregroundStyle(Theme.onSurfaceVariant)
                        .contentTransition(.numericText(value: Double(done)))
                }
            }
            cancel
        case .review:
            Review(job: job)
        case .uploading:
            VStack(alignment: .leading, spacing: 10) {
                Text(job.retrying ? "Connection lost, reconnecting…" : "Uploading…")
                    .font(Theme.font(17, .medium))
                    .foregroundStyle(job.retrying ? Theme.tertiary : Theme.onSurface)
                Bar(fraction: job.total > 0 ? Double(job.sent) / Double(job.total) : 0)
                    .matchedGeometryEffect(id: "action", in: space)
                Text("\(bytes(job.sent)) of \(bytes(job.total))")
                    .font(Theme.font(13)).foregroundStyle(Theme.onSurfaceVariant)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(job.sent)))
            }
            cancel
        case .done:
            VStack(alignment: .leading, spacing: 4) {
                Text("Sent!").font(Theme.font(20, .medium)).foregroundStyle(Theme.success)
                Text("Your render is on the farm. Opening its page…")
                    .font(Theme.font(14)).foregroundStyle(Theme.onSurfaceVariant)
            }
        case .failed(let message):
            Label {
                Text(message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.error)
            }
            .font(Theme.font(15))
            HStack(spacing: 10) {
                Button("Try Again", action: job.retry).buttonStyle(PillButtonStyle(large: false))
                Button("Cancel", action: job.cancel).buttonStyle(PillButtonStyle(prominent: false, large: false))
            }
        }
    }

    private var cancel: some View {
        Button("Cancel", action: job.cancel).buttonStyle(LinkButtonStyle()).padding(.top, 2)
    }

    private func bytes(_ count: Int64) -> String {
        let format = ByteCountFormatter()
        format.allowsNonnumericFormatting = false   // "0 KB", not "Zero KB"
        return format.string(fromByteCount: count)
    }
}

/// Files Blender couldn't find on this Mac, each with Find….
struct Review: View {
    let job: SendJob

    var body: some View {
        let total = job.report?.items.count ?? 0
        let missing = job.stillMissing
        VStack(alignment: .leading, spacing: 12) {
            Text(missing.isEmpty ? "Every file is ready" : "\(total - missing.count) of \(total) files are ready")
                .font(Theme.font(17, .medium))
            if !missing.isEmpty {
                Text("These aren't on this Mac. The farm will look for them too, or you can find them now.")
                    .font(Theme.font(13)).foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(missing.prefix(4)) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Theme.tertiary)
                            Text(item.name).font(Theme.font(14)).lineLimit(1).truncationMode(.middle).help(item.original)
                            Spacer(minLength: 8)
                            Button("Find…") { job.find(item) }.buttonStyle(LinkButtonStyle())
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        if item.id != missing.prefix(4).last?.id { Divider().overlay(Theme.outlineVariant) }
                    }
                    if missing.count > 4 {
                        Text("and \(missing.count - 4) more").font(Theme.font(13)).foregroundStyle(Theme.onSurfaceVariant)
                            .padding(.vertical, 8)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Theme.inner - 4, style: .continuous).fill(Theme.surfaceHigh))
            }
            HStack(spacing: 10) {
                Button(missing.isEmpty ? "Send" : "Send Anyway", action: job.sendAnyway)
                    .buttonStyle(PillButtonStyle(large: false))
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", action: job.cancel).buttonStyle(PillButtonStyle(prominent: false, large: false))
            }
        }
    }
}

/// Collect → Upload → Render, with a sliding highlight on the current step.
struct Steps: View {
    let phase: SendJob.Phase
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var space

    private var current: Int {
        switch phase {
        case .collecting, .review: 0
        case .uploading: 1
        case .done: 2
        case .failed: -1
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            step(0, "Collect textures", "photo.on.rectangle.angled")
            line(done: current > 0)
            step(1, "Upload", "arrow.up")
            line(done: current > 1)
            step(2, "Render on the farm", "sparkles")
        }
        .padding(8)
        .background(Capsule().fill(Theme.card))
        .frame(maxWidth: .infinity)
        .animation(Motion.spatial(reduce), value: current)
    }

    private func step(_ index: Int, _ title: String, _ icon: String) -> some View {
        let done = current > index
        let now = current == index
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark" : icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(done ? Theme.onPrimary : (now ? Theme.onPrimary : Theme.onSurfaceVariant))
                .frame(width: 26, height: 26)
                .background(Circle().fill(done ? Theme.success : (now ? Theme.primary : Theme.surfaceHigh)))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(Theme.font(14, now ? .medium : .regular))
                .foregroundStyle(now ? Theme.onPrimaryContainer : Theme.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 4)
        .background {
            if now { Capsule().fill(Theme.primaryContainer).matchedGeometryEffect(id: "now", in: space) }
        }
    }

    private func line(done: Bool) -> some View {
        Capsule().fill(done ? Theme.success : Theme.outlineVariant).frame(height: 2).frame(minWidth: 12, maxWidth: 40)
    }
}

// MARK: - Recent files

struct RecentFiles: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 700

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent files", systemImage: "clock")
                    .labelStyle(TintedIconLabel())
                    .font(Theme.font(15, .medium)).foregroundStyle(Theme.onSurfaceVariant)
                Spacer()
                Button("Choose another file…", action: model.choose).buttonStyle(LinkButtonStyle())
            }
            if model.library.blends.isEmpty {
                Text("Your Blender files will show up here.")
                    .font(Theme.font(14)).foregroundStyle(Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.card.opacity(0.6)))
            } else {
                // One row: as many cards as fit (3 to 6), so the window never scrolls for them.
                let count = min(6, max(3, Int((width + 14) / (150 + 14))))
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.library.blends.prefix(count)) { blend in
                        RecentCard(blend: blend, chosen: model.selection == blend.url).frame(maxWidth: .infinity)
                    }
                    // Keep card widths equal when there are fewer files than slots.
                    ForEach(0..<max(0, count - model.library.blends.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
        }
    }
}

struct TintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(Theme.primary)
            configuration.title
        }
    }
}

struct RecentCard: View {
    let blend: BlendLibrary.Blend
    let chosen: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false

    var body: some View {
        Button {
            withAnimation(Motion.settle(reduce)) { model.selection = blend.url }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                BlendThumb(url: blend.url, width: nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blend.name).font(Theme.font(14, .medium)).lineLimit(1)
                    Text(blend.modified, format: .relative(presentation: .named))
                        .font(Theme.font(12)).foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius - 4, style: .continuous)
                .fill(hover || chosen ? Theme.cardHover : Theme.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius - 4, style: .continuous)
                    .strokeBorder(Theme.primary, lineWidth: chosen ? 2 : 0)
            }
            .shadow(color: .black.opacity(hover ? 0.12 : 0), radius: 14, y: 6)
            .scaleEffect(hover ? 1.03 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius - 4, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .animation(Motion.spatial(reduce), value: hover)
        .animation(Motion.effects(reduce), value: chosen)
        .help(blend.url.path)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.send() })
    }
}

// MARK: - Pieces

/// The .blend's own preview, 4:3, or a soft placeholder while it loads.
struct BlendThumb: View {
    let url: URL
    let width: CGFloat?
    @Environment(AppModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.inner - 4, style: .continuous)
        ZStack {
            shape.fill(Theme.surfaceHigh)
            if let image = model.library.thumbnails[url] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "cube.transparent").font(.system(size: 28)).foregroundStyle(Theme.outline)
            }
        }
        .frame(width: width)
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(shape)
        .animation(.easeOut(duration: 0.2), value: model.library.thumbnails[url] != nil)
        .task(id: url) { await model.library.loadThumbnail(for: url) }
    }
}

/// Circular progress; spins when the total isn't known yet.
struct ProgressRing: View {
    let fraction: Double?
    var size: CGFloat = 54
    var label: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.surfaceHigh, lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: fraction ?? 0.28)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && spin ? 360 : 0)))
                .animation(Motion.settle(reduce), value: fraction)
            if let label {
                Text(label).font(Theme.font(size * 0.3, .medium)).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard fraction == nil, !reduce else { return }
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "Working")
    }
}

/// The upload bar.
struct Bar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceHigh)
                Capsule().fill(Theme.primary)
                    .frame(width: max(12, box.size.width * min(1, max(0, fraction))))
                    .animation(Motion.settle(reduce), value: fraction)
            }
        }
        .frame(height: 12)
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
