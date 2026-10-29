import SwiftUI

/// The v3 screen wall for Mac and iPad: a library of apps on the left and every screen on the
/// right. Pick an app (or drag it), then tap the screen it should play on.
struct ScreenWall: View {
    @Environment(HubStore.self) private var hub
    @State private var picked: String?

    /// Every app any screen can open, once each, in the order the hub lists them.
    private var library: [Device.Option] {
        var seen = Set<String>()
        return hub.screens.flatMap(\.apps).filter { seen.insert($0.name).inserted }
    }

    private func screens(playing name: String) -> [ScreenStatus] {
        hub.screens.filter { s in s.apps.contains { $0.name == name } }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(.system(size: 22, weight: .semibold))
                        Text("Pick something, then tap a screen.").font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                    }
                    Text("APPS").font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.tertiary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 16) {
                        ForEach(library) { app in
                            AppTile(app: app, picked: picked == app.name) {
                                picked = picked == app.name ? nil : app.name
                            }
                            .draggable(app.name)
                        }
                    }
                    if library.isEmpty {
                        Text("No apps yet. They appear once a screen is set up on the hub.")
                            .font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(24)
                .padding(.top, 86)
            }
            .scrollIndicators(.hidden)
            .frame(width: 300)
            .background(Color.white.opacity(0.04))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screens").font(.system(size: 34, weight: .bold)).kerning(-0.8)
                            Text(hint).font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        if picked != nil {
                            Pill(title: "Cancel", style: .quiet, height: 36) { picked = nil }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 20)], spacing: 20) {
                        ForEach(hub.screens) { s in
                            WallScreen(screen: s, offer: offer(for: s)) { play(on: s) }
                        }
                    }
                }
                .padding(32)
                .padding(.top, 86)
            }
            .scrollIndicators(.hidden)
        }
        .animation(Theme.lift, value: picked)
    }

    private var hint: String {
        guard let picked else {
            let on = hub.screens.filter(\.isOn).count
            return "\(on) of \(hub.screens.count) screens on"
        }
        let n = screens(playing: picked).count
        return n == 0 ? "No screen can play \(picked) yet" : "Tap a screen to play \(picked)"
    }

    private func offer(for s: ScreenStatus) -> String? {
        guard let picked, s.apps.contains(where: { $0.name == picked }) else { return nil }
        return s.isOn ? "Play \(picked) here" : "Turn on and play \(picked)"
    }

    private func play(on s: ScreenStatus, name: String? = nil) {
        guard let name = name ?? picked, let app = s.apps.first(where: { $0.name == name }) else { return }
        hub.launch(app, on: s)
        picked = nil
    }
}

/// A square app tile with its initial, white when picked.
private struct AppTile: View {
    let app: Device.Option
    let picked: Bool
    let action: () -> Void

    var body: some View {
        let art = Artwork(app: app.id + " " + app.name)
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    ArtworkView(art: art)
                    Text(String(app.name.prefix(1))).font(.system(size: 26, weight: .bold))
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: picked ? 2.5 : 0))
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
        }
        .buttonStyle(LiftButtonStyle(lifted: picked))
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// One screen on the wall. Offers "Play here" when an app is picked and accepts dropped apps.
private struct WallScreen: View {
    @Environment(HubStore.self) private var hub
    @Environment(\.openRemote) private var openRemote
    let screen: ScreenStatus
    let offer: String?
    let play: () -> Void
    @State private var targeted = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(art: screen.art)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.4), endPoint: .bottom)

            VStack(alignment: .leading) {
                HStack {
                    Text(screen.spot.name.uppercased())
                        .font(.system(size: 12, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    if let d = screen.display, screen.phase != .needsPairing {
                        RoundButton(icon: "power", label: (screen.isOn ? "Turn off " : "Turn on ") + screen.spot.name,
                                    on: screen.isOn, size: 34, busy: hub.pending.contains(d.id), glass: true) {
                            hub.setPower(d.id, on: !screen.isOn)
                        }
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(screen.isOn ? screen.title : screen.short).font(.system(size: 20, weight: .bold)).kerning(-0.3)
                        Text(screen.meta).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    if screen.isOn {
                        Pill(title: "Remote", style: .glass, height: 34) { openRemote(screen.id) }
                    }
                }
            }
            .padding(16)

            if let offer {
                Button(action: play) {
                    Text(offer)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 48)
                        .background(.white, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.35))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .transition(.opacity)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: targeted ? 3 : 0))
        .scaleEffect(targeted ? 1.03 : 1)
        .animation(Theme.lift, value: targeted)
        .dropDestination(for: String.self) { names, _ in
            guard let name = names.first, let app = screen.apps.first(where: { $0.name == name }) else { return false }
            hub.launch(app, on: screen)
            return true
        } isTargeted: { targeted = $0 && screen.player != nil }
    }
}
