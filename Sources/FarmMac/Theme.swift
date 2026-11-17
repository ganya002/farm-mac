import AppKit
import CoreText
import SwiftUI

/// The farm site's look (site/src/app.css, rose theme; site/src/lib/motion.ts) in SwiftUI.
/// Dark values are the site's rose theme; light values are the same rose hue at light-scheme tones.
enum Theme {
    // MARK: Colours
    static let background = Color(light: 0xF8EDEC, dark: 0x0D0606)       // --surface-lowest
    static let surface = Color(light: 0xFFF8F7, dark: 0x140C0C)          // --surface
    static let card = Color(light: 0xFFFFFF, dark: 0x2C201F)             // --card
    static let cardHover = Color(light: 0xFDF1F0, dark: 0x352726)        // --card-hover
    static let surfaceHigh = Color(light: 0xF3E1E0, dark: 0x291F1F)      // --surface-high
    static let onSurface = Color(light: 0x231919, dark: 0xF0DEDD)
    static let onSurfaceVariant = Color(light: 0x6B5655, dark: 0xC1ACAB)
    static let outline = Color(light: 0x9C8584, dark: 0x857372)
    static let outlineVariant = Color(light: 0xE3CCCA, dark: 0x4E3F3E)
    static let primary = Color(light: 0x9A4645, dark: 0xFFB3B1)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x652829)
    static let primaryContainer = Color(light: 0xFFDAD8, dark: 0x733333)
    static let onPrimaryContainer = Color(light: 0x3B0809, dark: 0xFFDAD8)
    static let tertiary = Color(light: 0x8A5300, dark: 0xE3C28D)
    static let success = Color(light: 0x2F7A45, dark: 0xB1CFA9)
    static let successContainer = Color(light: 0xD6EFDC, dark: 0x344D30)
    static let onSuccessContainer = Color(light: 0x0B3A1A, dark: 0xCCEBC4)
    static let error = Color(light: 0xBA1A1A, dark: 0xFFB4AB)
    static let errorContainer = Color(light: 0xFFDAD6, dark: 0x93000A)
    static let onErrorContainer = Color(light: 0x410002, dark: 0xFFDAD6)

    // MARK: Shape
    static let panel: CGFloat = 28   // --r-panel
    static let cardRadius: CGFloat = 25
    static let inner: CGFloat = 18

    // MARK: Type (Rubik, OFL; bundled as Resources/Fonts/Rubik.woff2)
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Rubik", withExtension: "woff2", subdirectory: "Fonts")
            ?? devResource("Fonts/Rubik.woff2") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Rubik at a weight; falls back to the system font if the font didn't load.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .medium: "Rubik-Light_Medium"
        case .semibold: "Rubik-Light_SemiBold"
        case .bold, .heavy, .black: "Rubik-Light_Bold"
        default: "Rubik-Light_Regular"
        }
        return NSFont(name: name, size: size) == nil ? .system(size: size, weight: weight) : .custom(name, size: size, relativeTo: style)
    }

    nonisolated static func devResource(_ path: String) -> URL? {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("Resources").appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// The site's M3 Expressive curves. Under Reduce Motion everything becomes a short fade.
enum Motion {
    /// --spatial-fast, 350 ms: layout, scale, position.
    static func spatial(_ reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.12) : .timingCurve(0.42, 1.4, 0.21, 0.95, duration: 0.35)
    }

    /// --effects, 200 ms: colour and opacity.
    static func effects(_ reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.12) : .timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    }

    /// --spatial, 500 ms: big state changes of the main card.
    static func settle(_ reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.12) : .timingCurve(0.38, 1.21, 0.22, 1, duration: 0.5)
    }

    /// The site's `rise`: comes up 14 pt and settles; a plain fade under Reduce Motion.
    static func rise(_ reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .asymmetric(insertion: .offset(y: 14).combined(with: .scale(scale: 0.97)).combined(with: .opacity),
                                        removal: .scale(scale: 0.98).combined(with: .opacity))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Buttons

/// The big filled pill (the site's primary button): lifts on hover, squashes on press.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var large = true

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, prominent: prominent, large: large)
    }

    struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let large: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(Theme.font(large ? 17 : 14, .medium))
                .padding(.horizontal, large ? 28 : 16)
                .frame(minHeight: large ? 52 : 36)
                .foregroundStyle(prominent ? Theme.onPrimary : Theme.onSurface)
                .background {
                    if prominent {
                        Capsule().fill(Theme.primary)
                            .overlay { if hover { Capsule().fill(.white.opacity(0.1)) } }
                    } else {
                        Capsule().fill(hover ? Theme.surfaceHigh : .clear)
                            .overlay { Capsule().strokeBorder(Theme.outlineVariant, lineWidth: 1.5) }
                    }
                }
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : (hover && enabled ? 1.03 : 1))
                .opacity(enabled ? 1 : 0.45)
                .animation(Motion.spatial(reduce), value: configuration.isPressed)
                .animation(Motion.spatial(reduce), value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Small borderless text button in the primary colour.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Round icon button (gear, close).
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledBody(configuration: configuration) }

    struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.onSurfaceVariant)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hover ? Theme.cardHover : .clear))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(Motion.spatial(reduce), value: configuration.isPressed)
                .animation(Motion.effects(reduce), value: hover)
                .onHover { hover = $0 }
        }
    }
}
