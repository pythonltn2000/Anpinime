import AVFoundation
import Combine
import UIKit

/// One owner for resolution, native playback and progress. Pager neighbors never own players.
@MainActor
final class AIDramaPlaybackSession: ObservableObject {
    let playlist: AIDramaPlaylist
    private let provider: AIDramaProviding
    @Published private(set) var selectedEpisodeID: String?
    @Published private(set) var controller: MPVPlaybackController?
    // A direct stored reference remains readable during nonisolated deinit;
    // the @Published controller accessor requires the main actor.
    private var teardownPlayer: MPVPlaybackController?
    @Published private(set) var playback: PlaybackState?
    @Published private(set) var resolving = false
    @Published private(set) var error: String?
    @Published private(set) var manuallyPaused: Bool
    @Published private(set) var transitioning = false

    private var generation = UUID()
    private var resolution: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private var presented = false
    private var sceneActive = false
    private var transitionGeneration: UUID?
    private var completedEpisode = false
    private var attached = false
    private var pendingResume: Double?
    private var resumeSeekRequestedAt: Date?
    private var positions: [String: Double]
    private var lastSavedTime = 0.0
    private var previousIdleTimer: Bool?
    private var ownsAudioSession = false
    private let defaults: UserDefaults

    #if DEBUG
    private(set) var cancelledResolutions = 0
    private(set) var playerCreations = 0
    private(set) var maximumOwnedPlayers = 0
    #endif

    init(playlist: AIDramaPlaylist, provider: AIDramaProviding, initialEpisodeID: String? = nil,
         defaults: UserDefaults = .standard) {
        self.playlist = playlist
        self.provider = provider
        self.defaults = defaults
        positions = defaults.dictionary(forKey: "AnPinime.AIDrama.positions." + playlist.series.id) as? [String: Double] ?? [:]
        let storedSelection = defaults.string(forKey: "AnPinime.AIDrama.selected." + playlist.series.id)
        manuallyPaused = (initialEpisodeID == nil || initialEpisodeID == storedSelection)
            && defaults.bool(forKey: "AnPinime.AIDrama.paused." + playlist.series.id)
        let requested = initialEpisodeID ?? storedSelection
        selectedEpisodeID = playlist.episodes.first(where: { $0.id == requested })?.id ?? playlist.episodes.first?.id
    }

    var selectedIndex: Int? { playlist.episodes.firstIndex { $0.id == selectedEpisodeID } }
    var selectedEpisode: AIDramaEpisode? { selectedIndex.map { playlist.episodes[$0] } }
    private var mayPlay: Bool { presented && sceneActive && !transitioning && attached && !manuallyPaused }
    private var mayResolve: Bool { presented && sceneActive && !transitioning }

    func setPresented(_ value: Bool, sceneActive: Bool) {
        presented = value
        self.sceneActive = sceneActive
        if !value || !sceneActive { transitioning = false; transitionGeneration = nil }
        reconcile()
    }

    func setSceneActive(_ value: Bool) {
        sceneActive = value
        if !value { transitioning = false; transitionGeneration = nil }
        reconcile()
    }

    /// A gesture has not selected its neighboring page yet. Retain the paused current frame
    /// so a canceled gesture can restore it without a second player or a fresh signed URL.
    func beginPageTransition() {
        guard presented, sceneActive else { return }
        transitionGeneration = generation
        transitioning = true
        cancelResolution()
        savePosition()
        controller?.perform("pause", value: 0)
    }

    func finishPageTransition(episodeID: String?, completed: Bool) {
        let valid = transitionGeneration == generation
        transitionGeneration = nil
        transitioning = false
        guard valid else { reconcile(); return }
        if completed, let episodeID, episodeID != selectedEpisodeID {
            selectEpisode(episodeID)
        } else {
            reconcile()
        }
    }

    func selectEpisode(_ id: String) {
        guard playlist.episodes.contains(where: { $0.id == id }) else { return }
        transitioning = false
        transitionGeneration = nil
        guard id != selectedEpisodeID else { reconcile(); return }
        invalidateCurrent()
        selectedEpisodeID = id
        defaults.set(id, forKey: "AnPinime.AIDrama.selected." + playlist.series.id)
        manuallyPaused = false
        persistPauseIntent()
        error = nil
        reconcile()
    }

    func togglePause() { setPaused(!manuallyPaused) }

