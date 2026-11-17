import AppKit
import SwiftUI

/// The one window: a slim top bar (tabs, farm status, settings) over Send or My renders.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ZStack {
                // Both stay alive so the web view keeps its page while the student is on Send.
                SendView()
                    .opacity(model.tab == .send ? 1 : 0)
                    .offset(x: model.tab == .send || reduce ? 0 : -40)
                    .allowsHitTesting(model.tab == .send)
                RendersView()
                    .opacity(model.tab == .renders ? 1 : 0)
                    .offset(x: model.tab == .renders || reduce ? 0 : 40)
                    .allowsHitTesting(model.tab == .renders)
            }
        }
        .ignoresSafeArea(edges: .top)   // the bar shares the title bar's line with the window buttons
        .background(Theme.background.ignoresSafeArea())
        .font(Theme.font(15))
        .foregroundStyle(Theme.onSurface)
        .tint(Theme.primary)
        .onChange(of: model.finder.url, initial: true) { model.serverChanged() }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Sits on the title bar line, centred on the window buttons (hidden title bar).
        ZStack {
            TabSwitch()
            HStack(spacing: 6) {
                Spacer()
                StatusPill(status: model.finder.status)
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(IconButtonStyle())
                    .help("Settings")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .padding(.bottom, 10)
    }
}

/// "Send" / "My renders" with a sliding pill under the chosen one.
struct TabSwitch: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            item(.send, "Send", "paperplane.fill")
            item(.renders, "My renders", "photo.stack.fill")
        }
        .padding(3)
        .background(Capsule().fill(Theme.surfaceHigh))
    }

    private func item(_ tab: AppModel.Tab, _ title: String, _ icon: String) -> some View {
        let chosen = model.tab == tab
        return Button {
            withAnimation(Motion.spatial(reduce)) { model.tab = tab }
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.font(14, .medium))
                .padding(.horizontal, 16)
                .frame(height: 30)
                .foregroundStyle(chosen ? Theme.onPrimaryContainer : Theme.onSurfaceVariant)
                .background {
                    if chosen { Capsule().fill(Theme.primaryContainer).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
    }
}

/// Squashes a little on press; for buttons that draw their own look.
struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.spatial(reduce), value: configuration.isPressed)
    }
}

/// Farm connected / looking / not found, with a breathing dot.
struct StatusPill: View {
    let status: ServerFinder.Status
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var text: String {
        switch status {
        case .connected: "Farm connected"
        case .searching: "Looking for the farm"
        case .notFound: "Farm not found"
        case .denied: "Network access off"
        }
    }

    private var color: Color {
        switch status {
        case .connected: Theme.success
        case .searching: Theme.tertiary
        case .notFound, .denied: Theme.error
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            PulseDot(color: color, pulsing: status != .notFound && status != .denied && !reduce, fast: status == .searching)
            Text(text)
                .font(Theme.font(13, .medium))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Theme.surfaceHigh))
        .animation(Motion.effects(reduce), value: status)
        .accessibilityElement(children: .combine)
    }
}

struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    var fast = false
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35))
                .scaleEffect(on ? 2.2 : 1)
                .opacity(on ? 0 : 1)
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onChange(of: pulsing, initial: true) { restart() }
        .onChange(of: fast) { restart() }
    }

    private func restart() {
        on = false
        guard pulsing else { return }
        withAnimation(.easeOut(duration: fast ? 1.0 : 1.8).repeatForever(autoreverses: false)) { on = true }
    }
}

/// The farm's own website: job status and renders.
struct RendersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.finder.url != nil {
                SiteView(webView: model.webView)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.panel, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: Theme.panel, style: .continuous).fill(Theme.surface))
            } else {
                FarmProblem(status: model.finder.status, compact: false)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding([.horizontal, .bottom], 16)
    }
}

/// What to do when the farm can't be reached. Compact: a banner on the Send tab.
struct FarmProblem: View {
    let status: ServerFinder.Status
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let (icon, title, detail) = words
        Group {
            if compact {
                HStack(spacing: 14) {
                    badge(icon, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.font(15, .medium))
                        Text(detail).font(Theme.font(13)).foregroundStyle(Theme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    action.buttonStyle(PillButtonStyle(prominent: false, large: false))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Theme.inner + 4, style: .continuous).fill(Theme.card))
            } else {
                VStack(spacing: 14) {
                    if status == .searching {
                        ProgressRing(fraction: nil, size: 64)
                    } else {
                        badge(icon, size: 64)
                    }
                    Text(title).font(Theme.font(22, .medium))
                    Text(detail).font(Theme.font(15)).foregroundStyle(Theme.onSurfaceVariant)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if status != .searching { action.buttonStyle(PillButtonStyle(large: false)).padding(.top, 6) }
                }
            }
        }
    }

    private var words: (String, String, String) {
        switch status {
        case .denied:
            ("lock.shield", "Let Render Farm use the network",
             "macOS is blocking it from finding the farm. Turn on Render Farm under Local Network, then come back.")
        case .searching:
            ("antenna.radiowaves.left.and.right", "Looking for the farm…", "This takes a few seconds on the school Wi-Fi.")
        default:
            ("wifi.exclamationmark", "Can't find the farm",
             "Make sure this Mac is on the school Wi-Fi. The farm may also be switched off.")
        }
    }

    @ViewBuilder private var action: some View {
        if status == .denied {
            Button("Open Settings") { ServerFinder.openLocalNetworkSettings() }
        } else {
            Button("Try Again") { model.finder.start() }
        }
    }

    private func badge(_ icon: String, size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Theme.onErrorContainer)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.errorContainer))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ServerFinder.manualKey) private var manual = ""

    var body: some View {
        Form {
            Section {
                TextField("Farm address", text: $manual, prompt: Text("Found automatically"))
                    .onSubmit { Task { await model.finder.refresh() } }
                LabeledContent("Using", value: model.finder.url?.absoluteString ?? "Not found yet")
            } footer: {
                Text("Leave the address empty to find the farm on the school network by itself.")
            }
            Section {
                Button("Search for the Farm Again") { model.finder.start() }
                Button("Local Network Settings…") { ServerFinder.openLocalNetworkSettings() }
                Button("Show Logs") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: manual) { Task { await model.finder.refresh() } }
    }
}
