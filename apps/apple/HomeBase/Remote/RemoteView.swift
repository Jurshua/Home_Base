import SwiftUI

/// A remote for whichever screen you pick. Swipe the pad to move, tap it to select.
struct RemoteView: View {
    @Environment(HubStore.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State var screenID: String
    var showsBack = true
    @State private var playing = true
    @State private var choosingInput = false
    @FocusState private var focused: Bool

    var body: some View {
        let screens = hub.screens.filter { $0.spot.display != nil }
        let screen = hub.screen(screenID) ?? screens[0]
        let device = screen.display
        let live = screen.isOn && device != nil

        VStack(spacing: 18) {
            header(screen)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(screens) { s in
                        let sel = s.id == screen.id
                        Button { screenID = s.id } label: {
                            Text(s.spot.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(sel ? Color.black : Color.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 40)
                                .background(sel ? Color.white : Theme.fill, in: Capsule())
                                .scaleEffect(sel ? 1.04 : 1)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressButtonStyle())
                        .accessibilityAddTraits(sel ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .animation(Theme.lift, value: screenID)

            Text(status(screen))
                .font(.system(size: 13))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.gutter)
                .contentTransition(.opacity)

            Touchpad(enabled: live) { button in
                if let device { hub.press(device.id, button) }
            }
            .padding(.horizontal, Theme.gutter)

            if let device {
                keys(device, enabled: live)
                volume(device, enabled: live)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $choosingInput) {
            if let device { InputPicker(device: device) { choosingInput = false } }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress { press in
            guard live, let device else { return .ignored }
            let map: [KeyEquivalent: String] = [.upArrow: "UP", .downArrow: "DOWN", .leftArrow: "LEFT", .rightArrow: "RIGHT",
                                                .return: "ENTER", .space: "ENTER", .escape: "BACK", .delete: "BACK"]
            guard let button = map[press.key] else { return .ignored }
            hub.press(device.id, button)
            return .handled
        }
    }

    private func header(_ screen: ScreenStatus) -> some View {
        HStack {
            if showsBack {
                RoundButton(icon: "chevron.left", label: "Back") { dismiss() }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("Remote").font(.system(size: 17, weight: .semibold))
            Spacer()
            if let d = screen.display {
                RoundButton(icon: "power", label: (screen.isOn ? "Turn off " : "Turn on ") + screen.spot.name,
                            on: screen.isOn, busy: hub.pending.contains(d.id)) {
                    if screen.phase == .needsPairing { hub.pair(d.id) } else { hub.setPower(d.id, on: !screen.isOn) }
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func status(_ s: ScreenStatus) -> String {
        switch s.phase {
        case .on: return "Controlling \(s.title) on \(s.spot.name)"
        case .off: return "\(s.spot.name) is off · the power button turns it on"
        case .needsPairing: return hub.pending.contains(s.display?.id ?? "") ? "Press Yes on the TV" : "\(s.spot.name) needs pairing · tap power to pair"
        case .unreachable: return "\(s.spot.name) isn't responding"
        case .notSetUp: return s.spot.arrives
        }
    }

    private func keys(_ d: Device, enabled: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            Key(title: "Back", icon: "arrow.uturn.backward") { hub.press(d.id, "BACK") }
            Key(title: "Home", icon: "house") { hub.press(d.id, "HOME") }
            Key(title: playing ? "Pause" : "Play", icon: playing ? "pause.fill" : "play.fill") {
                hub.press(d.id, playing ? "PAUSE" : "PLAY")
                playing.toggle()
            }
            Key(title: "Input", icon: "rectangle.on.rectangle", enabled: !(d.inputs ?? []).isEmpty) { choosingInput = true }
        }
        .padding(.horizontal, Theme.gutter)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func volume(_ d: Device, enabled: Bool) -> some View {
        let level = d.volume ?? 0
        return HStack(spacing: 12) {
            RoundButton(icon: "minus", label: "Volume down", size: 48) { hub.press(d.id, "VOLUMEDOWN") }
            Button { hub.send(d.id, "mute", .bool(!d.muted)) } label: {
                VStack(spacing: 6) {
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.18))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).frame(width: d.muted ? 0 : g.size.width * CGFloat(min(level, 50)) / 50)
                            }
                    }
                    .frame(height: 4)
                    Text(d.muted ? "\(d.name) muted · tap to unmute" : "\(d.name) volume \(level)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                        .contentTransition(.numericText(value: Double(level)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.muted ? "Unmute" : "Mute, volume \(level)")
            RoundButton(icon: "plus", label: "Volume up", size: 48) { hub.press(d.id, "VOLUMEUP") }
        }
        .padding(6)
        .background(Theme.fillSoft, in: Capsule())
        .padding(.horizontal, Theme.gutter)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(Theme.settle, value: level)
        .sensoryFeedback(.increase, trigger: level)
    }
}

private struct Key: View {
    let title: String
    let icon: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressButtonStyle())
        .disabled(!enabled)
    }
}

/// The big pad. A swipe moves one step per 56 points, so a long drag scrolls through a list; a tap selects.
struct Touchpad: View {
    let enabled: Bool
    let send: (String) -> Void

    @State private var anchor: CGPoint = .zero
    @State private var finger: CGSize = .zero
    @State private var touching = false
    @State private var moved = false
    @State private var steps = 0

    private let step: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Theme.fillSoft)
            VStack(spacing: 12) {
                Circle()
                    .fill(touching ? Color.white : Color.white.opacity(0.12))
                    .frame(width: 58, height: 58)
                    .offset(x: finger.width * 0.25, y: finger.height * 0.25)
                    .animation(Theme.lift, value: finger)
                    .animation(Theme.settle, value: touching)
                Text(enabled ? "Swipe to move · tap to select" : "Turn the screen on to use the remote")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 220)
        .contentShape(RoundedRectangle(cornerRadius: 34))
        .gesture(drag)
        .opacity(enabled ? 1 : 0.5)
        .allowsHitTesting(enabled)
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityElement()
        .accessibilityLabel("Touchpad")
        .accessibilityHint("Swipe to move, double tap to select")
        .accessibilityAction { send("ENTER") }
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: send("UP")
            case .decrement: send("DOWN")
            @unknown default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !touching { touching = true; moved = false; anchor = v.startLocation }
                finger = v.translation
                let dx = v.location.x - anchor.x, dy = v.location.y - anchor.y
                if abs(dx) >= step, abs(dx) > abs(dy) {
                    emit(dx > 0 ? "RIGHT" : "LEFT")
                    anchor.x += dx > 0 ? step : -step
                    anchor.y = v.location.y
                } else if abs(dy) >= step {
                    emit(dy > 0 ? "DOWN" : "UP")
                    anchor.y += dy > 0 ? step : -step
                    anchor.x = v.location.x
                }
            }
            .onEnded { v in
                let d = hypot(v.translation.width, v.translation.height)
                if !moved && d < 14 { emit("ENTER") }
                touching = false
                finger = .zero
            }
    }

    private func emit(_ button: String) {
        if button != "ENTER" { moved = true }
        steps += 1
        send(button)
    }
}

/// HDMI inputs and the like for a TV.
struct InputPicker: View {
    @Environment(HubStore.self) private var hub
    let device: Device
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(device.name) input").font(.shelfTitle).padding(.bottom, 10)
            ForEach(device.inputs ?? []) { input in
                let current = device.currentApp == input.id
                Button {
                    hub.send(device.id, "input", .string(input.id))
                    done()
                } label: {
                    HStack {
                        Text(input.name).font(.system(size: 16, weight: .semibold))
                        Spacer()
                        if current { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)) }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    .background(current ? Theme.fill : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 24)
        .foregroundStyle(.white)
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }
}

#Preview {
    NavigationStack { RemoteView(screenID: "lg") }
        .environment(HubStore.demo())
        .preferredColorScheme(.dark)
}
