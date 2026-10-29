import SwiftUI

/// Home: the chosen screen as a full-bleed hero, then shelves of screens and things to open.
struct HomeView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var tab: Tab
    @Binding var path: NavigationPath
    @State private var picking = false

    var body: some View {
        let screens = hub.screens
        let current = screens.first { $0.id == selection.screen } ?? screens[0]

        GeometryReader { geo in
            let wide = geo.size.width > 700
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Hero(screen: current, height: wide ? 520 : 440, topInset: geo.safeAreaInsets.top,
                         pick: { picking = true },
                         remote: { path.append(Route.remote(current.id)) },
                         launch: { tab = .launch })

                    Shelf(title: "Screens", trailing: "See all", onTrailing: { tab = .screens }) {
                        ForEach(screens) { s in
                            ScreenCard(screen: s, selected: s.id == current.id, width: wide ? 220 : 150) {
                                selection.screen = s.id
                            }
                        }
                    }
                    .padding(.top, 6)

                    if !current.apps.isEmpty {
                        Shelf(title: "Open on \(current.spot.name)", spacing: 14) {
                            ForEach(current.apps) { app in
                                AppCard(app: app, width: wide ? 240 : 200,
                                        playing: current.isOn && current.title == app.name) {
                                    hub.launch(app, on: current)
                                }
                            }
                        }
                    }

                    QuickTiles(path: $path)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 48)
                        .frame(maxWidth: 720, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .sheet(isPresented: $picking) {
            ScreenPicker(current: current.id) { id in
                selection.screen = id
                picking = false
            }
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(28)
        }
        .sensoryFeedback(.selection, trigger: selection.screen)
    }
}

/// The selected screen, full bleed, with what's on it and what you can do.
struct Hero: View {
    @Environment(HubStore.self) private var hub
    let screen: ScreenStatus
    let height: CGFloat
    let topInset: CGFloat
    let pick: () -> Void
    let remote: () -> Void
    let launch: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(art: screen.art)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 0.78),
                                   .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                Button(action: pick) {
                    HStack(spacing: 6) {
                        Text("ON \(screen.spot.name.uppercased())")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.4)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .glass(in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressButtonStyle())
                .accessibilityLabel("Showing \(screen.spot.name). Choose a screen")

                Text(screen.title)
                    .font(.heroTitle)
                    .kerning(-0.8)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text(screen.meta)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.opacity)

                actions.padding(.top, 6)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 26)
            .animation(Theme.settle, value: screen.title)
        }
        .frame(height: height + topInset)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder private var actions: some View {
        let busy = screen.display.map { hub.pending.contains($0.id) } ?? false
        HStack(spacing: 10) {
            switch screen.phase {
            case .on:
                Pill(title: "Remote", style: .primary, action: remote)
                Pill(title: "Launch", action: launch)
                if let d = screen.display {
                    RoundButton(icon: "power", label: "Turn off \(screen.spot.name)", size: 48, busy: busy, glass: true) {
                        hub.setPower(d.id, on: false)
                    }
                }
            case .off, .unreachable:
                Pill(title: "Launch here", style: .primary, action: launch)
                if let d = screen.display {
                    Pill(title: "Turn on", icon: "power", busy: busy) { hub.setPower(d.id, on: true) }
                }
            case .needsPairing:
                if let d = screen.display {
                    Pill(title: busy ? "Press Yes on the TV" : "Pair", style: .primary, busy: busy) { hub.pair(d.id) }
                }
            case .notSetUp:
                EmptyView()
            }
        }
    }
}

/// A screen in the shelf: a small window onto what it's showing.
struct ScreenCard: View {
    let screen: ScreenStatus
    let selected: Bool
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(art: screen.art)
                    Text(screen.isOn ? screen.title : "")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    if screen.isOn {
                        Circle().fill(.white).frame(width: 6, height: 6)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: width, height: width * 0.587)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white, lineWidth: selected ? 2 : 0)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(screen.spot.name).font(.cardTitle)
                    Text(screen.short).font(.system(size: 12)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(LiftButtonStyle(lifted: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(screen.spot.name), \(screen.short)")
    }
}

/// An app you can open on the selected screen. Opening it turns the screen on if needed.
struct AppCard: View {
    let app: Device.Option
    let width: CGFloat
    let playing: Bool
    /// Replaces "APP" over the artwork, for example with the screen it opens on.
    var caption: String? = nil
    let action: () -> Void

    var body: some View {
        let art = Artwork(app: app.id + " " + app.name)
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: art)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playing ? "PLAYING" : (caption ?? "App").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.4)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text(app.name).font(.system(size: 19, weight: .semibold)).kerning(-0.3)
                }
                .padding(16)
            }
            .frame(width: width, height: width * 0.55)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(LiftButtonStyle(lifted: playing))
        .accessibilityLabel(playing ? "\(app.name), playing" : "Open \(app.name)")
    }
}

/// Small tiles under the shelves: everything off, and how the hub link is doing.
struct QuickTiles: View {
    @Environment(HubStore.self) private var hub
    @Binding var path: NavigationPath

    var body: some View {
        let onCount = hub.screens.filter(\.isOn).count
        VStack(spacing: 12) {
            Button { hub.allOff() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("All off").font(.system(size: 15, weight: .semibold))
                        Text(onCount == 0 ? "Everything's off" : "\(onCount) \(onCount == 1 ? "screen" : "screens") on · keeps the hub on")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Image(systemName: "power").font(.system(size: 18, weight: .medium))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(PressButtonStyle())
            .disabled(onCount == 0)
            .opacity(onCount == 0 ? 0.6 : 1)

            Button { path.append(Route.hub) } label: {
                HStack(spacing: 10) {
                    Circle().fill(linkColor).frame(width: 8, height: 8)
                    Text(linkText).font(.system(size: 14))
                    Spacer()
                    Text(hub.isDemo ? "Connect ›" : "Hub ›").font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(PressButtonStyle())
        }
    }

    private var linkText: String {
        switch hub.link {
        case .demo: return "Demo mode · pretend devices"
        case .connecting: return "Connecting to the hub…"
        case .live: return "Live with the hub on the Mac Mini"
        case .offline: return "Can't reach the hub"
        case .needsPairing: return "Pair this device with the hub"
        }
    }

    private var linkColor: Color {
        switch hub.link {
        case .live: return Theme.live
        case .connecting, .demo: return Theme.faint
        case .offline, .needsPairing: return .orange
        }
    }
}

/// The sheet behind "ON SONY TV ⌄".
struct ScreenPicker: View {
    @Environment(HubStore.self) private var hub
    let current: String
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose a screen").font(.shelfTitle).padding(.bottom, 10)
            ForEach(hub.screens) { s in
                Button { choose(s.id) } label: {
                    HStack(spacing: 12) {
                        ArtworkView(art: s.art)
                            .frame(width: 56, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.spot.name).font(.system(size: 15, weight: .semibold))
                            Text(s.short).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        if s.id == current { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)) }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 60)
                    .background(s.id == current ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 24)
        .foregroundStyle(.white)
    }
}

#Preview {
    RootView().environment(HubStore.demo()).preferredColorScheme(.dark)
}
