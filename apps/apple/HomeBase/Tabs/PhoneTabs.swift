import SwiftUI

// The iPhone tabs beyond Home, from the v3 mockup.

struct ScreensView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var tab: Tab
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screens").font(.heroTitle).kerning(-0.8)
                    Text("\(hub.screens.filter(\.isOn).count) of \(hub.screens.count) screens on")
                        .font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                }
                ForEach(hub.screens) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            ArtworkView(art: s.art)
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.isOn ? s.title : s.short).font(.system(size: 18, weight: .bold))
                                Text(s.meta).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            .padding(16)
                        }
                        .frame(height: 196)
                        .overlay(alignment: .topTrailing) {
                            if let d = s.display, s.phase != .needsPairing {
                                RoundButton(icon: "power", label: (s.isOn ? "Turn off " : "Turn on ") + s.spot.name,
                                            on: s.isOn, size: 40, busy: hub.pending.contains(d.id), glass: true) {
                                    hub.setPower(d.id, on: !s.isOn)
                                }
                                .padding(14)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        HStack {
                            Text(s.spot.name).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if s.canControl {
                                Pill(title: "Remote", style: .quiet, height: 34) { path.append(Route.remote(s.id)) }
                                Pill(title: "Launch", style: .primary, height: 34) { selection.screen = s.id; tab = .launch }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 124)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

/// v3 Launch: pick the screen, pick the app, then one clear button that says what will happen.
struct LaunchView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var path: NavigationPath
    @State private var app: Device.Option?
    @State private var sent = false

    var body: some View {
        let screens = hub.screens
        let current = screens.first { $0.id == selection.screen } ?? screens[0]

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Launch").font(.heroTitle).kerning(-0.8).padding(.horizontal, Theme.gutter)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("PLAY ON").font(.system(size: 12, weight: .semibold)).kerning(0.6)
                            .foregroundStyle(Theme.tertiary).padding(.horizontal, Theme.gutter)
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(screens) { s in
                                    ScreenCard(screen: s, selected: s.id == current.id, width: 130) {
                                        selection.screen = s.id
                                        sent = false
                                        if let a = app, !s.apps.contains(a) { app = nil }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.gutter)
                            .padding(.vertical, 14)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Apps").font(.shelfTitle).kerning(-0.4)
                        if current.apps.isEmpty {
                            Text(current.phase == .notSetUp ? current.spot.arrives : "\(current.spot.name) has no apps to open.")
                                .font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 18) {
                                ForEach(current.apps) { a in
                                    let sel = app == a
                                    Button {
                                        app = sel ? nil : a
                                        sent = false
                                    } label: {
                                        VStack(spacing: 8) {
                                            Text(String(a.name.prefix(1)))
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundStyle(sel ? Color.black : Color.white)
                                                .frame(width: 64, height: 64)
                                                .background(sel ? Color.white : Theme.fill,
                                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                            Text(a.name).font(.system(size: 12)).lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(LiftButtonStyle(lifted: sel))
                                    .accessibilityAddTraits(sel ? .isSelected : [])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .padding(.top, 124)
                .padding(.bottom, 180)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            summary(current)
        }
        .animation(Theme.lift, value: app)
        .animation(Theme.settle, value: sent)
    }

    /// The bar at the bottom: what will happen, and the button that does it.
    private func summary(_ s: ScreenStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.map { "\($0.name) → \(s.spot.name)" } ?? "Pick something for \(s.spot.name)")
                    .font(.system(size: 16, weight: .semibold))
                Text(route(s)).font(.system(size: 13)).foregroundStyle(Theme.tertiary)
            }
            if sent {
                Pill(title: "Open remote for \(s.spot.name)", style: .primary) { path.append(Route.remote(s.id)) }
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    guard let app else { return }
                    hub.launch(app, on: s)
                    sent = true
                } label: {
                    Text(app == nil ? "Choose what to play" : "Play on \(s.spot.name)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(app == nil ? Theme.tertiary : Color.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(app == nil ? Theme.fill : Color.white, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressButtonStyle())
                .disabled(app == nil)
            }
        }
        .padding(18)
        .glass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func route(_ s: ScreenStatus) -> String {
        guard app != nil, let player = s.player else { return "Change the screen at the top at any time" }
        let on = s.isOn ? "" : " · \(s.spot.name) turns on"
        return player.id == s.display?.id ? "\(player.name) built-in app\(on)" : "Through \(player.name)\(on)"
    }
}

struct LightsView: View {
    var body: some View {
        ScrollView {
            ComingSoon(title: "Lights", icon: "lightbulb", note: "Philips Hue arrives in milestone 5.")
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 124)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}
