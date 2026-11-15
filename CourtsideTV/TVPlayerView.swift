import SwiftUI
import UIKit

struct TVVideoSurface: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Full-screen player.
/// - Swipe or press up/down: previous/next stream for this game (or channel in this category).
/// - Click or swipe left/right: show the info bar.
/// - Play/Pause: pause. Back (Menu): close.
/// A stream that fails, stops, or buffers for 10 seconds switches to the next one (USA and Canada first).
struct TVPlayerView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.bufferMs) private var bufferMs = 2000
    @AppStorage(Prefs.autoSwitch) private var autoSwitch = true
    @ObservedObject private var controller = PlaybackController.shared
    @FocusState private var focused: Bool
    @State private var tried: Set<Int> = []
    @State private var stalledSince: Date?
    @State private var switchingAutomatically = false
    @State private var showInfo = true
    @State private var hideTask: Task<Void, Never>?
    @State private var flipLabel: String?
    @State private var flipTask: Task<Void, Never>?
    let item: NowPlaying

    private var position: Int {
        (item.lineup.firstIndex(where: { $0.id == item.channel.id }) ?? 0) + 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(view: controller.view)
                .ignoresSafeArea()

            statusOverlay

            infoBar
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(showInfo ? 1 : 0)

            if let flipLabel {
                Text(flipLabel)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .up: model.step(-1)
            case .down: model.step(1)
            default: poke()
            }
        }
        .onPlayPauseCommand {
            controller.togglePause()
            poke()
        }
        .onTapGesture { poke() }
        .onExitCommand { model.closePlayer() }
        .onAppear {
            focused = true
            tried = [item.channel.id]
            start()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            checkForStall()
        }
        .onChange(of: item.channel.id) {
            stalledSince = nil
            start()
            if switchingAutomatically {
                switchingAutomatically = false
            } else {
                tried = [item.channel.id]
                showFlipLabel()
            }
        }
        .onChange(of: controller.resolution) {
            if !controller.resolution.isEmpty {
                model.recordQuality(item.channel.id, controller.resolution)
            }
        }
        .onDisappear {
            hideTask?.cancel()
            flipTask?.cancel()
        }
    }

    // MARK: Playback

    private func start() {
        guard let url = model.streamURL(for: item.channel, hls: !PlaybackController.usesVLC) else { return }
        controller.play(url, bufferMs: bufferMs)
        poke()
    }

    private func checkForStall() {
        guard autoSwitch, item.lineup.count > 1 else { return }
        switch controller.status {
        case .failed, .ended:
            switchToNext(reason: "The stream stopped")
        case .buffering, .opening:
            if let since = stalledSince {
                if Date().timeIntervalSince(since) >= 10 { switchToNext(reason: "The stream stalled") }
            } else {
                stalledSince = Date()
            }
        default:
            stalledSince = nil
        }
    }

    private func switchToNext(reason: String) {
        stalledSince = nil
        let untried = item.lineup.filter { !tried.contains($0.id) }
        let preferred = untried.filter { ["USA", "Canada"].contains(Matcher.country(of: $0) ?? "") }
        guard let next = preferred.first ?? untried.first else {
            flipMessage("\(reason). No other streams left to try.")
            return
        }
        tried.insert(next.id)
        switchingAutomatically = true
        controller.stop()
        model.switchStream(to: next)
        flipMessage("\(reason). Switched to \(next.name)")
    }

    // MARK: Overlays

    private func poke() {
        withAnimation(.easeOut(duration: 0.2)) { showInfo = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, controller.status == .playing {
                withAnimation(.easeOut(duration: 0.4)) { showInfo = false }
            }
        }
    }

    private func showFlipLabel() {
        guard item.lineup.count > 1 else { return }
        flipMessage("\(position) of \(item.lineup.count) · \(item.channel.name)", seconds: 2)
    }

    private func flipMessage(_ text: String, seconds: Double = 4) {
        withAnimation(.easeOut(duration: 0.15)) { flipLabel = text }
        flipTask?.cancel()
        flipTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.3)) { flipLabel = nil }
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch controller.status {
        case .opening, .buffering, .idle:
            VStack(spacing: 20) {
                ProgressView()
                Text(controller.status == .buffering ? "Buffering…" : "Opening \(item.channel.name)…")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.soft)
            }
        case .failed(let why):
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                Text(why)
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.soft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Text(item.lineup.count > 1 ? "Swipe up or down for another stream." : "Press Back to choose another channel.")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.muted)
            }
        case .ended:
            Text("The stream stopped. Swipe up or down for another stream.")
                .font(.system(size: 28))
                .foregroundStyle(Theme.soft)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.text.opacity(0.85))
        case .playing:
            EmptyView()
        }
    }

    private var infoBar: some View {
        HStack(alignment: .center, spacing: 24) {
            TVChannelIcon(url: item.channel.icon, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.playerTitle(item))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(item.lineup.count > 1
                     ? "\(item.channel.name) · \(position) of \(item.lineup.count) · Swipe up or down to switch"
                     : item.channel.name)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.soft)
            }
            .lineLimit(1)
            Spacer()
            if !controller.resolution.isEmpty {
                TVBadge(text: controller.resolution)
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 44)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
