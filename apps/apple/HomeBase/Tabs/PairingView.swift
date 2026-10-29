import SwiftUI

/// First run on a new device, or after the hub removed it: find the hub, type the code a trusted
/// device shows, and get a key that's kept in the Keychain.
struct PairingView: View {
    @Environment(HubStore.self) private var hub
    @State private var finder = HubFinder()
    @State private var code = ""
    @State private var name = HubStore.deviceName
    @State private var manual = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.secondary)
                    Text("Pair with your hub").font(.heroTitle).kerning(-0.8)
                    Text("On the Mac Mini, or any device that's already paired, open Home Base › Hub › Pair another device. Type the 6-digit code it shows.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                hubPicker

                VStack(alignment: .leading, spacing: 12) {
                    label("CODE")
                    CodeBoxes(code: code)
                        .overlay {
                            TextField("", text: $code)
                                .focused($typing)
                                .opacity(0.02)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                #endif
                                .onChange(of: code) { _, new in
                                    let digits = String(new.filter(\.isNumber).prefix(6))
                                    if digits != new { code = digits }
                                    error = nil
                                    if digits.count == 6 { submit() }
                                }
                                .accessibilityLabel("Pairing code")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { typing = true }
                }

                VStack(alignment: .leading, spacing: 10) {
                    label("THIS DEVICE")
                    field("Josh's iPhone", text: $name)
                    Text("The hub lists it under this name and logs what it does.")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                }

                if let error {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }

                Pill(title: working ? "Pairing…" : "Pair", style: .primary, busy: working) { submit() }
                    .disabled(code.count != 6 || hub.host.isEmpty || working)
                    .opacity(code.count == 6 && !hub.host.isEmpty ? 1 : 0.5)

                Button("Try the demo instead") { hub.use(address: "") }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .foregroundStyle(.white)
        .animation(Theme.settle, value: error)
        .onAppear {
            finder.start()
            manual = hub.address
            typing = !hub.host.isEmpty
        }
        .onDisappear { finder.stop() }
        .onChange(of: finder.found) { _, found in
            // Nothing chosen yet and exactly one hub on the network: use it.
            if hub.host.isEmpty, found.count == 1, let only = found.first { hub.use(address: only.address) }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 600)
        #endif
    }

    @ViewBuilder private var hubPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("HUB")
                if finder.searching && finder.found.isEmpty { ProgressView().controlSize(.mini).tint(.white) }
            }
            ForEach(finder.found) { f in
                let chosen = hub.host == f.address
                Button { hub.use(address: f.address) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name).font(.system(size: 15, weight: .semibold))
                            Text(f.address).font(.system(size: 12)).foregroundStyle(chosen ? Color.black.opacity(0.6) : Theme.tertiary)
                        }
                        Spacer()
                        if chosen { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)) }
                    }
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 54)
                    .background(chosen ? Color.white : Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
            }
            HStack(spacing: 10) {
                field(finder.found.isEmpty ? "Looking… or type mac-mini.local" : "Or type an address", text: $manual)
                    .onSubmit { hub.use(address: manual) }
                if !manual.isEmpty && manual != hub.address {
                    Pill(title: "Use", style: .quiet, height: 44) { hub.use(address: manual) }
                }
            }
        }
    }

    private func submit() {
        guard code.count == 6, !working, !hub.host.isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await hub.pair(code: code, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? HubStore.deviceName : name)
            } catch {
                self.error = (error as? HubError)?.message ?? error.localizedDescription
                code = ""
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.tertiary)
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.fill, in: Capsule())
    }
}

/// Six boxes that fill in as you type, the next one outlined.
private struct CodeBoxes: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                Text(i < chars.count ? String(chars[i]) : "")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white, lineWidth: i == chars.count ? 2 : 0)
                    }
                    .animation(Theme.lift, value: chars.count)
            }
        }
        .accessibilityHidden(true)
    }
}

/// On a trusted device: show a code another device can pair with, and the devices already paired.
struct PairAnotherDevice: View {
    @Environment(HubStore.self) private var hub
    @State private var code: HubStore.PairingCode?
    @State private var clients: [HubStore.Client] = []
    @State private var error: String?
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAIRED DEVICES").font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.tertiary)

            if let code, Date(timeIntervalSince1970: code.expires) > now {
                VStack(alignment: .leading, spacing: 6) {
                    Text(code.code.map(String.init).joined(separator: " "))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Text("Type this on the new device. It works once, for \(remaining(code)).")
                        .font(.system(size: 13)).foregroundStyle(Theme.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Pill(title: "Pair another device", icon: "plus", style: .quiet, height: 44) {
                    Task {
                        do { code = try await hub.newPairingCode(); error = nil } catch { self.error = (error as? HubError)?.message }
                    }
                }
            }

            ForEach(clients) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.system(size: 15, weight: .semibold))
                        Text(seen(c)).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Button("Remove") {
                        Task {
                            try? await hub.remove(c)
                            await reload()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let error { Text(error).font(.system(size: 13)).foregroundStyle(.orange) }
        }
        .task { await reload() }
        .task(id: code?.code) {
            // Tick the countdown, and refresh the list once the code is used up.
            while code != nil, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
                if let c = code, Date(timeIntervalSince1970: c.expires) <= now { code = nil; await reload() }
                else if Int(now.timeIntervalSince1970) % 3 == 0 { await reload() }
            }
        }
    }

    private func reload() async {
        clients = (try? await hub.pairedDevices()) ?? clients
    }

    private func remaining(_ c: HubStore.PairingCode) -> String {
        let s = max(0, Int(c.expires - now.timeIntervalSince1970))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func seen(_ c: HubStore.Client) -> String {
        guard let t = c.lastSeen else { return "Not used yet" }
        return "Last used " + Date(timeIntervalSince1970: t).formatted(.relative(presentation: .named))
    }
}
