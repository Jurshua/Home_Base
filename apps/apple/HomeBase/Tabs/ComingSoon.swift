import SwiftUI

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
