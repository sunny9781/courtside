import SwiftUI

/// The EPG as a timeline, shown when the phone is turned sideways on a category: a channel column, then two and a
/// half hours of programmes laid out by time, coloured by sport (or the channel's own colour), with an orange line
/// at the current time and what's already been on a shade darker. Tap a row to play it (again for full screen).
struct IOSGuideTimeline: View {
    @EnvironmentObject var model: AppModel
    let channels: [Channel]
    let playingID: Int?
    let onTap: (Channel) -> Void

    private let channelWidth: CGFloat = 150
    private let rowHeight: CGFloat = 52
    private let span: TimeInterval = 150 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let start = Self.windowStart(now)
            GeometryReader { geo in
                let area = max(geo.size.width - channelWidth - 8, 200)
                VStack(spacing: 0) {
                    header(start: start, now: now, area: area)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(channels) { channel in
                                row(channel, start: start, now: now, area: area)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onTap(channel) }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    /// The guide starts at the last half hour.
    static func windowStart(_ now: Date) -> Date {
        let t = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.down) * 1800)
    }

    private func x(_ date: Date, _ start: Date, _ area: CGFloat) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / span) * area
    }

    private func header(start: Date, now: Date, area: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: channelWidth + 8, height: 24)
            ZStack(alignment: .leading) {
                ForEach(0..<5, id: \.self) { i in
                    let t = start.addingTimeInterval(Double(i) * 1800)
                    Text(t.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .offset(x: x(t, start, area) + 4)
                }
            }
            .frame(width: area, height: 24, alignment: .leading)
            .clipped()
        }
    }

    private func row(_ channel: Channel, start: Date, now: Date, area: CGFloat) -> some View {
        let end = start.addingTimeInterval(span)
        let programmes = Array((model.guide[channel.epgID] ?? []).overlapping(start, end))
        let playing = channel.id == playingID
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                IOSChannelIcon(url: channel.icon, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(playing ? Theme.accent : Theme.text)
                        .lineLimit(2)
                }
                ReliabilityDot(channelID: channel.id, size: 7, bare: true)
            }
            .frame(width: channelWidth, alignment: .leading)
            .padding(.leading, 8)
            .padding(.vertical, 2)
            // What's playing: an orange outline on its channel and the show on now (2.21, like the TVs).
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(playing ? Theme.accent : .clear, lineWidth: 2))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.card)
                ForEach(programmes, id: \.self) { p in
                    let from = max(x(p.start, start, area), 0)
                    let to = min(x(p.end, start, area), area)
                    cell(p, channel: channel, width: max(to - from - 2, 2), now: now, start: start, area: area, from: from)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(playing && p.start <= now && p.end > now ? Theme.accent : .clear, lineWidth: 2))
                        .offset(x: from)
                }
                // The current time.
                Rectangle().fill(Theme.accent).frame(width: 2).offset(x: x(now, start, area))
            }
            .frame(width: area, height: rowHeight, alignment: .leading)
            .clipped()
        }
    }

    @ViewBuilder
    private func tags(_ channel: Channel) -> some View {
        let parts = [model.measuredQuality[channel.id],
                     model.measuredFrameRate[channel.id].map(PlaybackController.fpsLabel),
                     model.measuredAudio[channel.id]].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }

    private func cell(_ p: Programme, channel: Channel, width: CGFloat, now: Date, start: Date, area: CGFloat,
                      from: CGFloat) -> some View {
        let colour = GuideColour.fill(title: p.title, channel: channel, games: model.games)
        // What's already been on is darker.
        let past = p.start < now ? min(max(x(now, start, area) - from, 0), width) : 0
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6).fill(colour)
            Rectangle().fill(Color.black.opacity(0.3)).frame(width: past)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title.isEmpty ? "Untitled" : p.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(p.start.formatted(date: .omitted, time: .shortened)) – \(p.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: width, height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
