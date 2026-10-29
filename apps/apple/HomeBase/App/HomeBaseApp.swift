import SwiftUI

@main
struct HomeBaseApp: App {
    @State private var hub = HubStore()
    @State private var selection = Selection()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                MacRootView()
                #else
                AdaptiveRoot()
                #endif
            }
            .homeBase(hub, selection)
            .onAppear { hub.start() }
            .onChange(of: phase) { _, now in
                if now == .active { hub.resume() }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        .windowStyle(.hiddenTitleBar)
        #endif

        #if os(macOS)
        // A small remote you can keep beside your work. Arrow keys, Return and Esc drive the TV.
        WindowGroup("Remote", id: "remote", for: String.self) { $screen in
            RemoteView(screenID: screen ?? selection.screen, showsBack: false)
                .homeBase(hub, selection)
        }
        .defaultSize(width: 400, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Settings {
            HubView()
                .frame(width: 520, height: 560)
                .homeBase(hub, selection)
        }
        #endif
    }
}

extension View {
    /// Shows the pairing screen whenever the hub doesn't know this device.
    func pairingSheet() -> some View { modifier(PairingSheet()) }
}

private struct PairingSheet: ViewModifier {
    @Environment(HubStore.self) private var hub

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { hub.needsPairing || hub.tryingWithoutKey }, set: { _ in })) {
            PairingView().interactiveDismissDisabled()
        }
    }
}

private extension View {
    func homeBase(_ hub: HubStore, _ selection: Selection) -> some View {
        self.environment(hub)
            .environment(selection)
            .preferredColorScheme(.dark)
            .tint(.white)
    }
}

#if os(iOS)
/// iPad (and a wide iPhone window) gets the Mac's tall page; iPhone gets its own tabs.
struct AdaptiveRoot: View {
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        if size == .regular { MacRootView() } else { RootView() }
    }
}
#endif

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home", screens = "Screens", launch = "Launch", lights = "Lights"
    var id: String { rawValue }
}

enum Route: Hashable {
    case remote(String)
    case hub
}

/// Picks which screen the app is talking about. Shared by every tab so they stay in step.
@MainActor
@Observable
final class Selection {
    var screen: String = UserDefaults.standard.string(forKey: "selectedScreen") ?? "lg" {
        didSet { UserDefaults.standard.set(screen, forKey: "selectedScreen") }
    }
}

struct RootView: View {
    @Environment(HubStore.self) private var hub
    @State private var tab: Tab = .home
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Theme.ground.ignoresSafeArea()
                Group {
                    switch tab {
                    case .home: HomeView(tab: $tab, path: $path)
                    case .screens: ScreensView(tab: $tab, path: $path)
                    case .launch: LaunchView(path: $path)
                    case .lights: LightsView()
                    }
                }
                .transition(.opacity)
                TabBar(tab: $tab)
                    .padding(.top, 8)
            }
            .animation(Theme.settle, value: tab)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .remote(let id): RemoteView(screenID: id)
                case .hub: HubView()
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .overlay(alignment: .bottom) { Toast() }
        .foregroundStyle(Theme.label)
        .pairingSheet()
    }
}

/// The floating glass capsule of tabs at the top, as on Apple TV.
struct TabBar: View {
    @Binding var tab: Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 14, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? Color.black : Color.white.opacity(0.85))
                        .padding(.horizontal, tab == t ? 16 : 14)
                        .frame(minHeight: 38)
                        .background {
                            if tab == t {
                                Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .animation(Theme.lift, value: tab)
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// A brief note at the bottom when a command fails. Successes need no message: the screen changes.
struct Toast: View {
    @Environment(HubStore.self) private var hub

    var body: some View {
        ZStack {
            if let f = hub.failure {
                Text(f.message)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glass(in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: f.id) {
                        try? await Task.sleep(for: .seconds(3.5))
                        if hub.failure == f { hub.failure = nil }
                    }
                    .onTapGesture { hub.failure = nil }
            }
        }
        .animation(Theme.lift, value: hub.failure)
        .sensoryFeedback(.error, trigger: hub.failure) { _, new in new != nil }
    }
}
