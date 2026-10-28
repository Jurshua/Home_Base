import SwiftUI

// The iPhone tabs beyond Home. The Mac comes first, so these are simple for now.

struct ScreensView: View {
    @Environment(HubStore.self) private var hub
    @Environment(Selection.self) private var selection
    @Binding var tab: Tab
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screens").font(.heroTitle).kerning(-0.8)
                    Text("\(hub.screens.filter(\.isOn).count) of \(hub.screens.count) screens on")
                        .font(.system(size: 14)).foregroundStyle(Theme.tertiary)
                }
                ForEach(hub.screens) { s in
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            ArtworkView(art: s.art)
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.isOn ? s.title : s.short).font(.system(size: 18, weight: .bold))
                                Text(s.meta).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            }
                            .padding(16)
                        }
                        .frame(height: 196)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        HStack {
                            Text(s.spot.name).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            if s.canControl {
                                Pill(title: "Remote", style: .quiet, height: 34) { path.append(Route.remote(s.id)) }
                                Pill(title: "Launch", style: .primary, height: 34) { selection.screen = s.id; tab = .launch }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 124)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

struct LaunchView: View {
    var body: some View {
        ScrollView {
            LaunchGrid(columns: 2)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 124)
                .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}

struct LightsView: View {
    var body: some View {
        ScrollView {
            ComingSoon(title: "Lights", icon: "lightbulb", note: "Philips Hue arrives in milestone 5.")
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 124)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
}
