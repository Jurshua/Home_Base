import SwiftUI

/// Mac Home: the chosen screen as a wide hero, then Screens, apps to open, and every device.
struct MacHomeView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var tab: MacTab
    @Binding var scrolled: Bool

    var body: some View {
        let screens = hub.screens
        let current = screens.first { $0.id == selection.screen } ?? screens[0]

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MacHero(screen: current, launch: { tab = .media })

                Shelf(title: "Screens", spacing: 20) {
                    ForEach(screens) { s in
                        ScreenCard(screen: s, selected: s.id == current.id, width: 240) { selection.screen = s.id }
                    }
                }
                .macShelf()

                if !current.apps.isEmpty {
                    Shelf(title: "Open on \(current.spot.name)", spacing: 20) {
                        ForEach(current.apps) { app in
                            AppCard(app: app, width: 260, playing: current.isOn && current.title == app.name) {
                                hub.launch(app, on: current)
                            }
                        }
                    }
                    .macShelf()
                }

                if !hub.devices.isEmpty {
                    Shelf(title: "Devices", spacing: 18) {
                        ForEach(hub.devices.values.sorted(by: deviceOrder)) { d in
                            DeviceTile(device: d)
                        }
                    }
                    .macShelf()
                }
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .reportsScrolled($scrolled)
        .ignoresSafeArea(edges: .top)
    }

    private func deviceOrder(_ a: Device, _ b: Device) -> Bool {
        let order = ["sony", "appletv", "lg", "pc", "mini", "air"]
        return (order.firstIndex(of: a.id) ?? 99, a.name) < (order.firstIndex(of: b.id) ?? 99, b.name)
    }
}

private extension View {
    /// Mac shelves use the mockup's 4% gutter and slightly larger titles.
    func macShelf() -> some View {
        self.environment(\.shelfGutter, 48).padding(.top, 8)
    }
}

/// The wide hero: artwork fills the top, text sits on the left over a dark fade.
struct MacHero: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Environment(\.openWindow) private var openWindow
    let screen: ScreenStatus
    let launch: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(art: screen.art)
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))
            LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ForEach(hub.screens) { s in
                        Button {
                            selection.screen = s.id
                        } label: {
                            if s.id == screen.id { Label(s.spot.name, systemImage: "checkmark") } else { Text(s.spot.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(eyebrow)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a screen")

                Text(screen.title)
                    .font(.system(size: 56, weight: .bold))
                    .kerning(-1.8)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text(screen.meta)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.opacity)

                actions.padding(.top, 10)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 56)
            .animation(Theme.settle, value: screen.title)
        }
        .frame(height: 560)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var eyebrow: String {
        let source = screen.player.flatMap { $0.id == screen.display?.id ? nil : $0.name }
        return ([screen.spot.name] + (screen.isOn ? [source].compactMap { $0 } : [])).joined(separator: " · ").uppercased()
    }

    @ViewBuilder private var actions: some View {
        let busy = screen.display.map { hub.pending.contains($0.id) } ?? false
        HStack(spacing: 12) {
            switch screen.phase {
            case .on:
                Pill(title: "Remote", style: .primary) { openRemote() }
                Pill(title: "Launch", action: launch)
                if let d = screen.display {
                    RoundButton(icon: "power", label: "Turn off \(screen.spot.name)", size: 48, busy: busy, glass: true) {
                        hub.setPower(d.id, on: false)
                    }
                    .help("Turn off \(screen.spot.name)")
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

    private func openRemote() {
        openWindow(id: "remote", value: screen.id)
    }
}

/// One hub device. White means on; click to turn it on or off.
struct DeviceTile: View {
    @Environment(HubStore.self) private var hub
    let device: Device

    var body: some View {
        let on = device.isOn
        let busy = hub.pending.contains(device.id)
        let canToggle = device.can(on ? "power_off" : "power_on") && !device.needsPairing
        Button {
            hub.setPower(device.id, on: !on)
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Circle().fill(on ? Color.black : Color.white.opacity(0.3)).frame(width: 10, height: 10)
                    Spacer()
                    if busy { ProgressView().controlSize(.small).tint(on ? .black : .white) }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.system(size: 16, weight: .semibold))
                    Text(status).font(.system(size: 13))
                        .foregroundStyle(on ? Color.black.opacity(0.6) : Theme.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(width: 170, height: 120, alignment: .leading)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(on ? Color.white : Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(!canToggle || busy)
        .animation(Theme.settle, value: on)
        .accessibilityLabel((on ? "Turn off " : "Turn on ") + device.name)
        .help(canToggle ? (on ? "Turn off" : "Turn on") : status)
    }

    private var status: String {
        if device.needsPairing { return "Needs pairing" }
        if device.isOn {
            let app = device.currentApp.map { ScreenStatus.appName($0, on: device, player: nil) }
            return app ?? "On"
        }
        if !device.can("power_off") && device.reachable { return "Runs the hub" }
        return device.reachable || device.power == .off ? "Off" : "Not responding"
    }
}

private extension View {
    /// Sets `scrolled` once the page moves more than a few points. Before macOS 15 it stays true,
    /// so the header keeps its backdrop.
    @ViewBuilder func reportsScrolled(_ scrolled: Binding<Bool>) -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 24 } action: { _, now in
                scrolled.wrappedValue = now
            }
        } else {
            self.onAppear { scrolled.wrappedValue = true }
        }
    }
}