    func setPaused(_ paused: Bool) {
        manuallyPaused = paused
        playback?.userPaused = paused
        persistPauseIntent()
        if !paused, completedEpisode { retry(); return }
        applyPlaybackIntent()
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, let playback, playback.duration > 0 else { return }
        let target = min(max(0, seconds), playback.duration)
        // A user's seek replaces any startup resume, including a queued duration callback.
        pendingResume = target
        resumeSeekRequestedAt = Date()
        controller?.perform("seek", value: target)
        savePosition()
    }

    func retry() {
        invalidateCurrent()
        error = nil
        reconcile()
    }

    func didAttach(_ player: MPVPlaybackController) {
        guard controller === player else { player.perform("pause", value: 0); player.shutdown(); return }
        attached = true
        applyPlaybackIntent()
    }

    func didDetach(_ player: MPVPlaybackController) {
        player.perform("pause", value: 0)
        guard controller === player else { return }
        attached = false
        savePosition()
    }

    private func reconcile() {
        guard mayResolve else {
            invalidateCurrent()
            releaseActivity()
            return
        }
        acquireActivity()
        if advanceCompletedEpisode() { return }
        guard controller == nil else { applyPlaybackIntent(); return }
        guard resolution == nil, error == nil else { return }
        guard let episode = selectedEpisode else { error = "Bộ phim chưa có tập để phát."; return }
        guard !episode.isLocked else { error = AIDramaError.lockedEpisode.localizedDescription; return }
        let token = generation
        resolving = true
        resolution = Task { [weak self, provider] in
            do {
                let stream = try await provider.resolve(episode)
                try Task.checkCancellation()
                guard let self, self.generation == token, self.selectedEpisodeID == episode.id,
                      self.mayResolve else { return }
                self.resolution = nil
                self.resolving = false
                self.install(stream, episode: episode, token: token)
            } catch {
                guard !Task.isCancelled, let self, self.generation == token,
                      self.selectedEpisodeID == episode.id, self.mayResolve else { return }
                self.resolution = nil
                self.resolving = false
                self.error = error.localizedDescription
            }
        }
    }

