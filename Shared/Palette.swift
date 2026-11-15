import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0E1116)
    static let sidebar = Color(hex: 0x131820)
    static let card = Color(hex: 0x171B22)
    static let cardHover = Color(hex: 0x1E242E)
    static let raised = Color(hex: 0x232A35)
    static let border = Color(hex: 0x2E3643)
    static let text = Color(hex: 0xF2F4F7)
    static let soft = Color(hex: 0xD5DAE2)
    static let muted = Color(hex: 0x9AA3B2)
    static let accent = Color(hex: 0xFF8A3D)
    static let onAccent = Color(hex: 0x14100C)
    static let matchBG = Color(hex: 0x3A2614)
    static let matchText = Color(hex: 0xFFD9BD)
    static let danger = Color(hex: 0xFF6B6B)
    static let winning = Color(hex: 0x4ADE80)
    static let losing = Color(hex: 0xF87171)
    static let champion = Color(hex: 0xFACC15)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Game {
    /// Score colour for one side: live leader green, trailing red; final winner gold, loser grey;
    /// tied stays white; not started is grey.
    func scoreColor(_ side: Team) -> Color {
        let other = side == away ? home : away
        guard let mine = Double(side.score), let theirs = Double(other.score) else { return Theme.text }
        switch state {
        case .upcoming:
            return Theme.muted
        case .live:
            if mine == theirs { return Theme.winning }
            return mine > theirs ? Theme.winning : Theme.losing
        case .finished:
            if mine == theirs { return Theme.text }
            return mine > theirs ? Theme.champion : Theme.muted
        }
    }
}
