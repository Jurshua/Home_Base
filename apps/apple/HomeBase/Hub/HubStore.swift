import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The app's one connection to the hub on the Mac Mini, and the live state of every device.
/// With no hub address it runs in demo mode with pretend devices, so the app is never empty.
@MainActor
@Observable
final class HubStore {
    enum Link: Equatable {
        case demo
        case connecting
        case live
        case offline(String)
    }

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    private(set) var devices: [String: Device] = [:]
    private(set) var link: Link = .connecting
    /// The latest command that failed, shown briefly as a toast.
    var failure: Failure?
    /// Device ids with a power change on the way, so buttons can show progress.
    private(set) var pending: Set<String> = []

    private(set) var address: String
    let source: String

    private var socket: URLSessionWebSocketTask?
    private var waiting: [String: CheckedContinuation<Void, Error>] = [:]
    private var counter = 0
    private var attempt = 0
    private var reconnect: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var everLive = false

    static let addressKey = "hubAddress"

    init(address: String? = nil) {
        #if os(macOS)
        source = "Home Base on Mac"
        let fallback = "localhost:4900"  // the hub listens only on the Mac Mini until milestone 3
        #else
        source = "Home Base on " + UIDevice.current.model
        let fallback = ""
        #endif
        self.address = address ?? UserDefaults.standard.string(forKey: HubStore.addressKey) ?? fallback
    }

    var screens: [ScreenStatus] {
        let waiting: String? = switch link {
        case .connecting where devices.isEmpty: "Connecting to the hub…"
        case .offline where devices.isEmpty: "Can't reach the hub"
        default: nil
        }
        return ScreenSpot.all.map { ScreenStatus(spot: $0, devices: devices, waiting: waiting) }
    }
    func screen(_ id: String) -> ScreenStatus? { screens.first { $0.id == id } }
    var isDemo: Bool { link == .demo }

    // MARK: Connection

    func start() {
        guard socket == nil, reconnect == nil else { return }
        if address.trimmingCharacters(in: .whitespaces).isEmpty {
            startDemo()
        } else {
            open()
        }
    }

    /// Point at a different hub (or "" for demo mode) and reconnect.
    func use(address new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: HubStore.addressKey)
        address = trimmed
        close()
        devices = [:]
        start()
    }

    /// Called when the app comes back to the foreground: reconnect now instead of waiting.
    func resume() {
        guard link != .demo else { return }
        if socket == nil || link != .live {
            close()
            open()
        }
    }

    private var liveURL: URL? {
        var host = address
        for scheme in ["http://", "https://", "ws://", "wss://"] where host.hasPrefix(scheme) {
            host.removeFirst(scheme.count)
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !host.contains(":") { host += ":4900" }
        return URL(string: "ws://\(host)/api/live")
    }

    private func open() {
        guard let url = liveURL else {
            link = .offline("That hub address doesn't look right")
            return
        }
        link = .connecting
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        Task { await listen(task) }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.socket === task else { return }
                task.sendPing { error in
                    if error != nil { Task { @MainActor in self.dropped(task, "Lost the hub") } }
                }
            }
        }
    }

    private func close() {
        reconnect?.cancel(); reconnect = nil
        heartbeat?.cancel(); heartbeat = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        failAll("Disconnected")
    }

    private func listen(_ task: URLSessionWebSocketTask) async {
        do {
            while true {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: continue
                }
                guard socket === task else { return }
                handle(data)
            }
        } catch {
            dropped(task, "Can't reach the hub at \(address)")
        }
    }

    private func dropped(_ task: URLSessionWebSocketTask, _ why: String) {
        guard socket === task else { return }
        socket = nil
        heartbeat?.cancel(); heartbeat = nil
        failAll(why)
        // Never reached a hub and nobody typed an address (a Mac that isn't the Mac Mini):
        // show the demo instead of an empty, offline app. Settings connects to the real hub.
        if !everLive && UserDefaults.standard.string(forKey: HubStore.addressKey) == nil {
            startDemo()
            return
        }
        link = .offline(why)
        let delay = min(15.0, pow(2.0, Double(attempt)))
        attempt += 1
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnect = nil
            self.open()
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func handle(_ data: Data) {
        guard let frame = try? HubStore.decoder.decode(HubFrame.self, from: data) else { return }
        switch frame.type {
        case "snapshot":
            devices = Dictionary((frame.devices ?? []).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            link = .live
            attempt = 0
            everLive = true
        case "device":
            if let d = frame.device { devices[d.id] = d }
        case "result":
            guard let id = frame.id, let waiter = waiting.removeValue(forKey: id) else { return }
            if frame.ok == true { waiter.resume() } else { waiter.resume(throwing: HubError(frame.error ?? "That didn't work")) }
        default:
            break
        }
    }

    private func failAll(_ why: String) {
        let all = waiting
        waiting = [:]
        for w in all.values { w.resume(throwing: HubError(why)) }
    }

    // MARK: Commands

    /// Send a command and wait for the hub to say it worked.
    func command(_ device: String, _ action: String, _ arg: JSONValue? = nil) async throws {
        if link == .demo { return try runDemo(device, action, arg) }
        guard let socket, link == .live else { throw HubError("Not connected to the hub") }
        counter += 1
        let id = String(counter)
        let frame = CommandFrame(id: id, device: device, action: action, arg: arg, source: source)
        let text = String(decoding: try JSONEncoder().encode(frame), as: UTF8.self)
        let limit: Double = action == "pair" ? 75 : 20
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiting[id] = c
            socket.send(.string(text)) { error in
                guard let error else { return }
                Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume(throwing: error) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                self?.waiting.removeValue(forKey: id)?.resume(throwing: HubError("The hub didn't answer in time"))
            }
        }
    }

    /// Fire and forget: errors become a toast instead of being thrown.
    func send(_ device: String, _ action: String, _ arg: JSONValue? = nil) {
        Task {
            do { try await command(device, action, arg) } catch { report(error) }
        }
    }

    func press(_ device: String, _ button: String) { send(device, "button", .string(button)) }

    func setPower(_ device: String, on: Bool) {
        Task {
            pending.insert(device)
            defer { pending.remove(device) }
            do {
                try await command(device, on ? "power_on" : "power_off")
                try await waitFor(device, timeout: 20) { $0.power == (on ? .on : .off) }
            } catch { report(error) }
        }
    }

    /// Launch an app on a screen, turning the screen on first if it's off.
    func launch(_ app: Device.Option, on screen: ScreenStatus) {
        guard let player = screen.player else { return }
        Task {
            pending.insert(player.id)
            defer { pending.remove(player.id) }
            do {
                if !(devices[player.id]?.isOn ?? false) {
                    try await command(player.id, "power_on")
                    try await waitFor(player.id, timeout: 20) { $0.isOn }
                    try await Task.sleep(for: .seconds(1.5))  // webOS needs a moment before it takes launches
                }
                try await command(player.id, "launch", .string(app.id))
            } catch { report(error) }
        }
    }

    /// Turn off every screen that's on. The Mac Mini stays on because it runs the hub.
    func allOff() {
        for s in screens where s.isOn { if let d = s.display { setPower(d.id, on: false) } }
    }

    func pair(_ device: String) {
        Task {
            pending.insert(device)
            defer { pending.remove(device) }
            do { try await command(device, "pair") } catch { report(error) }
        }
    }

    private func waitFor(_ id: String, timeout: Double, _ done: (Device) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let d = devices[id], done(d) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw HubError("\(devices[id]?.name ?? id) didn't respond")
    }

    private func report(_ error: Error) {
        failure = Failure(message: (error as? HubError)?.message ?? error.localizedDescription)
    }
}

