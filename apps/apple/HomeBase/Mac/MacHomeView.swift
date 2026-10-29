import SwiftUI

/// Mac Home. A dashboard of scenes, screens and things to watch. Pick a screen and its card grows
/// into the hero while the other screens shrink out of the way, with everything it can play in
/// rows underneath: apps first, then movies and shows, then inputs.
struct MacHomeView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var tab: MacTab
    @Binding var scrolled: Bool
    @Namespace private var zoom

    private static let top = "top"

    var body: some View {
        let screens = hub.screens
        let focused = selection.focused.flatMap { id in screens.first { $0.id == id } }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(MacHomeView.top)
                    if let focused {
                        ScreenPage(screen: focused, others: screens.filter { $0.id != focused.id }, zoom: zoom) { focus($0, proxy) }
                            .id(focused.id)
                    } else {
                        Dashboard(screens: screens, zoom: zoom) { focus($0, proxy) }
                    }
                }
                // Room for the remote's bar along the bottom.
                .padding(.bottom, focused == nil ? 48 : 120)
            }
            .scrollIndicators(.hidden)
            .reportsScrolled($scrolled)
            .ignoresSafeArea(edges: .top)
        }
    }

    /// Zoom into a screen, or back out to the dashboard with nil. Scrolls to the top first so
    /// the card and the hero are both in view while one becomes the other.
    private func focus(_ id: String?, _ proxy: ScrollViewProxy) {
        let go = {
            withAnimation(Theme.zoom) {
                selection.focused = id
                selection.remoteOpen = false
                if let id { selection.screen = id }
            }
        }
        if scrolled {
            withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(MacHomeView.top, anchor: .top) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { go() }
        } else {
            go()
        }
    }
}

private extension View {
    /// Mac shelves use the mockup's 4% gutter and slightly larger titles.
    func macShelf() -> some View {
        self.environment(\.shelfGutter, 48).padding(.top, 8)
    }
}

// MARK: Dashboard

