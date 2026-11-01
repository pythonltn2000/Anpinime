#if DEBUG
import SwiftUI

/// Instrumentation exists only in explicit simulator checks, never the release UI.
@MainActor
final class AIDramaDebugSupport: ObservableObject {
    static let shared = AIDramaDebugSupport()
    static var fixtureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ai-drama-smoke") }
    static var enabled: Bool { fixtureEnabled || ProcessInfo.processInfo.arguments.contains("--ai-drama-live-smoke") }
    @Published var ownedPlayers = 0
    private var activeControllers = Set<ObjectIdentifier>()

    func installed(_ controller: MPVPlaybackController) {
        activeControllers.insert(ObjectIdentifier(controller))
        ownedPlayers = activeControllers.count
    }

    func stopped(_ controller: MPVPlaybackController) {
        activeControllers.remove(ObjectIdentifier(controller))
        ownedPlayers = activeControllers.count
    }

    static func clearFixtureProgress() {
        let seriesID = "7000000000000000001"
        for part in ["positions", "selected", "paused"] {
            UserDefaults.standard.removeObject(forKey: "AnPinime.AIDrama." + part + "." + seriesID)
        }
    }
}

@MainActor
struct AIDramaDebugOwnerView: View {
    @ObservedObject private var support = AIDramaDebugSupport.shared
    var body: some View {
        Text(String(support.ownedPlayers))
            .font(.system(size: 1)).foregroundColor(.white.opacity(0.01))
            .frame(width: 2, height: 2).allowsHitTesting(false)
            .accessibilityIdentifier("aidrama.debug.ownedPlayers")
            .accessibilityValue(String(support.ownedPlayers))
    }
}

@MainActor
struct AIDramaDebugStateView: View {
    @ObservedObject var session: AIDramaPlaybackSession
    var body: some View {
        Group {
            if let playback = session.playback {
                AIDramaDebugPlaybackState(session: session, playback: playback)
            } else {
                snapshot(time: 0, info: "")
            }
        }
    }

    fileprivate func snapshot(time: Double, info: String) -> some View {
        let fields: [String: Any] = [
            "selectedEpisodeID": session.selectedEpisodeID as Any? ?? NSNull(),
            "resolving": session.resolving, "manuallyPaused": session.manuallyPaused,
            "currentTime": time, "mediaInfo": info, "ownedPlayers": session.controller == nil ? 0 : 1,
            "maximumOwnedPlayers": session.maximumOwnedPlayers,
            "playerCreations": session.playerCreations, "cancelledResolutions": session.cancelledResolutions
        ]
        let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
        let value = String(decoding: data, as: UTF8.self)
        return Text("Trạng thái kiểm thử")
            .font(.system(size: 1)).foregroundColor(.white.opacity(0.01))
            .frame(width: 2, height: 2).allowsHitTesting(false)
            .accessibilityIdentifier("aidrama.debug.state")
            .accessibilityValue(value)
    }
}

@MainActor
private struct AIDramaDebugPlaybackState: View {
    @ObservedObject var session: AIDramaPlaybackSession
    @ObservedObject var playback: PlaybackState
    var body: some View {
        AIDramaDebugStateView(session: session).snapshot(time: playback.currentTime, info: playback.mediaInfo)
    }
}
#endif
