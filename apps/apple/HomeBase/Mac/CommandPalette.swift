import SwiftUI

/// ⌘K: type a few letters of anything Home Base can do and press Return.
struct CommandPalette: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Environment(\.openWindow) private var openWindow
    @Binding var isPresented: Bool
    @Binding var tab: MacTab
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var typing: Bool

    struct Action: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let run: () -> Void
    }

    var body: some View {
        let results = matches
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                    TextField("Search or run an action", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20))
                        .focused($typing)
                        .onSubmit { run(results) }
                        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(results.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                        .onKeyPress(.escape) { isPresented = false; return .handled }
                }
                .padding(.horizontal, 20)
                .frame(height: 60)

                if !results.isEmpty {
                    Divider().overlay(.white.opacity(0.08))
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { i, a in
                                    row(a, on: i == highlighted)
                                        .id(i)
                                        .onTapGesture { highlighted = i; run(results) }
                                }
                            }
                            .padding(8)
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxHeight: 360)
                        .onChange(of: highlighted) { _, i in proxy.scrollTo(i) }
                    }
                }
            }
            .frame(width: 600)
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            .padding(.top, 96)
        }
        .onAppear { typing = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ a: Action, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.icon).frame(width: 22)
            Text(a.title).font(.system(size: 15, weight: .medium))
            Spacer()
            Text(a.detail).font(.system(size: 13)).foregroundStyle(on ? Color.black.opacity(0.6) : Theme.tertiary)
        }
        .foregroundStyle(on ? Color.black : Color.white)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(on ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func run(_ results: [Action]) {
        guard results.indices.contains(highlighted) else { return }
        isPresented = false
        results[highlighted].run()
    }

    private var matches: [Action] {
        let all = actions
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return Array(all.prefix(8)) }
        return all.filter { a in
            let hay = (a.title + " " + a.detail).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    private var actions: [Action] {
        var list: [Action] = []
        // The screen you're looking at comes first, so "netflix" opens it there.
        let screens = hub.screens.sorted { a, _ in a.id == selection.screen }
        for s in screens where s.canControl {
            guard let d = s.display else { continue }
            if s.isOn {
                list.append(Action(id: "off-\(s.id)", title: "Turn off \(s.spot.name)", detail: s.title, icon: "power") {
                    hub.setPower(d.id, on: false)
                })
                list.append(Action(id: "remote-\(s.id)", title: "Remote for \(s.spot.name)", detail: "Window", icon: "appletvremote.gen4") {
                    openWindow(id: "remote", value: s.id)
                })
            } else if s.phase == .needsPairing {
                list.append(Action(id: "pair-\(s.id)", title: "Pair \(s.spot.name)", detail: "Press Yes on the TV", icon: "link") {
                    hub.pair(d.id)
                })
            } else {
                list.append(Action(id: "on-\(s.id)", title: "Turn on \(s.spot.name)", detail: "Screen", icon: "power") {
                    hub.setPower(d.id, on: true)
                })
            }
            for app in s.apps {
                list.append(Action(id: "open-\(s.id)-\(app.id)", title: "Open \(app.name)", detail: "on \(s.spot.name)", icon: "play.rectangle") {
                    selection.screen = s.id
                    hub.launch(app, on: s)
                })
            }
            for input in s.inputs {
                list.append(Action(id: "input-\(s.id)-\(input.id)", title: "Switch \(s.spot.name) to \(input.name)", detail: "Input", icon: "rectangle.on.rectangle") {
                    hub.send(d.id, "input", .string(input.id))
                })
            }
        }
        if hub.screens.contains(where: \.isOn) {
            list.insert(Action(id: "all-off", title: "All off", detail: "Keeps the hub on", icon: "moon") { hub.allOff() }, at: 0)
        }
        for t in MacTab.allCases where !t.dimmed {
            list.append(Action(id: "tab-\(t.id)", title: "Go to \(t.rawValue)", detail: "Tab", icon: "arrow.right.circle") { tab = t })
        }
        return list
    }
}
