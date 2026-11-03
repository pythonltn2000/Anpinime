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
            "subtitleTrack": session.playback?.subtitleTrack ?? "",
            "currentTime": time, "mediaInfo": info, "ownedPlayers": session.controller == nil ? 0 : 1,
            "maximumOwnedPlayers": session.maximumOwnedPlayers,
            "playerCreations": session.playerCreations, "cancelledResolutions": session.cancelledResolutions
        ]
        let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
        let value = String(decoding: data, as: UTF8.self)
        return AIDramaDebugLabel(identifier: "aidrama.debug.state", value: value)
            .frame(width: 32, height: 20).padding(.top, 80).padding(.leading, 8)
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
    var body: some View {
        AIDramaDebugStateView(session: session).snapshot(time: playback.currentTime, info: playback.mediaInfo)
    }
}
#endif
