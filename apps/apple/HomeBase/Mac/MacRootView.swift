import SwiftUI

enum MacTab: String, CaseIterable, Identifiable {
    case home = "Home", media = "Media", lights = "Lights", scenes = "Scenes", vault = "Vault", pages = "Pages"
    var id: String { rawValue }
    /// Vault and Pages are Josh's other apps; they show dimmed until they're wired in.
    var dimmed: Bool { self == .vault || self == .pages }
}

/// The Mac and iPad layout from the v3 mockup: one tall black page, a full-bleed hero with the
/// header floating over it, then shelves. iPhone uses RootView instead.
struct MacRootView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Environment(\.openWindow) private var openWindow
    @State private var tab: MacTab = .home
    @State private var palette = false
    @State private var scrolled = false
    @State private var remoteFor: RemoteTarget?

    struct RemoteTarget: Identifiable { let id: String }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .home: MacHomeView(tab: $tab, scrolled: $scrolled)
                case .media: ScreenWall()
                case .lights: MacPage { ComingSoon(title: "Lights", icon: "lightbulb", note: "Philips Hue arrives in milestone 5.") }
                case .scenes: MacPage { ComingSoon(title: "Scenes", icon: "sparkles.rectangle.stack", note: "Movie night, Game time and Wind down arrive in milestone 6.") }
                case .vault: MacPage { ComingSoon(title: "Vault", icon: "books.vertical", note: "Your Knowledge vault will live here.") }
                case .pages: MacPage { ComingSoon(title: "Pages", icon: "doc.richtext", note: "Your Pages app will live here.") }
                }
            }
            .transition(.opacity)

            MacHeader(tab: $tab, palette: $palette, backdrop: tab != .home || scrolled)
        }
        .animation(Theme.settle, value: tab)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
        .pairingSheet()
        .sheet(item: $remoteFor) { target in
            RemoteView(screenID: target.id, showsBack: false)
                .presentationBackground(.black)
        }
        .foregroundStyle(Theme.label)
        .overlay(alignment: .bottom) {
            // A zoomed-in screen on Home gets the slide-up remote.
            if tab == .home, let id = selection.focused, let screen = hub.screen(id), screen.display != nil {
                RemoteSheet(screen: screen)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom))
            }
        }
        .onChange(of: tab) { _, _ in selection.remoteOpen = false }
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
        // On Mac the remote is its own window; on iPad it slides up as a sheet.
        .environment(\.openRemote, OpenRemote { id in
            #if os(macOS)
            openWindow(id: "remote", value: id)
            #else
            remoteFor = RemoteTarget(id: id)
            #endif
        })
    }
}

/// Header row: name and hub link, the glass tab capsule, and the ⌘K search.
struct MacHeader: View {
    @Environment(HubStore.self) private var hub
    @Binding var tab: MacTab
    @Binding var palette: Bool
    /// Off over the top of the Home hero so the artwork runs to the top edge, on once content scrolls under.
    var backdrop = true
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                Text("Home Base").font(.system(size: 17, weight: .semibold)).lineLimit(1).fixedSize()
                ViewThatFits(in: .horizontal) { LinkBadge(); Color.clear.frame(width: 0) }
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
                // Narrow windows (iPad portrait) keep just the magnifying glass.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text("Search or run an action")
                        Text("⌘K").foregroundStyle(.white.opacity(0.6)).font(.system(size: 12))
                    }
                    .fixedSize()
                    Image(systemName: "magnifyingglass").frame(width: 12)
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
        #if os(macOS)
        .padding(.leading, 84)
        #else
        .padding(.leading, 32)
        #endif
        .padding(.trailing, 32)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background {
            // Content scrolls away under a dark fade, as on Apple TV, so the header stays readable.
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                   .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -40)
                .ignoresSafeArea()
                .opacity(backdrop ? 1 : 0)
                .animation(Theme.settle, value: backdrop)
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
        case .live: return "Live · \(hub.devices.count) \(hub.devices.count == 1 ? "device" : "devices")"
        case .offline: return "Hub offline"
        case .needsPairing: return "Not paired"
        }
    }

    private var color: Color {
        switch hub.link {
        case .live: return Theme.live
        case .offline, .needsPairing: return .orange
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

/// Opens the remote for a screen: a window on Mac, a sheet on iPad.
struct OpenRemote {
    let action: (String) -> Void
    init(_ action: @escaping (String) -> Void) { self.action = action }
    func callAsFunction(_ screen: String) { action(screen) }
}

extension EnvironmentValues {
    @Entry var openRemote = OpenRemote { _ in }
}
