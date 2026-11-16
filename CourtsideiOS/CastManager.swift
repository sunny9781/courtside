import SwiftUI
import UIKit
import GoogleCast

/// Chromecast, through Google's Cast toolkit and its standard media receiver. When a Chromecast is connected,
/// streams play on the TV (using the provider's HLS version of the channel) instead of on the phone.
@MainActor
final class CastManager: NSObject, ObservableObject, GCKSessionManagerListener {
    static let shared = CastManager()

    /// The Chromecast's name while connected.
    @Published private(set) var deviceName: String?
    /// What's on the Chromecast right now.
    @Published private(set) var castingTitle: String?

    /// Whether Google's Cast toolkit was started this time (it isn't after it crashed the app while starting).
    private(set) static var isSetUp = false
    /// Saved while the Cast toolkit starts: still there at the next launch means it crashed the app.
    static let startingKey = "castStarting"
    /// Cast was switched off after it crashed the app while starting (Settings can switch it back on).
    static let disabledKey = "castDisabled"
    /// The build that was running when Cast was switched off.
    static let disabledBuildKey = "castDisabledBuild"

    /// Starts Cast once the app has finished launching (Google's recommended moment). If starting it crashed the app
    /// last time, it stays off so the app still opens, and Settings says so.
    static func setUp() {
        let defaults = UserDefaults.standard
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if defaults.bool(forKey: startingKey) {
            defaults.set(false, forKey: startingKey)
            defaults.set(true, forKey: disabledKey)
            defaults.set(build, forKey: disabledBuildKey)
        } else if defaults.bool(forKey: disabledKey), defaults.string(forKey: disabledBuildKey) != build {
            // A new version may have fixed what crashed: try Cast again once.
            defaults.set(false, forKey: disabledKey)
        }
        guard !isSetUp, !defaults.bool(forKey: disabledKey) else { return }
        defaults.set(true, forKey: startingKey)
        defaults.synchronize()
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.startDiscoveryAfterFirstTapOnCastButton = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(shared)
        isSetUp = true
        // Discovery and resuming a session happen in the first seconds: still running after 10, Cast is fine.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            UserDefaults.standard.set(false, forKey: startingKey)
        }
    }

    /// Settings › Playback: switch Cast back on after it was turned off (takes effect next launch).
    static func enableAgain() {
        UserDefaults.standard.set(false, forKey: disabledKey)
    }

    var isCasting: Bool { deviceName != nil }

    func cast(_ url: URL, title: String, subtitle: String) {
        guard Self.isSetUp, let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else { return }
        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle)
        let info = GCKMediaInformationBuilder(contentURL: url)
        info.streamType = .live
        info.contentType = "application/x-mpegURL"
        info.metadata = metadata
        let request = GCKMediaLoadRequestDataBuilder()
        request.mediaInformation = info.build()
        request.autoplay = true
        client.loadMedia(with: request.build())
        castingTitle = title
    }

    func disconnect() {
        guard Self.isSetUp else { return }
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        let name = session.device.friendlyName ?? "Chromecast"
        Task { @MainActor in self.deviceName = name }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        let name = session.device.friendlyName ?? "Chromecast"
        Task { @MainActor in self.deviceName = name }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        Task { @MainActor in
            self.deviceName = nil
            self.castingTitle = nil
        }
    }
}

/// Google's Cast button (shows only when a Chromecast is on the network, and only when Cast started).
struct CastButton: View {
    var body: some View {
        if CastManager.isSetUp { GoogleCastButton() }
    }
}

private struct GoogleCastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        button.tintColor = .white
        return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
