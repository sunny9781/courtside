import SwiftUI

/// Settings › Updates › What's new: every update with this app's changes. Click one to open it; the newest is open.
struct WhatsNewList: View {
    @State private var open: Set<String> = Set(Changelog.forThisApp.prefix(1).map(\.id))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Changelog.forThisApp.enumerated()), id: \.element.id) { index, release in
                if index > 0 { Rectangle().fill(Theme.raised).frame(height: 1) }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if open.contains(release.id) { open.remove(release.id) } else { open.insert(release.id) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(open.contains(release.id) ? 90 : 0))
                        Text(release.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if index == 0 {
                            Text("LATEST")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent))
                        }
                        Spacer()
                        Text(release.dateLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if open.contains(release.id) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(release.changes, id: \.self) { change in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                Text(change.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.soft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}