    private func install(_ stream: AIDramaStream, episode: AIDramaEpisode, token: UUID) {
        // A new state prevents old EOF counts, callbacks and timers crossing episode boundaries.
        let state = PlaybackState()
        state.userPaused = true
        let player = MPVPlaybackController(url: stream.url, headers: stream.headers, playback: state)
        player.onFailure = { [weak self] message in
            // mpv can report failure while its polling loop still holds the native handle.
            // Leave that stack before teardown, and recheck ownership after the hop.
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.selectedEpisodeID == episode.id else { return }
                self.error = message
                self.stopController()
            }
        }
        state.command = { [weak self, weak player] command, value in
            guard let self, self.generation == token, self.controller === player else { return }
            switch command {
            case "play": self.setPaused(false)
            case "pause": self.setPaused(true)
            case "seek": self.seek(value)
            default: player?.perform(command, value: value)
            }
        }
        pendingResume = positions[episode.id].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        resumeSeekRequestedAt = nil
        lastSavedTime = pendingResume ?? 0
        playback = state
        attached = false
        controller = player
        teardownPlayer = player
        #if DEBUG
        playerCreations += 1
        if AIDramaDebugSupport.enabled { AIDramaDebugSupport.shared.installed(player) }
        // Logical session ownership only; asynchronous native teardown is not counted.
        maximumOwnedPlayers = max(maximumOwnedPlayers, controller == nil ? 0 : 1)
        #endif
        state.$duration.sink { [weak self, weak state, weak player] duration in
            guard duration > 0, self?.pendingResume != nil else { return }
            // @Published emits before assignment; MPV's seek clamps to state.duration.
            Task { @MainActor [weak self, weak state, weak player] in
                guard let self, let state, let player, self.generation == token,
                      self.controller === player, state.duration > 0, let saved = self.pendingResume,
                      self.resumeSeekRequestedAt == nil else { return }
                let target = saved < state.duration - 1 ? saved : 0
                self.pendingResume = target
                self.resumeSeekRequestedAt = Date()
                player.perform("seek", value: target)
                state.userPaused = self.manuallyPaused
            }
        }.store(in: &observations)
        state.$currentTime.sink { [weak self] time in
            guard let self, self.generation == token, self.selectedEpisodeID == episode.id else { return }
            if let target = self.pendingResume {
                guard let requestedAt = self.resumeSeekRequestedAt else { return }
                // Do not persist startup frames while the asynchronous seek is pending.
                // Allow playback to advance if the main actor delayed the confirming poll.
                let forwardTolerance = max(1, Date().timeIntervalSince(requestedAt) + 0.5)
                guard time >= target - 1, time <= target + forwardTolerance else { return }
                self.pendingResume = nil
                self.resumeSeekRequestedAt = nil
            }
            guard abs(time - self.lastSavedTime) >= 5 else { return }
            self.savePosition(time: time)
        }.store(in: &observations)
        state.$endCount.dropFirst().sink { [weak self] count in
            guard count > 0 else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.selectedEpisodeID == episode.id,
                      self.controller != nil else { return }
                self.completedEpisode = true
                self.pendingResume = nil
                self.resumeSeekRequestedAt = nil
                self.positions[episode.id] = 0
                self.persistPositions()
                _ = self.advanceCompletedEpisode()
            }
        }.store(in: &observations)
    }

    private func applyPlaybackIntent() {
        controller?.perform(mayPlay ? "play" : "pause", value: 0)
        playback?.userPaused = manuallyPaused
    }

    @discardableResult
    private func advanceCompletedEpisode() -> Bool {
        guard completedEpisode, mayResolve, !manuallyPaused, let index = selectedIndex else { return false }
        if playlist.episodes.indices.contains(index + 1) {
            selectEpisode(playlist.episodes[index + 1].id)
        } else {
            setPaused(true)
        }
        return true
    }

    private func cancelResolution() {
        if resolution != nil {
            #if DEBUG
            cancelledResolutions += 1
            #endif
            resolution?.cancel()
            resolution = nil
        }
        resolving = false
    }

    private func invalidateCurrent() {
        generation = UUID()
        cancelResolution()
        savePosition()
        stopController()
        playback = nil
        pendingResume = nil
        resumeSeekRequestedAt = nil
        completedEpisode = false
    }

    private func stopController() {
        observations.removeAll()
        playback?.command = nil
        playback?.chooseOption = nil
        playback?.importSubtitle = nil
        // mpv destruction runs off the main actor; silence the old player before a successor exists.
        controller?.perform("pause", value: 0)
        controller?.perform("volume", value: 0)
        controller?.onFailure = nil
        controller?.shutdown()
        #if DEBUG
        if AIDramaDebugSupport.enabled, let player = controller { AIDramaDebugSupport.shared.stopped(player) }
        #endif
        controller = nil
        teardownPlayer = nil
        attached = false
    }

    private func savePosition(time: Double? = nil) {
        guard let id = selectedEpisodeID, let state = playback else { return }
        if let target = pendingResume {
            // Teardown can happen between issuing a seek and MPV's confirming poll.
            positions[id] = target
            lastSavedTime = target
            persistPositions()
            return
        }
        let position = time ?? state.currentTime
        guard position.isFinite, position > 0 else { return }
        // Completed episodes start again instead of reopening on a final frame.
        positions[id] = state.duration > 0 && position >= state.duration - 1 ? 0 : position
        lastSavedTime = position
        persistPositions()
    }

    private func persistPositions() {
        defaults.set(positions, forKey: "AnPinime.AIDrama.positions." + playlist.series.id)
        defaults.set(selectedEpisodeID, forKey: "AnPinime.AIDrama.selected." + playlist.series.id)
    }

    private func persistPauseIntent() {
        defaults.set(manuallyPaused, forKey: "AnPinime.AIDrama.paused." + playlist.series.id)
    }

    private func acquireActivity() {
        if previousIdleTimer == nil {
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        guard !ownsAudioSession else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        ownsAudioSession = true
    }

    private func releaseActivity() {
        if let previousIdleTimer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimer }
        previousIdleTimer = nil
        if ownsAudioSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        ownsAudioSession = false
    }

    deinit {
        resolution?.cancel()
        let player = teardownPlayer
        let idleTimer = previousIdleTimer
        let audioActive = ownsAudioSession
        Task { @MainActor in
            player?.perform("pause", value: 0)
            player?.perform("volume", value: 0)
            player?.shutdown()
            #if DEBUG
            if AIDramaDebugSupport.enabled, let player { AIDramaDebugSupport.shared.stopped(player) }
            #endif
            if let idleTimer { UIApplication.shared.isIdleTimerDisabled = idleTimer }
            if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }
}
