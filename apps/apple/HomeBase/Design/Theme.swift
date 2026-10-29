import SwiftUI

/// The v3 "Apple TV style" look: black ground, white text, white means on.
enum Theme {
    static let ground = Color.black
    static let label = Color.white
    /// iOS's dark secondary label (#EBEBF5) at the mockup's opacities.
    static let secondary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.7)
    static let tertiary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    static let faint = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.35)
    static let fill = Color.white.opacity(0.10)
    static let fillSoft = Color.white.opacity(0.07)
    static let fillStrong = Color.white.opacity(0.14)
    static let live = Color(red: 0x5F / 255, green: 0xD0 / 255, blue: 0x8A / 255)
    static let gutter: CGFloat = 20

    static let lift = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let settle = Animation.smooth(duration: 0.35)
    /// A screen card growing into the hero, and back.
    static let zoom = Animation.spring(response: 0.62, dampingFraction: 0.86)
    /// The remote sliding up from the bottom and tucking back down.
    static let sheet = Animation.spring(response: 0.5, dampingFraction: 0.84)
}

extension Font {
    static let heroTitle = Font.system(size: 34, weight: .bold)
    static let shelfTitle = Font.system(size: 20, weight: .semibold)
    static let cardTitle = Font.system(size: 14, weight: .semibold)
}

// MARK: Glass

extension View {
    /// Liquid Glass on iOS/macOS 26, the closest material before that.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

// MARK: Buttons

/// Cards that lift toward you when chosen, pressed or hovered, like focus on Apple TV.
struct LiftButtonStyle: ButtonStyle {
    var lifted = false

    func makeBody(configuration: Configuration) -> some View {
        LiftBody(configuration: configuration, lifted: lifted)
    }

    private struct LiftBody: View {
        let configuration: Configuration
        let lifted: Bool
        @State private var hovering = false

        var body: some View {
            let up = lifted || hovering
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : (up ? 1.05 : 1))
                .shadow(color: .black.opacity(up ? 0.6 : 0), radius: up ? 18 : 0, y: up ? 14 : 0)
                .animation(Theme.lift, value: configuration.isPressed)
                .animation(Theme.lift, value: up)
                .onHover { hovering = $0 }
        }
    }
}

/// A soft squeeze for plain controls.
struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.lift, value: configuration.isPressed)
    }
}

/// Capsule buttons. Primary is solid white (white means on or go); the rest are glass.
struct Pill: View {
    enum Style { case primary, glass, quiet }

    let title: String
    var icon: String? = nil
    var style: Style = .glass
    var height: CGFloat = 48
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).tint(style == .primary ? .black : .white)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.system(size: height > 40 ? 16 : 13, weight: .semibold))
            }
            .padding(.horizontal, height > 40 ? 24 : 14)
            .frame(minHeight: height)
            .foregroundStyle(style == .primary ? Color.black : Color.white)
            .background {
                switch style {
                case .primary: Capsule().fill(.white)
                case .glass: Capsule().fill(.clear).glass(in: Capsule())
                case .quiet: Capsule().fill(Theme.fill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressButtonStyle())
    }
}

/// A round icon button. `on` fills it white.
struct RoundButton: View {
    let icon: String
    let label: String
    var on = false
    var size: CGFloat = 44
    var busy = false
    var glass = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).tint(on ? .black : .white)
                } else {
                    Image(systemName: icon).font(.system(size: size * 0.38, weight: .semibold))
                }
            }
            .frame(width: size, height: size)
            .foregroundStyle(on ? Color.black : Color.white)
            .background {
                if on { Circle().fill(.white) }
                else if glass { Circle().fill(.clear).glass(in: Circle()) }
                else { Circle().fill(Theme.fill) }
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel(label)
        .animation(Theme.settle, value: on)
    }
}

// MARK: Shelves

/// A titled horizontal row that scrolls edge to edge with no visible scroll bar.
struct Shelf<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var onTrailing: (() -> Void)? = nil
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content
    @Environment(\.shelfGutter) private var gutter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(gutter > Theme.gutter ? .system(size: 22, weight: .semibold) : .shelfTitle).kerning(-0.4)
                Spacer()
                if let trailing, let onTrailing {
                    Button(trailing, action: onTrailing)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: spacing) { content }
                    .padding(.horizontal, gutter)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

extension EnvironmentValues {
    /// Side margin for shelves: 20 on iPhone, wider on Mac.
    @Entry var shelfGutter: CGFloat = Theme.gutter
}

/// The artwork wash behind a hero or a card.
struct ArtworkView: View {
    let art: Artwork

    var body: some View {
        ZStack {
            art.base
            RadialGradient(colors: [art.glow.opacity(0.55), .clear], center: UnitPoint(x: 0.72, y: 0.18),
                           startRadius: 0, endRadius: 420)
            RadialGradient(colors: [art.glow.opacity(0.25), .clear], center: UnitPoint(x: 0.1, y: 0.9),
                           startRadius: 0, endRadius: 300)
        }
        .animation(Theme.settle, value: art)
    }
}

// MARK: Entrances

extension View {
    /// Rises into place a moment after it appears, so rows follow the hero in.
    func riseIn(delay: Double = 0, from offset: CGFloat = 60) -> some View {
        modifier(RiseIn(delay: delay, offset: offset))
    }
}

private struct RiseIn: ViewModifier {
    let delay: Double
    let offset: CGFloat
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : offset)
            .onAppear { withAnimation(Theme.zoom.delay(delay)) { shown = true } }
    }
}