private struct Dashboard: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    let screens: [ScreenStatus]
    let zoom: Namespace.ID
    let focus: (String?) -> Void

    var body: some View {
        let rooms = hub.lightRooms
        let ready = readyToLaunch

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.system(size: 38, weight: .bold)).kerning(-1.2)
                Text(summary(rooms)).font(.system(size: 15)).foregroundStyle(Theme.secondary).contentTransition(.opacity)
            }
            .padding(.horizontal, 48)
            .padding(.top, 104)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                ForEach(HomePreset.all) { PresetButton(preset: $0) }
            }
            .padding(.horizontal, 48)
            .padding(.top, 24)

            Text("Screens").font(.system(size: 22, weight: .semibold)).kerning(-0.4)
                .padding(.horizontal, 48)
                .padding(.top, 38)
            HStack(spacing: 20) {
                ForEach(screens) { s in
                    ScreenTile(screen: s, zoom: zoom) { focus(s.id) }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)
            .padding(.bottom, 14)

            if !hub.continueWatching.isEmpty {
                Shelf(title: "Continue watching", spacing: 18) {
                    ForEach(hub.continueWatching) { item in
                        if let s = bestScreen(for: item.app) {
                            WatchCard(item: item, caption: s.spot.name, playing: playing(item, on: s)) { play(item, on: s) }
                        }
                    }
                }
                .macShelf()
            }

            if !ready.isEmpty {
                Shelf(title: "Ready to launch", spacing: 18) {
                    ForEach(ready) { r in
                        AppCard(app: r.app, width: 220, playing: r.screen.isOn && r.screen.title == r.app.name, caption: r.screen.spot.name) {
                            hub.launch(r.app, on: r.screen)
                            selection.showing[r.screen.id] = nil
                            focus(r.screen.id)
                        }
                    }
                }
                .macShelf()
            }

            if !rooms.isEmpty {
                Text("Lights").font(.system(size: 22, weight: .semibold)).kerning(-0.4)
                    .padding(.horizontal, 48)
                    .padding(.top, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(rooms) { LightButton(room: $0) }
                }
                .padding(.horizontal, 48)
                .padding(.top, 14)
                .padding(.bottom, 22)
            }

            if !hub.devices.isEmpty {
                Shelf(title: "Devices", spacing: 18) {
                    ForEach(hub.devices.values.sorted(by: deviceOrder)) { DeviceTile(device: $0) }
                }
                .macShelf()
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func summary(_ rooms: [LightRoom]) -> String {
        let on = screens.filter(\.isOn).count
        var parts = [on == 0 ? "Every screen is off" : "\(on) of \(screens.count) screens on"]
        if !rooms.isEmpty {
            let lit = rooms.filter(\.on).count
            parts.append(lit == 0 ? "lights off" : "\(lit) \(lit == 1 ? "light" : "lights") on")
        }
        return parts.joined(separator: " · ")
    }

    /// The chosen screen first, then the rest, so things open where you were looking.
    private var ordered: [ScreenStatus] {
        screens.filter { $0.id == selection.screen } + screens.filter { $0.id != selection.screen }
    }

    private func bestScreen(for app: String) -> ScreenStatus? {
        ordered.first { s in s.apps.contains { $0.name == app } }
    }

    struct ReadyApp: Identifiable {
        let app: Device.Option
        let screen: ScreenStatus
        var id: String { app.name }
    }

    /// Every app any screen can open, once each, on the screen that would play it.
    private var readyToLaunch: [ReadyApp] {
        var seen = Set<String>()
        return screens.flatMap { s in s.apps.map { ReadyApp(app: $0, screen: s) } }
            .filter { seen.insert($0.app.name).inserted }
            .map { ReadyApp(app: $0.app, screen: bestScreen(for: $0.app.name) ?? $0.screen) }
    }

    private func playing(_ item: MediaItem, on s: ScreenStatus) -> Bool {
        s.isOn && s.title == item.app && selection.showing[s.id] == item
    }

    private func play(_ item: MediaItem, on s: ScreenStatus) {
        guard let app = s.apps.first(where: { $0.name == item.app }) else { return }
        hub.launch(app, on: s)
        selection.showing[s.id] = item
        focus(s.id)
    }

    private func deviceOrder(_ a: Device, _ b: Device) -> Bool {
        let order = ["sony", "appletv", "lg", "pc", "mini", "air", "hue"]
        return (order.firstIndex(of: a.id) ?? 99, a.name) < (order.firstIndex(of: b.id) ?? 99, b.name)
    }
}

/// A scene in the row under the greeting. White while it's the one that ran last.
private struct PresetButton: View {
    @Environment(HubStore.self) private var hub
    let preset: HomePreset

    var body: some View {
        let on = hub.activePreset == preset.id
        let running = on && hub.presetRunning
        Button { hub.run(preset) } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(on ? Color.black : Theme.fill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.system(size: 15, weight: .semibold))
                    Text(running ? "Setting everything…" : preset.summary.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(on ? Color.black.opacity(0.6) : Theme.tertiary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if on && !running {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(height: 62)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(on ? Color.white : Theme.fillSoft, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(LiftButtonStyle())
        .animation(Theme.settle, value: on)
        .animation(Theme.settle, value: running)
        .accessibilityLabel("\(preset.name): \(preset.summary.joined(separator: ", "))")
    }
}

/// A screen on the dashboard. Its artwork is the same view as the hero's, so picking it grows
/// the card into the top of the page.
private struct ScreenTile: View {
    let screen: ScreenStatus
    let zoom: Namespace.ID
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: screen.art)
                    .clipShape(shape)
                    .matchedGeometryEffect(id: screen.id, in: zoom)
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
                    .clipShape(shape)

                VStack(alignment: .leading, spacing: 3) {
                    if screen.isOn {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.live).frame(width: 7, height: 7)
                            Text("On")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(.black.opacity(0.4), in: Capsule())
                    }
                    Spacer()
                    Text(screen.spot.name.uppercased())
                        .font(.system(size: 12, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(Theme.secondary)
                    Text(screen.isOn ? screen.title : screen.short)
                        .font(.system(size: 26, weight: .bold)).kerning(-0.6)
                        .lineLimit(1)
                    Text(screen.meta).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    AppDots(apps: screen.apps, inputs: screen.inputs.count).padding(.top, 10)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .contentShape(shape)
        }
        .buttonStyle(LiftButtonStyle())
        .accessibilityLabel("\(screen.spot.name), \(screen.short). Open")
    }
}

/// The first few apps a screen can open, as small icons.
private struct AppDots: View {
    let apps: [Device.Option]
    let inputs: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps.prefix(5)) { app in
                ZStack {
                    ArtworkView(art: Artwork(app: app.id + " " + app.name))
                    Text(String(app.name.prefix(1))).font(.system(size: 13, weight: .heavy))
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(more).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.leading, 4)
        }
        .accessibilityHidden(true)
    }

    private var more: String {
        var parts: [String] = []
        if apps.count > 5 { parts.append("+\(apps.count - 5)") }
        if inputs > 0 { parts.append("\(inputs) inputs") }
        return parts.joined(separator: " · ")
    }
}

/// A Hue room. The fill shows its brightness; click to turn it on or off.
private struct LightButton: View {
    @Environment(HubStore.self) private var hub
    let room: LightRoom

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button { hub.setRoom(room, on: !room.on) } label: {
            HStack(spacing: 10) {
                Image(systemName: room.on ? "lightbulb.fill" : "lightbulb").font(.system(size: 15, weight: .semibold))
                Text(room.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(room.on ? "\(room.brightness)%" : "Off").font(.system(size: 14, weight: .semibold))
                    .contentTransition(.numericText(value: Double(room.brightness)))
            }
            .foregroundStyle(room.on ? Color.white : Theme.secondary)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(.white.opacity(0.16))
                        .frame(width: g.size.width * CGFloat(room.on ? room.brightness : 0) / 100)
                }
            }
            .background(Theme.fillSoft)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(PressButtonStyle())
        .animation(Theme.settle, value: room.brightness)
        .animation(Theme.settle, value: room.on)
        .accessibilityLabel("\(room.name), \(room.on ? "\(room.brightness) percent" : "off"). \(room.on ? "Turn off" : "Turn on")")
    }
}

// MARK: Screen page

/// One screen, zoomed in: the hero, the other screens tucked in the corner, and rows of
/// everything this screen can play.
private struct ScreenPage: View {
    let screen: ScreenStatus
    let others: [ScreenStatus]
    let zoom: Namespace.ID
    let focus: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: screen.art)
                    .matchedGeometryEffect(id: screen.id, in: zoom)
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.62, y: 0.5))
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                HeroDetails(screen: screen)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 52)
                    .riseIn(delay: 0.14, from: 24)
            }
            .frame(height: 560)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Pill(title: "Home", icon: "chevron.left", height: 36) { focus(nil) }
                    .padding(.top, 84)
                    .padding(.leading, 48)
                    .riseIn(delay: 0.2, from: -8)
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("SWITCH SCREEN")
                        .font(.system(size: 11, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(Theme.secondary)
                        .riseIn(delay: 0.3, from: -6)
                    HStack(spacing: 12) {
                        ForEach(others) { o in
                            ScreenThumb(screen: o, zoom: zoom) { focus(o.id) }
                        }
                    }
                }
                .padding(.top, 84)
                .padding(.trailing, 48)
            }

            MediaRows(screen: screen)
                .riseIn(delay: 0.08, from: 90)
        }
    }
}

