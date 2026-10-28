import SwiftUI

/// Pick a screen, then what to play on it. Launching turns the screen on if it's off.
struct LaunchGrid: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    var columns = 2

    var body: some View {
        let screens = hub.screens
        let current = screens.first { $0.id == selection.screen } ?? screens[0]

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Launch").font(.heroTitle).kerning(-0.8)
                Text("Choose a screen, then what to play. Home Base turns the screen on for you.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiary)
            }

            HStack(spacing: 6) {
                ForEach(screens) { s in
                    let sel = s.id == current.id
                    Button { selection.screen = s.id } label: {
                        Text(s.spot.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(sel ? Color.black : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(sel ? Color.white : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.fill, in: Capsule())
            .frame(maxWidth: 520)
            .animation(Theme.lift, value: current.id)

            if current.apps.isEmpty {
                ComingSoon(title: current.spot.name, icon: "tv", note: current.phase == .notSetUp ? current.spot.arrives : "\(current.spot.name) has no apps to open.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                    ForEach(current.apps) { app in
                        GeometryReader { g in
                            AppCard(app: app, width: g.size.width, playing: current.isOn && current.title == app.name) {
                                hub.launch(app, on: current)
                            }
                        }
                        .aspectRatio(1 / 0.55, contentMode: .fit)
                    }
                }
            }
        }
    }
}

/// A calm placeholder for parts of the app that arrive in a later milestone.
struct ComingSoon: View {
    let title: String
    let icon: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(note).font(.system(size: 14)).foregroundStyle(Theme.tertiary)
        }
        .padding(28)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.fillSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
