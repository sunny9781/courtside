import SwiftUI
// MARK: Buttons

struct ChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .foregroundStyle(selected ? Theme.bg : Theme.soft)
            .background(Capsule().fill(selected ? Theme.text : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 24)
            .frame(height: 46)
            .foregroundStyle(Theme.onAccent)
            .background(Capsule().fill(Theme.accent))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.soft

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .foregroundStyle(tint)
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(Theme.soft)
            .background(Circle().fill(Theme.raised))
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Building blocks

/// A card that lights up on hover and acts as one big button.
struct CardButton<Content: View>: View {
    var radius: CGFloat = 14
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: radius).fill(hovering ? Theme.cardHover : Theme.card))
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Badge: View {
    let text: String
    var highlight = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(highlight ? Theme.matchText : Theme.text)
            .background(RoundedRectangle(cornerRadius: 7).fill(highlight ? Theme.matchBG : Theme.raised))
    }
}

/// Team logo from the schedule feed, or the team's abbreviation when there's no logo.
struct TeamBadge: View {
    let abbr: String
    var logo: URL? = nil
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Theme.raised)
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit().padding(size * 0.14)
            } placeholder: {
                Text(abbr)
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .frame(width: size, height: size)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.display(20))
            .foregroundStyle(Theme.text)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.display(38))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            trailing
        }
    }
}

struct Banner: View {
    let text: String
    var icon = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
            Text(text)
                .foregroundStyle(Theme.soft)
            Spacer()
        }
        .font(.system(size: 13))
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}

/// Text field styled for the dark panels.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }
}

/// A big, easy back button: a pill 40 points tall with a hover state, plus ⌘[ like other Mac apps.
/// Large targets like this also suit a TV remote's directional pad later.
struct BackButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(hovering ? Theme.cardHover : Theme.raised))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("[", modifiers: .command)
        .help("Back (⌘[)")
    }
}

/// A round icon button big enough to hit easily (36 points).
struct RoundIconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Circle().fill(hovering ? Theme.cardHover : Theme.raised))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
