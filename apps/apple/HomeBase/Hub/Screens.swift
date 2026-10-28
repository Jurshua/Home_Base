import SwiftUI

/// A physical screen in the house. Screens are separate from sources: the Sony TV shows
/// whatever the Apple TV plays, and the desk monitor shows one of three computers.
struct ScreenSpot: Identifiable, Hashable {
    let id: String
    let name: String
    /// The hub device that powers this screen and takes its remote buttons.
    let display: String?
    /// Hub devices that play on this screen, best first.
    let sources: [String]
    /// What a "not set up yet" screen says about when it arrives.
    let arrives: String

    static let all: [ScreenSpot] = [
        ScreenSpot(id: "sony", name: "Sony TV", display: "sony", sources: ["appletv", "sony"],
                   arrives: "Arrives once the Sony TV is set up on the hub"),
        ScreenSpot(id: "lg", name: "LG TV", display: "lg", sources: ["lg"],
                   arrives: "Arrives once the LG TV is set up on the hub"),
        ScreenSpot(id: "desk", name: "Desk monitor", display: nil, sources: ["mini", "air", "pc"],
                   arrives: "Arrives with desk monitor switching"),
    ]
}

/// Everything the UI needs to draw one screen right now, worked out from live hub state.
struct ScreenStatus: Identifiable {
    enum Phase: Equatable { case notSetUp, needsPairing, unreachable, off, on }

    let spot: ScreenSpot
    let phase: Phase
    let display: Device?
    /// The device whose apps "Launch" offers.
    let player: Device?
    let title: String
    let meta: String
    let art: Artwork
    let waiting: String?

    var id: String { spot.id }
    var isOn: Bool { phase == .on }
    var canControl: Bool { display != nil && phase != .notSetUp }
    var apps: [Device.Option] { player?.apps ?? [] }
    var inputs: [Device.Option] { display?.inputs ?? [] }

    /// Shorter line for shelf cards.
    var short: String {
        switch phase {
        case .on: return title
        case .off: return "Off"
        case .needsPairing: return "Needs pairing"
        case .unreachable: return "Not responding"
        case .notSetUp: return waiting == nil ? "Not set up yet" : "Waiting for the hub"
        }
    }

    /// `waiting` explains an empty screen while the hub is connecting or unreachable.
    init(spot: ScreenSpot, devices: [String: Device], waiting: String? = nil) {
        self.spot = spot
        self.waiting = waiting
        let display = spot.display.flatMap { devices[$0] }
        let player = spot.sources.lazy.compactMap { devices[$0] }.first { $0.apps?.isEmpty == false } ?? display
        self.display = display
        self.player = player

        guard let d = display else {
            phase = .notSetUp
            title = waiting ?? spot.name
            meta = waiting == nil ? spot.arrives : "Home Base keeps trying. Make sure the Mac Mini is on."
            art = .off
            return
        }
        if d.needsPairing {
            phase = .needsPairing
            title = "Pair \(spot.name)"
            meta = "Tap Pair, then press Yes on the TV"
            art = .off
        } else if d.isOn {
            phase = .on
            let app = d.currentApp
            let name = ScreenStatus.appName(app, on: d, player: player)
            title = name
            meta = player.map { $0.id == d.id ? "\(d.name) built-in app" : "via \($0.name)" } ?? d.name
            art = Artwork(app: app ?? name)
        } else if !d.reachable && d.power != .off {
            phase = .unreachable
            title = "\(spot.name) isn't responding"
            meta = "Check it's plugged in and on Wi-Fi"
            art = .off
        } else {
            phase = .off
            title = "\(spot.name) is off"
            meta = "Launch something here and Home Base turns it on"
            art = .off
        }
    }

    /// "netflix" → "Netflix", "com.webos.app.hdmi2" → "HDMI 2", using the device's own lists first.
    static func appName(_ id: String?, on d: Device, player: Device?) -> String {
        guard let id, !id.isEmpty else { return "Home screen" }
        let known = (d.apps ?? []) + (d.inputs ?? []) + (player?.apps ?? [])
        if let match = known.first(where: { $0.id == id }) { return match.name }
        switch id {
        case "com.webos.app.home", "com.webos.app.homeconnect": return "Home screen"
        case "com.webos.app.livetv": return "Live TV"
        case "com.webos.app.browser": return "Web browser"
        default:
            let last = id.split(separator: ".").last.map(String.init) ?? id
            return last.prefix(1).uppercased() + last.dropFirst()
        }
    }
}

/// Stand-in artwork until the hub sends real artwork: a deep wash in the app's own colour.
struct Artwork: Equatable {
    let base: Color
    let glow: Color

    static let off = Artwork(base: Color(white: 0.055), glow: Color(white: 0.09))

    init(base: Color, glow: Color) {
        self.base = base
        self.glow = glow
    }

    init(app: String) {
        let key = app.lowercased()
        let tones: [(String, (Double, Double, Double))] = [
            ("netflix", (0.55, 0.04, 0.07)), ("youtube", (0.50, 0.05, 0.05)),
            ("disney", (0.05, 0.16, 0.48)), ("amazon", (0.02, 0.30, 0.42)), ("prime", (0.02, 0.30, 0.42)),
            ("hulu", (0.03, 0.40, 0.22)), ("hbo", (0.24, 0.10, 0.55)), ("wbd", (0.24, 0.10, 0.55)),
            ("sling", (0.45, 0.22, 0.03)), ("spotify", (0.06, 0.40, 0.18)), ("apple", (0.16, 0.16, 0.20)),
            ("hdmi", (0.12, 0.13, 0.16)), ("steam", (0.05, 0.22, 0.30)), ("plex", (0.42, 0.30, 0.03)),
        ]
        let rgb = tones.first { key.contains($0.0) }?.1 ?? Artwork.hashed(key)
        base = Color(red: rgb.0 * 0.38, green: rgb.1 * 0.38, blue: rgb.2 * 0.38)
        glow = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// A stable, muted colour for apps we don't know.
    private static func hashed(_ s: String) -> (Double, Double, Double) {
        let hue = Double(s.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value } % 360) / 60
        let (v, sat) = (0.45, 0.7)
        let c = v * sat, x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let rgb: (Double, Double, Double) = switch Int(hue) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }
}