/// Another screen, shrunk into the hero's corner. Click to switch to it.
private struct ScreenThumb: View {
    let screen: ScreenStatus
    let zoom: Namespace.ID
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: screen.art)
                    .clipShape(shape)
                    .matchedGeometryEffect(id: screen.id, in: zoom)
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).clipShape(shape)
                VStack(alignment: .leading, spacing: 0) {
                    Text(screen.spot.name).font(.system(size: 13, weight: .semibold))
                    Text(screen.short).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                .padding(10)
            }
            .frame(width: 168, height: 96)
            .overlay(shape.strokeBorder(.white.opacity(0.22)))
            .contentShape(shape)
        }
        .buttonStyle(LiftButtonStyle())
        .accessibilityLabel("Switch to \(screen.spot.name), \(screen.short)")
    }
}

/// What's on the zoomed-in screen and what you can do about it.
private struct HeroDetails: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    let screen: ScreenStatus

    var body: some View {
        let item = selection.showing[screen.id].flatMap { screen.isOn && screen.title == $0.app ? $0 : nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(screen.isOn ? Theme.live : Theme.faint).frame(width: 8, height: 8)
                Text(eyebrow)
            }
            .font(.system(size: 13, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Theme.secondary)

            Text(item?.title ?? screen.title)
                .font(.system(size: 60, weight: .bold))
                .kerning(-2)
                .lineLimit(2)
                .contentTransition(.opacity)
            Text(item.map { "\($0.app) · \($0.detail)" } ?? screen.meta)
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
                .contentTransition(.opacity)
            if let item, item.progress > 0 {
                ProgressLine(value: item.progress).frame(width: 320).padding(.top, 4)
            }
            actions.padding(.top, 12)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .animation(Theme.settle, value: screen.title)
    }

    private var eyebrow: String {
        let source = screen.player.flatMap { $0.id == screen.display?.id ? nil : $0.name }
        return ([screen.spot.name] + (screen.isOn ? [source].compactMap { $0 } : ["Off"])).joined(separator: " · ").uppercased()
    }

    @ViewBuilder private var actions: some View {
        let busy = screen.display.map { hub.pending.contains($0.id) } ?? false
        HStack(spacing: 12) {
            switch screen.phase {
            case .on:
                Pill(title: "Remote", icon: "appletvremote.gen4", style: .primary) {
                    withAnimation(Theme.sheet) { selection.remoteOpen = true }
                }
                if let d = screen.display {
                    RoundButton(icon: "power", label: "Turn off \(screen.spot.name)", size: 48, busy: busy, glass: true) {
                        hub.setPower(d.id, on: false)
                    }
                    .help("Turn off \(screen.spot.name)")
                }
            case .off, .unreachable:
                if let d = screen.display {
                    Pill(title: "Turn on", icon: "power", style: .primary, busy: busy) { hub.setPower(d.id, on: true) }
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

/// The rows under the hero: apps, then movies and shows, then everything plugged in.
private struct MediaRows: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    let screen: ScreenStatus

    var body: some View {
        let names = Set(screen.apps.map(\.name))
        let resume = hub.continueWatching.filter { names.contains($0.app) }
        let titles = hub.moviesAndShows.filter { names.contains($0.app) }

        VStack(alignment: .leading, spacing: 0) {
            if !screen.apps.isEmpty {
                Shelf(title: "Apps on \(screen.player?.name ?? screen.spot.name)", spacing: 18) {
                    ForEach(screen.apps) { app in
                        AppCard(app: app, width: 240, playing: screen.isOn && screen.title == app.name) {
                            hub.launch(app, on: screen)
                            selection.showing[screen.id] = nil
                        }
                    }
                }
                .macShelf()
            }

            if !resume.isEmpty {
                Shelf(title: "Continue watching", spacing: 18) {
                    ForEach(resume) { item in
                        WatchCard(item: item, playing: playing(item)) { play(item) }
                    }
                }
                .macShelf()
            }

            if !titles.isEmpty {
                Shelf(title: "Movies & shows", spacing: 18) {
                    ForEach(titles) { item in
                        PosterCard(item: item, playing: playing(item)) { play(item) }
                    }
                }
                .macShelf()
            } else if !screen.apps.isEmpty {
                Shelf(title: "Movies & shows") {
                    LibraryPlaceholder()
                }
                .macShelf()
            }

            if let d = screen.display, let inputs = d.inputs, !inputs.isEmpty {
                Shelf(title: "Inputs", spacing: 16) {
                    ForEach(inputs) { input in
                        let current = d.isOn && d.currentApp == input.id
                        OptionTile(title: input.name, detail: current ? "On now" : (d.isOn ? "Switch to it" : "Turn the TV on first"),
                                   icon: "cable.connector.horizontal", on: current) {
                            hub.send(d.id, "input", .string(input.id))
                        }
                        .disabled(!d.isOn)
                    }
                }
                .macShelf()
            }

            let computers = screen.spot.display == nil ? screen.spot.sources.compactMap { hub.devices[$0] } : []
            if !computers.isEmpty {
                Shelf(title: "Computers on this monitor", spacing: 18) {
                    ForEach(computers) { DeviceTile(device: $0) }
                }
                .macShelf()
                Text("Switching the monitor between them arrives with milestone 4.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 48)
            }
        }
    }

    private func playing(_ item: MediaItem) -> Bool {
        screen.isOn && screen.title == item.app && selection.showing[screen.id] == item
    }

    private func play(_ item: MediaItem) {
        guard let app = screen.apps.first(where: { $0.name == item.app }) else { return }
        hub.launch(app, on: screen)
        selection.showing[screen.id] = item
    }
}

// MARK: Cards

/// A show to pick up: wide artwork, the title and how far through you are.
private struct WatchCard: View {
    let item: MediaItem
    var caption: String?
    let playing: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: item.art)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    if let caption {
                        Text(caption.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.4)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Text(item.title).font(.system(size: 19, weight: .bold)).kerning(-0.4).lineLimit(1)
                    Text(playing ? "Playing on \(item.app)" : "\(item.app) · \(item.detail)")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                    ProgressLine(value: item.progress).padding(.top, 8)
                }
                .padding(16)
            }
            .frame(width: 300, height: 170)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white, lineWidth: playing ? 2 : 0))
        }
        .buttonStyle(LiftButtonStyle(lifted: playing))
        .accessibilityLabel(playing ? "\(item.title), playing" : "Resume \(item.title) in \(item.app)")
    }
}

