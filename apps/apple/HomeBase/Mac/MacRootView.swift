import SwiftUI

enum MacTab: String, CaseIterable, Identifiable {
    case home = "Home", media = "Media", lights = "Lights", scenes = "Scenes", vault = "Vault", pages = "Pages"
    var id: String { rawValue }
    /// Vault and Pages are Josh's other apps; they show dimmed until they're wired in.
    var dimmed: Bool { self == .vault || self == .pages }
}

/// The Mac window from the v3 mockup: one tall black page, a full-bleed hero with the header
/// floating over it, then shelves. Also runs on iPad-sized windows later.
struct MacRootView: View {
    @Environment(HubStore.self) private var hub
    @State private var tab: MacTab = .home
    @State private var palette = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .home: MacHomeView(tab: $tab)
                case .media: MacPage { LaunchGrid(columns: 4) }
                case .lights: MacPage { ComingSoon(title: "Lights", icon: "lightbulb", note: "Philips Hue arrives in milestone 5.") }
                case .scenes: MacPage { ComingSoon(title: "Scenes", icon: "sparkles.rectangle.stack", note: "Movie night, Game time and Wind down arrive in milestone 6.") }
                case .vault: MacPage { ComingSoon(title: "Vault", icon: "books.vertical", note: "Your Knowledge vault will live here.") }
                case .pages: MacPage { ComingSoon(title: "Pages", icon: "doc.richtext", note: "Your Pages app will live here.") }
                }
            }
            .transition(.opacity)

            MacHeader(tab: $tab, palette: $palette)
        }
        .animation(Theme.settle, value: tab)
        .frame(minWidth: 900, minHeight: 640)
        .foregroundStyle(Theme.label)
        .overlay(alignment: .bottom) { Toast() }
        .overlay {
            if palette {
                CommandPalette(isPresented: $palette, tab: $tab)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(Theme.lift, value: palette)
        .background {
            // ⌘K from anywhere in the window.
            Button("Search or run an action") { palette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// Header row: name and hub link, the glass tab capsule, and the ⌘K search.
struct MacHeader: View {
    @Environment(HubStore.self) private var hub
    @Binding var tab: MacTab
    @Binding var palette: Bool
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                Text("Home Base").font(.system(size: 17, weight: .semibold))
                LinkBadge()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(MacTab.allCases) { t in
                    let sel = tab == t
                    Button { tab = t } label: {
                        Text(t.rawValue)
                            .font(.system(size: 14, weight: sel ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(sel ? Color.black : Color.white.opacity(t.dimmed ? 0.45 : 0.85))
                            .padding(.horizontal, sel ? 18 : 16)
                            .frame(minHeight: 36)
                            .background {
                                if sel { Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            .padding(4)
            .glass(in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            .fixedSize()
            .layoutPriority(1)
            .animation(Theme.lift, value: tab)

            Button { palette = true } label: {
                HStack(spacing: 10) {
                    Text("Search or run an action")
                    Text("⌘K").foregroundStyle(.white.opacity(0.6)).font(.system(size: 12))
                }
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .glass(in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressButtonStyle())
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // Leave room for the window's traffic lights on the left.
        .padding(.leading, 84)
        .padding(.trailing, 32)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background {
            // Content scrolls away under a dark fade, as on Apple TV, so the header stays readable.
            LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -36)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// "● Live with the hub" in a small glass capsule.
struct LinkBadge: View {
    @Environment(HubStore.self) private var hub

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .glass(in: Capsule())
        .help(help)
    }

    private var text: String {
        switch hub.link {
        case .demo: return "Demo"
        case .connecting: return "Connecting…"
        case .live: return "Live · \(hub.devices.count) devices"
        case .offline: return "Hub offline"
        }
    }

    private var color: Color {
        switch hub.link {
        case .live: return Theme.live
        case .offline: return .orange
        default: return Theme.faint
        }
    }

    private var help: String {
        if case .offline(let why) = hub.link { return why }
        return "Hub address and devices are in Settings (⌘,)"
    }
}

/// A page under the header for tabs other than Home.
struct MacPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 48)
                .padding(.top, 110)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    MacRootView()
        .environment(HubStore.demo())
        .environment(Selection())
        .preferredColorScheme(.dark)
        .frame(width: 1280, height: 860)
}
