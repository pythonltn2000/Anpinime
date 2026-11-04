#if DEBUG
import SwiftUI
import UIKit

/// Instrumentation exists only in explicit simulator checks, never the release UI.
@MainActor
final class AIDramaDebugSupport: ObservableObject {
    static let shared = AIDramaDebugSupport()
    static var fixtureEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ai-drama-smoke") }
    static var enabled: Bool { fixtureEnabled || ProcessInfo.processInfo.arguments.contains("--ai-drama-live-smoke") }
    @Published var ownedPlayers = 0
    private var activeControllers = Set<ObjectIdentifier>()
    private static var preparedSeries = Set<String>()

    func installed(_ controller: MPVPlaybackController) {
        activeControllers.insert(ObjectIdentifier(controller))
        ownedPlayers = activeControllers.count
    }

    func stopped(_ controller: MPVPlaybackController) {
        activeControllers.remove(ObjectIdentifier(controller))
        ownedPlayers = activeControllers.count
    }

    static func clearFixtureProgress() {
        let firstPreparation = !preparedSeries.contains("7000000000000000001")
        clearProgress(seriesID: "7000000000000000001")
        if firstPreparation { AIDramaHistoryStore.shared.removeFixtureHistory() }
    }

    static func clearProgress(seriesID: String) {
        guard preparedSeries.insert(seriesID).inserted else { return }
        for part in ["positions", "selected", "paused"] {
            UserDefaults.standard.removeObject(forKey: "AnPinime.AIDrama." + part + "." + seriesID)
        }
    }
}

@MainActor
struct AIDramaDebugOwnerView: View {
    @ObservedObject private var support = AIDramaDebugSupport.shared
    var body: some View {
        AIDramaDebugLabel(identifier: "aidrama.debug.ownedPlayers", value: String(support.ownedPlayers))
            .frame(width: 32, height: 20).padding(.top, 70).padding(.leading, 8)
    }
}

@MainActor
struct AIDramaDebugStateView: View {
    @ObservedObject var session: AIDramaPlaybackSession
    var topInset: CGFloat = 160
    var body: some View {
        Group {
            if let playback = session.playback {
                AIDramaDebugPlaybackState(session: session, playback: playback, topInset: topInset)
            } else {
                snapshot(time: 0, info: "")
            }
        }
    }

    fileprivate func snapshot(time: Double, info: String) -> some View {
        let fields: [String: Any] = [
            "selectedEpisodeID": session.selectedEpisodeID as Any? ?? NSNull(),
            "resolving": session.resolving, "manuallyPaused": session.manuallyPaused,
            "subtitleTrack": session.playback?.subtitleTrack ?? "",
            "nativeGeometry": session.controller?.nativeGeometry ?? [:],
            "piPSupported": session.playback?.pictureInPictureSupported == true,
            "piPPrepared": session.controller?.piPPrepared == true,
            "piPPossible": session.controller?.piPPossible == true,
            "piPActive": session.playback?.pictureInPictureActive == true,
            "piPPending": session.playback?.pictureInPicturePending == true,
            "sceneActive": session.debugSceneActive,
            "sceneInBackground": session.debugSceneInBackground,
            "backgroundTransitionPending": session.debugBackgroundTransitionPending,
            "controllerIdentity": session.controller.map { String(describing: ObjectIdentifier($0)) } ?? "",
            "nativeVideoOutput": session.controller?.nativeGeometry["videoOutput"] as? String ?? "",
            "playing": session.playback?.playing == true,
            "lastPromotionToPlaybackSeconds": session.lastPromotionToPlaybackSeconds as Any? ?? NSNull(),
            "systemPiPStartCount": session.controller?.systemPiPStartCount ?? 0,
            "systemPiPStopCount": session.controller?.systemPiPStopCount ?? 0,
            "automaticPiPRequests": session.controller?.automaticPiPRequests ?? 0,
            "inlinePiPCommands": session.debugInlinePiPCommands,
            "currentTime": time, "mediaInfo": info, "ownedPlayers": session.controller == nil ? 0 : 1,
            "maximumOwnedPlayers": session.maximumOwnedPlayers,
            "playerCreations": session.playerCreations, "cancelledResolutions": session.cancelledResolutions
        ]
        let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
        let value = String(decoding: data, as: UTF8.self)
        return HStack(spacing: 4) {
            AIDramaDebugLabel(identifier: "aidrama.debug.state", value: value)
                .frame(width: 32, height: 20)
            Button("I") {
                NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
                session.setSceneActive(false)
            }.frame(width: 44, height: 44).contentShape(Rectangle())
                .accessibilityIdentifier("aidrama.debug.transientInactive")
            Button("A") {
                NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                session.setSceneActive(true)
            }.frame(width: 44, height: 44).contentShape(Rectangle())
                .accessibilityIdentifier("aidrama.debug.transientActive")
            Button("P") { session.debugSimulateInlinePiPCommand(playing: false) }
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .accessibilityIdentifier("aidrama.debug.inlinePiPPause")
            Button("R") { session.debugSimulateInlinePiPCommand(playing: true) }
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .accessibilityIdentifier("aidrama.debug.inlinePiPPlay")
        }.font(.system(size: 10)).foregroundColor(.white).buttonStyle(.plain)
            .padding(.top, topInset).padding(.leading, 8)
    }
}

@MainActor
private struct AIDramaDebugLabel: View {
    let identifier: String
    let value: String

    var body: some View {
        Button {} label: {
            Text("AI").font(.system(size: 10)).foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Kiểm thử phát")
        .accessibilityValue(value)
    }
}

@MainActor
private struct AIDramaDebugPlaybackState: View {
    @ObservedObject var session: AIDramaPlaybackSession
    @ObservedObject var playback: PlaybackState
    let topInset: CGFloat
    var body: some View {
        AIDramaDebugStateView(session: session, topInset: topInset).snapshot(time: playback.currentTime, info: playback.mediaInfo)
    }
}
#endif