/// A movie or show, poster shaped.
private struct PosterCard: View {
    let item: MediaItem
    let playing: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(art: item.art)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Spacer()
                        if playing {
                            Text("PLAYING").padding(.horizontal, 8).frame(height: 20).foregroundStyle(.black).background(.white, in: Capsule())
                        } else if let badge = item.badge {
                            Text(badge.uppercased()).padding(.horizontal, 8).frame(height: 20).background(.black.opacity(0.5), in: Capsule())
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.4)
                    Spacer()
                    Text(item.title).font(.system(size: 22, weight: .heavy)).kerning(-0.6).lineLimit(3)
                    Text(item.app.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.4)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(12)
            }
            .frame(width: 168, height: 252)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white, lineWidth: playing ? 2 : 0))
        }
        .buttonStyle(LiftButtonStyle(lifted: playing))
        .accessibilityLabel(playing ? "\(item.title), playing" : "Play \(item.title) in \(item.app)")
    }
}

/// Holds the Movies & shows row's place until the hub can read the apps' libraries.
private struct LibraryPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "film.stack").font(.system(size: 22, weight: .medium))
            Spacer()
            Text("Movies and shows land here").font(.system(size: 15, weight: .semibold))
            Text("once the hub can read what's in your apps. Open an app above for now.")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
        }
        .padding(16)
        .frame(width: 300, height: 170, alignment: .leading)
        .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// An input or source. White when it's the one showing.
private struct OptionTile: View {
    let title: String
    let detail: String
    let icon: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Spacer()
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(on ? Color.black.opacity(0.6) : Theme.tertiary)
            }
            .padding(16)
            .frame(width: 200, height: 112, alignment: .leading)
            .foregroundStyle(on ? Color.black : Color.white)
            .background(on ? Color.white : Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(LiftButtonStyle(lifted: on))
        .animation(Theme.settle, value: on)
        .accessibilityLabel(on ? "\(title), on now" : "Switch to \(title)")
    }
}

/// A thin white bar for how far through something is.
struct ProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            Capsule().fill(.white.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: g.size.width * min(max(value, 0), 1))
                }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
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
