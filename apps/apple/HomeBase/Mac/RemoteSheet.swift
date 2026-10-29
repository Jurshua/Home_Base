import SwiftUI

/// The remote on Mac Home. A bar along the bottom of the window with play and volume slides up
/// into a full remote and tucks back down to the bar. Arrows, OK and playback go to whatever is
/// playing on the screen (the Apple TV for the Sony); power, input and volume go to the screen.
struct RemoteSheet: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    let screen: ScreenStatus
    @State private var drag: CGFloat = 0
    @State private var sent: String?
    @State private var sentCount = 0
    @State private var paused = false

    private let height: CGFloat = 588
    private let peek: CGFloat = 86

    private var open: Bool { selection.remoteOpen }

    /// Gets the arrows, OK, Back, Home and playback.
    private var nav: Device? {
        if let p = screen.player, p.id != screen.display?.id, p.can("button"), !(p.buttons ?? []).isEmpty { return p }
        return screen.display
    }

    private var tv: Device? { screen.display }

    var body: some View {
        ZStack(alignment: .bottom) {
            if open {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { set(open: false) }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            panel
                .offset(y: max(0, (open ? 0 : height - peek) + drag))
        }
        .sensoryFeedback(.selection, trigger: sentCount)
        .onChange(of: screen.id) { _, _ in paused = false }
    }

    private func set(open: Bool) {
        withAnimation(Theme.sheet) {
            selection.remoteOpen = open
            drag = 0
        }
    }

    // MARK: Panel

    private var panel: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        let live = screen.isOn
        return VStack(spacing: 0) {
            grabber
            peekRow
                .padding(.horizontal, 16)
                .frame(height: peek - 22)
            VStack(spacing: 22) {
                utilities
                HStack(alignment: .center, spacing: 0) {
                    sideKeys
                    Spacer(minLength: 12)
                    ZStack(alignment: .top) {
                        DPad { press($0, on: nav) }
                        flash.offset(y: -22)
                    }
                    Spacer(minLength: 12)
                    rockers
                }
                .disabled(!live)
                .opacity(live ? 1 : 0.4)
                transport
                    .disabled(!live)
                    .opacity(live ? 1 : 0.4)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
            Spacer(minLength: 0)
        }
        .frame(width: 580, height: height, alignment: .top)
        .background(Color(white: 0.09).opacity(0.8), in: shape)
        .glass(in: shape)
        .overlay(shape.stroke(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 30, y: -8)
        .foregroundStyle(.white)
        .animation(Theme.settle, value: live)
    }

    /// The handle: click it, or drag it up and down.
    private var grabber: some View {
        Capsule().fill(.white.opacity(0.3))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .onTapGesture { set(open: !open) }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in drag = open ? max(0, v.translation.height) : min(0, v.translation.height) }
                    .onEnded { v in
                        let t = v.translation.height
                        set(open: open ? t < 90 : t < -60)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(open ? "Tuck the remote away" : "Open the remote")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { set(open: !open) }
    }

    private var peekRow: some View {
        HStack(spacing: 10) {
            Button { set(open: !open) } label: {
                HStack(spacing: 12) {
                    ArtworkView(art: screen.art)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(screen.isOn ? screen.title : screen.short)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        Text("\(screen.spot.name) remote").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Tuck the remote away" : "Open the remote")

            Group {
                RoundButton(icon: paused ? "play.fill" : "pause.fill", label: paused ? "Play" : "Pause") { playPause() }
                RoundButton(icon: "speaker.wave.1.fill", label: "Volume down") { volume(up: false) }
                RoundButton(icon: "speaker.wave.3.fill", label: "Volume up") { volume(up: true) }
            }
            .disabled(!screen.isOn)
            .opacity(screen.isOn ? 1 : 0.4)

            RoundButton(icon: "chevron.up", label: open ? "Tuck the remote away" : "Open the remote") { set(open: !open) }
                .rotationEffect(.degrees(open ? 180 : 0))
        }
    }

    // MARK: Keys

    private var utilities: some View {
        HStack(spacing: 10) {
            if let tv {
                let busy = hub.pending.contains(tv.id)
                UtilityKey(title: busy ? "…" : "Power", icon: "power", on: screen.isOn) {
                    if screen.phase == .needsPairing { hub.pair(tv.id) } else { hub.setPower(tv.id, on: !screen.isOn) }
                    show(screen.isOn ? "Turning off" : "Turning on")
                }
                if let inputs = tv.inputs, !inputs.isEmpty {
                    Menu {
                        ForEach(inputs) { input in
                            Button(input.name) {
                                hub.send(tv.id, "input", .string(input.id))
                                show(input.name)
                            }
                        }
                    } label: {
                        UtilityLabel(title: "Input", icon: "rectangle.on.rectangle", on: false)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .disabled(!screen.isOn)
                }
                if tv.can("mute") {
                    UtilityKey(title: tv.muted ? "Muted" : "Mute", icon: tv.muted ? "speaker.slash.fill" : "speaker.slash", on: tv.muted) {
                        hub.send(tv.id, "mute", .bool(!tv.muted))
                        show(tv.muted ? "Sound on" : "Muted")
                    }
                    .disabled(!screen.isOn)
                }
            }
            if has("INFO", nav) {
                UtilityKey(title: "Info", icon: "info.circle", on: false) { press("INFO", on: nav) }.disabled(!screen.isOn)
            }
            if has("EXIT", nav) {
                UtilityKey(title: "Exit", icon: "xmark.circle", on: false) { press("EXIT", on: nav) }.disabled(!screen.isOn)
            }
        }
    }

    private var sideKeys: some View {
        VStack(spacing: 14) {
            SideKey(title: "Back", icon: "arrow.uturn.backward") { press("BACK", on: nav) }
            SideKey(title: "Home", icon: "house") { press("HOME", on: nav) }
            if has("MENU", nav) {
                SideKey(title: "Menu", icon: "line.3.horizontal") { press("MENU", on: nav) }
            }
        }
    }

    private var rockers: some View {
        let target = volumeTarget
        let level = tv?.volume
        return HStack(spacing: 10) {
            Rocker(value: tv?.muted == true ? "–" : level.map { String($0) } ?? "",
                   caption: tv?.muted == true ? "Muted" : "Vol",
                   upLabel: "Volume up", downLabel: "Volume down",
                   up: { volume(up: true) }, down: { volume(up: false) })
                .disabled(target == nil)
            if has("CHANNELUP", tv) {
                Rocker(value: "", caption: "Ch", upLabel: "Channel up", downLabel: "Channel down",
                       up: { press("CHANNELUP", on: tv) }, down: { press("CHANNELDOWN", on: tv) })
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 24) {
            if has("REWIND", nav) {
                TransportKey(icon: "gobackward.10", label: "Back 10 seconds", size: 56) { press("REWIND", on: nav, as: "Back 10 s") }
            }
            TransportKey(icon: paused ? "play.fill" : "pause.fill", label: paused ? "Play" : "Pause", size: 72, primary: true) { playPause() }
            if has("FASTFORWARD", nav) {
                TransportKey(icon: "goforward.10", label: "Forward 10 seconds", size: 56) { press("FASTFORWARD", on: nav, as: "Forward 10 s") }
            }
        }
    }

    /// A pill that pops up over the pad naming the last button sent.
    @ViewBuilder private var flash: some View {
        if let sent {
            Text(sent)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.white, in: Capsule())
                .id(sentCount)
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: Sending

    private func has(_ button: String, _ device: Device?) -> Bool {
        device?.buttons?.contains(button) ?? false
    }

    /// Volume goes to the TV when it takes volume buttons, otherwise to the player.
    private var volumeTarget: Device? {
        if has("VOLUMEUP", tv) { return tv }
        if has("VOLUMEUP", nav) { return nav }
        return nil
    }

    private static let names = ["UP": "Up", "DOWN": "Down", "LEFT": "Left", "RIGHT": "Right", "ENTER": "OK",
                                "BACK": "Back", "HOME": "Home", "MENU": "Menu", "INFO": "Info", "EXIT": "Exit",
                                "CHANNELUP": "Channel up", "CHANNELDOWN": "Channel down"]

    private func press(_ button: String, on device: Device?, as name: String? = nil) {
        guard let device else { return }
        hub.press(device.id, button)
        show(name ?? RemoteSheet.names[button] ?? button.capitalized)
    }

    private func volume(up: Bool) {
        guard let d = volumeTarget else { return }
        hub.press(d.id, up ? "VOLUMEUP" : "VOLUMEDOWN")
        let next = (d.volume ?? 0) + (up ? 1 : -1)
        show(d.volume == nil ? (up ? "Volume up" : "Volume down") : "Volume \(max(0, min(100, next)))")
    }

    private func playPause() {
        guard let d = nav else { return }
        if has("PLAYPAUSE", d) {
            hub.press(d.id, "PLAYPAUSE")
        } else {
            hub.press(d.id, paused ? "PLAY" : "PAUSE")
        }
        show(paused ? "Play" : "Pause")
        paused.toggle()
    }

    private func show(_ label: String) {
        sentCount += 1
        let n = sentCount
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { sent = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if sentCount == n { withAnimation(.easeOut(duration: 0.25)) { sent = nil } }
        }
    }
}

// MARK: Pieces

/// Arrows round an OK button, sized for a thumb or a mouse.
private struct DPad: View {
    let send: (String) -> Void

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.07))
            Circle().stroke(.white.opacity(0.06), lineWidth: 1)
            arrow("chevron.up", "UP", "Up").offset(y: -84)
            arrow("chevron.down", "DOWN", "Down").offset(y: 84)
            arrow("chevron.left", "LEFT", "Left").offset(x: -84)
            arrow("chevron.right", "RIGHT", "Right").offset(x: 84)
            Button { send("ENTER") } label: {
                Text("OK")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 100, height: 100)
                    .background(.white.opacity(0.16), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PadPress(flash: true))
            .accessibilityLabel("OK")
        }
        .frame(width: 248, height: 248)
    }

    private func arrow(_ icon: String, _ button: String, _ label: String) -> some View {
        Button { send(button) } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(PadPress())
        .accessibilityLabel(label)
    }
}

/// A pad key: a soft glow while pressed, white for OK.
private struct PadPress: ButtonStyle {
    var flash = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(flash && configuration.isPressed ? Color.black : Color.white)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? (flash ? 1 : 0.18) : 0)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct UtilityLabel: View {
    let title: String
    let icon: String
    let on: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .foregroundStyle(on ? Color.black : Color.white)
        .background(on ? Color.white : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct UtilityKey: View {
    let title: String
    let icon: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { UtilityLabel(title: title, icon: icon, on: on) }
            .buttonStyle(PressButtonStyle())
            .animation(Theme.settle, value: on)
    }
}

private struct SideKey: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .frame(width: 64, height: 64)
            .background(.white.opacity(0.1), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(PadPress())
        .accessibilityLabel(title)
    }
}

/// A tall up/down key with the level in the middle, like a TV remote's volume rocker.
private struct Rocker: View {
    let value: String
    let caption: String
    let upLabel: String
    let downLabel: String
    let up: () -> Void
    let down: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            key("plus", upLabel, up)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                if !value.isEmpty {
                    Text(value).font(.system(size: 20, weight: .bold)).contentTransition(.numericText())
                }
                Text(caption.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.5).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            key("minus", downLabel, down)
        }
        .padding(.vertical, 6)
        .frame(width: 72, height: 248)
        .background(.white.opacity(0.07), in: Capsule())
        .animation(Theme.settle, value: value)
    }

    private func key(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(PadPress())
        .accessibilityLabel(label)
    }
}

private struct TransportKey: View {
    let icon: String
    let label: String
    let size: CGFloat
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(primary ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(primary ? Color.white : Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressButtonStyle())
        .accessibilityLabel(label)
    }
}