struct HubError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: Demo mode

extension HubStore {
    static func demo() -> HubStore {
        let s = HubStore(address: "")
        s.startDemo()
        return s
    }

    private func startDemo() {
        link = .demo
        let apps = [("Netflix", "netflix"), ("YouTube", "youtube.leanback.v4"), ("Disney+", "com.disney.disneyplus-prod"),
                    ("Prime Video", "amazon"), ("Hulu", "hulu"), ("HBO Max", "com.wbd.stream"), ("Apple TV", "com.apple.appletv")]
            .map { Device.Option(name: $0.0, id: $0.1) }
        let inputs = (1...4).map { Device.Option(name: "HDMI \($0)", id: "com.webos.app.hdmi\($0)") }
        let tv = ["power_on", "power_off", "button", "launch", "input", "volume", "mute"]
        devices = [
            "lg": Device(id: "lg", name: "LG TV", kind: "lg_webos", actions: tv + ["pair"], apps: apps, inputs: inputs,
                         buttons: ["UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACK", "HOME", "PLAY", "PAUSE", "VOLUMEUP", "VOLUMEDOWN"],
                         power: .on, reachable: true, needsPairing: false,
                         detail: ["app": .string("netflix"), "volume": .number(12), "muted": .bool(false)], updated: nil),
            "sony": Device(id: "sony", name: "Sony TV", kind: "sony_bravia", actions: tv, apps: nil, inputs: inputs,
                           buttons: ["UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACK", "HOME", "PLAY", "PAUSE"],
                           power: .off, reachable: true, needsPairing: false, detail: ["volume": .number(22)], updated: nil),
            "appletv": Device(id: "appletv", name: "Apple TV", kind: "apple_tv", actions: tv,
                              apps: [("Apple TV", "com.apple.TVWatchList"), ("Netflix", "com.netflix.Netflix"),
                                     ("YouTube", "com.google.ios.youtube"), ("Plex", "com.plexapp.plex")].map { Device.Option(name: $0.0, id: $0.1) },
                              inputs: nil, buttons: nil, power: .off, reachable: true, needsPairing: false, detail: [:], updated: nil),
        ]
    }

    /// The demo hub acts like the hub's FakeTV: commands change state straight away.
    private func runDemo(_ id: String, _ action: String, _ arg: JSONValue?) throws {
        guard var d = devices[id] else { throw HubError("No device \(id)") }
        switch action {
        case "power_on":
            d.power = .on
            if d.detail["app"] == nil { d.detail["app"] = .string("com.webos.app.home") }
        case "power_off":
            d.power = .off
        case "launch", "input":
            guard d.isOn else { throw HubError("\(d.name) is off") }
            d.detail["app"] = arg ?? .null
        case "volume":
            d.detail["volume"] = arg ?? .null
        case "mute":
            d.detail["muted"] = arg ?? .null
        case "button":
            guard d.isOn else { throw HubError("\(d.name) is off") }
            let v = d.volume ?? 10
            if arg?.string == "VOLUMEUP" { d.detail["volume"] = .number(Double(min(100, v + 1))) }
            if arg?.string == "VOLUMEDOWN" { d.detail["volume"] = .number(Double(max(0, v - 1))) }
            if arg?.string == "HOME" { d.detail["app"] = .string("com.webos.app.home") }
        default:
            break
        }
        devices[id] = d
        // The Sony TV wakes with the Apple TV, like HDMI-CEC does at home.
        if id == "appletv", action == "power_on" || action == "launch" { devices["sony"]?.power = .on; devices["sony"]?.detail["app"] = d.detail["app"] }
    }
}
