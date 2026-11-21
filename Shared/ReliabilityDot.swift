import SwiftUI

/// A green, amber or red dot on a game-screen stream: how reliable it has been on this device (2.21, from
/// `StreamStats`). Nothing until the stream has enough history.
struct ReliabilityDot: View {
    @ObservedObject private var stats = StreamStats.shared
    let channelID: Int
    var size: CGFloat = 8
    var padding: CGFloat = 5
    /// Just the dot, no chip around it: for tight spots like the EPG's channel names (2.27).
    var bare = false

    var body: some View {
        if let rating = stats.ratings[channelID], bare {
            Circle()
                .fill(Self.colour(rating))
                .frame(width: size, height: size)
                .accessibilityLabel(Self.words(rating))
        } else if let rating = stats.ratings[channelID] {
            Circle()
                .fill(Self.colour(rating))
                .frame(width: size, height: size)
                .padding(padding)
                .background(RoundedRectangle(cornerRadius: size * 0.75).fill(Color.white.opacity(0.08)))
                .accessibilityLabel(Self.words(rating))
        }
    }

    static func colour(_ r: StreamStats.Rating) -> Color {
        switch r {
        case .good: return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .ok: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .poor: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    static func words(_ r: StreamStats.Rating) -> String {
        switch r {
        case .good: return "Reliable"
        case .ok: return "Sometimes buffers"
        case .poor: return "Unreliable"
        }
    }
}
