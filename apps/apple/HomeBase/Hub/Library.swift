import Foundation

/// Something to watch: a show to pick up, or a title to start, and the app that plays it.
/// The hub can't read the apps' libraries or watch history yet, so only demo mode has any.
struct MediaItem: Identifiable, Hashable {
    let title: String
    /// The app's name as the screen lists it, like "Netflix".
    let app: String
    /// "S2 · E4 · 32 min left", or "Movie".
    let detail: String
    /// How far through it is, 0 to 1. Zero for something not started.
    var progress: Double = 0
    /// A small label like "New" or "Top 10".
    var badge: String?

    var id: String { app + "/" + title }
    var art: Artwork { Artwork(app: "title " + title) }

    static let demoContinue: [MediaItem] = [
        MediaItem(title: "Night Signal", app: "Netflix", detail: "S2 · E4 · 32 min left", progress: 0.62),
        MediaItem(title: "Ironwood", app: "Plex", detail: "Movie · 1 h 10 min left", progress: 0.35),
        MediaItem(title: "Low Tide", app: "Disney+", detail: "S1 · E7 · 18 min left", progress: 0.8),
        MediaItem(title: "Glasshouse", app: "Prime Video", detail: "S3 · E1 · Just started", progress: 0.08),
        MediaItem(title: "Small Hours", app: "Hulu", detail: "S1 · E2 · 24 min left", progress: 0.5),
    ]

    static let demoTitles: [MediaItem] = [
        MediaItem(title: "The Long Coast", app: "Netflix", detail: "Series", badge: "New"),
        MediaItem(title: "Harbor Lights", app: "Apple TV", detail: "Series", badge: "New"),
        MediaItem(title: "North of Here", app: "Prime Video", detail: "Movie", badge: "Top 10"),
        MediaItem(title: "Paper Moons", app: "Disney+", detail: "Movie"),
        MediaItem(title: "The Quiet Year", app: "HBO Max", detail: "Series", badge: "New"),
        MediaItem(title: "Static", app: "Hulu", detail: "Series"),
        MediaItem(title: "Field Notes", app: "YouTube", detail: "Series"),
        MediaItem(title: "Ironwood", app: "Plex", detail: "Movie"),
        MediaItem(title: "Night Signal", app: "Netflix", detail: "Series", badge: "Top 10"),
    ]
}

/// A Hue room or zone, read from the hue_bridge device's detail.
struct LightRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let on: Bool
    let brightness: Int
    /// The hub device that owns it.
    let bridge: String

    init?(bridge: String, _ value: JSONValue) {
        guard let o = value.object, let id = o["id"]?.string, let name = o["name"]?.string else { return nil }
        self.id = id
        self.name = name
        self.on = o["on"]?.bool ?? false
        self.brightness = o["brightness"]?.int ?? 0
        self.bridge = bridge
    }
}

/// A scene: one tap sets screens, lights and, later, anything else the hub learns to control.
/// Steps for devices that aren't set up yet are skipped.
struct HomePreset: Identifiable {
    enum Step {
        case power(String, on: Bool)
        case launch(screen: String, app: String)
        /// A Hue room whose name contains this, at a brightness (0 turns it off).
        case room(String, brightness: Int)
        case lights(on: Bool)
        case screensOff
    }

    let id: String
    let name: String
    let icon: String
    /// What it does, in a few words each.
    let summary: [String]
    let steps: [Step]

    static let all: [HomePreset] = [
        HomePreset(id: "movie", name: "Movie night", icon: "film", summary: ["Sony TV plays Plex", "Living room 20%", "LG TV off"],
                   steps: [.power("lg", on: false), .launch(screen: "sony", app: "Plex"), .room("living", brightness: 20)]),
        HomePreset(id: "work", name: "Desk work", icon: "desktopcomputer", summary: ["TVs off", "Desk lamp 80%"],
                   steps: [.power("lg", on: false), .power("sony", on: false), .room("desk", brightness: 80)]),
        HomePreset(id: "game", name: "Game time", icon: "gamecontroller", summary: ["Wakes the Gaming PC", "Living room 30%", "TVs off"],
                   steps: [.power("pc", on: true), .power("lg", on: false), .power("sony", on: false), .room("living", brightness: 30)]),
        HomePreset(id: "morning", name: "Morning", icon: "sun.max", summary: ["LG TV plays YouTube", "Every light on"],
                   steps: [.launch(screen: "lg", app: "YouTube"), .lights(on: true)]),
        HomePreset(id: "off", name: "All off", icon: "moon", summary: ["Every screen off", "Every light off"],
                   steps: [.screensOff, .lights(on: false)]),
    ]
}

extension HubStore {
    /// Shows to pick up where you left off. Empty until the hub can read watch history.
    var continueWatching: [MediaItem] { isDemo ? MediaItem.demoContinue : [] }
    /// Movies and shows from the apps. Empty until the hub can read the apps' libraries.
    var moviesAndShows: [MediaItem] { isDemo ? MediaItem.demoTitles : [] }

    /// Every Hue room and zone on every paired bridge.
    var lightRooms: [LightRoom] {
        devices.values
            .filter { $0.kind == "hue_bridge" && !$0.needsPairing }
            .sorted { $0.id < $1.id }
            .flatMap { d in (d.detail["rooms"]?.array ?? []).compactMap { LightRoom(bridge: d.id, $0) } }
    }

    func setRoom(_ room: LightRoom, on: Bool? = nil, brightness: Int? = nil) {
        var arg: [String: JSONValue] = ["room": .string(room.id)]
        if let on { arg["on"] = .bool(on) }
        if let brightness { arg["brightness"] = .number(Double(brightness)) }
        send(room.bridge, "room", .object(arg))
    }

    /// Run a scene's steps in order. The card stays white until another scene runs.
    func run(_ preset: HomePreset) {
        activePreset = preset.id
        presetRunning = true
        Task {
            defer { presetRunning = false }
            for step in preset.steps {
                switch step {
                case .power(let id, let on):
                    if let d = devices[id], d.can(on ? "power_on" : "power_off"), d.isOn != on { setPower(id, on: on) }
                case .launch(let id, let name):
                    if let s = screen(id), let app = s.apps.first(where: { $0.name == name }) { launch(app, on: s) }
                case .room(let name, let level):
                    for r in lightRooms where r.name.localizedCaseInsensitiveContains(name) { setRoom(r, brightness: level) }
                case .lights(let on):
                    for d in devices.values where d.kind == "hue_bridge" && d.can(on ? "power_on" : "power_off") {
                        send(d.id, on ? "power_on" : "power_off")
                    }
                case .screensOff:
                    allOff()
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}
