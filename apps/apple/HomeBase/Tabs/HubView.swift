import SwiftUI

/// Where the hub is, how the link is doing, and every device it knows about.
/// On Mac this is the Settings window (⌘,); on iPhone it opens from Home.
struct HubView: View {
    @Environment(HubStore.self) private var hub
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hub").font(.heroTitle).kerning(-0.8)
                    Text(linkText).font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("ADDRESS").font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.tertiary)
                    HStack(spacing: 10) {
                        TextField("mac-mini.local:4900", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .background(Theme.fill, in: Capsule())
                            .onSubmit { hub.use(address: draft) }
                        Pill(title: "Connect", style: .primary) { hub.use(address: draft) }
                    }
                    Text("The Mac Mini's name or IP and port 4900. Leave it empty to try Home Base with pretend devices.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }

                if !hub.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DEVICES").font(.system(size: 12, weight: .semibold)).kerning(0.4).foregroundStyle(Theme.tertiary)
                        ForEach(hub.devices.values.sorted { $0.name < $1.name }) { d in
                            HStack(spacing: 12) {
                                Circle().fill(d.isOn ? Color.white : Color.white.opacity(0.25)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d.name).font(.system(size: 15, weight: .semibold))
                                    Text(state(d)).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                                }
                                Spacer()
                                if d.needsPairing && d.can("pair") {
                                    Pill(title: hub.pending.contains(d.id) ? "Press Yes on the TV" : "Pair", style: .primary,
                                         height: 34, busy: hub.pending.contains(d.id)) { hub.pair(d.id) }
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 58)
                            .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(Theme.gutter)
            .padding(.top, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .foregroundStyle(.white)
        .onAppear { draft = hub.address }
    }

    private var linkText: String {
        switch hub.link {
        case .demo: return "Demo mode: these are pretend devices"
        case .connecting: return "Connecting to \(hub.address)…"
        case .live: return "Live with \(hub.address)"
        case .offline(let why): return why
        }
    }

    private func state(_ d: Device) -> String {
        if d.needsPairing { return "Needs pairing" }
        if !d.reachable && d.power != .off { return "Not responding" }
        return [d.kind.replacingOccurrences(of: "_", with: " "), d.power.rawValue].joined(separator: " · ")
    }
}
