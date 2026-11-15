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

    static func setUp() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(shared)
    }

    var isCasting: Bool { deviceName != nil }

    func cast(_ url: URL, title: String, subtitle: String) {
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else { return }
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

/// Google's Cast button (shows only when a Chromecast is on the network).
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 28, height: 28))
        button.tintColor = .white
        return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
