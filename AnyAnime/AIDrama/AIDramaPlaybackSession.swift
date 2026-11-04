import AVFoundation
import Combine
import UIKit

/// One owner for resolution, native playback and progress. A warm neighbor stays silent
/// and cannot acquire the audio session, PiP or viewing history until promoted.
@MainActor
final class AIDramaPlaybackSession: ObservableObject {
    let playlist: AIDramaPlaylist
    private let provider: AIDramaProviding
    private let mediaCache: AIDramaMediaCache
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
    private(set) var preloading: Bool

    private var generation = UUID()
    private var resolution: Task<Void, Never>?
    private var observations = Set<AnyCancellable>()
    private var activityObservations = Set<AnyCancellable>()
    private var backgroundTransition: Task<Void, Never>?
    private var presented = false
    private var sceneActive = false
    private var applicationInBackground = false
    private var sceneInBackground = false
    private var transitionGeneration: UUID?
    private var completedEpisode = false
    private var attached = false
    private var pendingResume: Double?
    private var resumeSeekRequestedAt: Date?
    private var positions: [String: Double]
    private var lastSavedTime = 0.0
    private var currentStream: AIDramaStream?
    private var streamResolvedAt = Date.distantPast
    private var pendingViewport: CGSize?
    private var previousIdleTimer: Bool?
    private var ownsAudioSession = false
    private let defaults: UserDefaults

    #if DEBUG
    private(set) var cancelledResolutions = 0
    private(set) var playerCreations = 0
    private(set) var maximumOwnedPlayers = 0
    @Published private(set) var debugInlinePiPCommands = 0
    private var promotionStartedAt: TimeInterval?
    private(set) var lastPromotionToPlaybackSeconds: Double?
    var debugSceneActive: Bool { sceneActive }
    var debugSceneInBackground: Bool { sceneInBackground }
    var debugBackgroundTransitionPending: Bool { backgroundTransition != nil }
    func debugSimulateInlinePiPCommand(playing: Bool) {
        guard controller?.debugSimulateArmedPiPPlaybackCommand(playing: playing) == true else { return }
        debugInlinePiPCommands += 1
    }
    #endif

    init(playlist: AIDramaPlaylist, provider: AIDramaProviding, initialEpisodeID: String? = nil,
         defaults: UserDefaults = .standard, preloading: Bool = false) {
        self.playlist = playlist
        let cache = (provider as? AIDramaMediaCache) ?? AIDramaMediaCache(provider: provider)
        self.provider = cache; self.mediaCache = cache
        self.defaults = defaults
        self.preloading = preloading
        positions = defaults.dictionary(forKey: "AnPinime.AIDrama.positions." + playlist.series.id) as? [String: Double] ?? [:]
        let storedSelection = defaults.string(forKey: "AnPinime.AIDrama.selected." + playlist.series.id)
        manuallyPaused = (initialEpisodeID == nil || initialEpisodeID == storedSelection)
            && defaults.bool(forKey: "AnPinime.AIDrama.paused." + playlist.series.id)
        let requested = initialEpisodeID ?? storedSelection
        selectedEpisodeID = playlist.episodes.first(where: { $0.id == requested })?.id ?? playlist.episodes.first?.id
        applicationInBackground = UIApplication.shared.applicationState == .background
        sceneInBackground = applicationInBackground
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard UIApplication.shared.applicationState == .background else { return }
                    self?.applicationInBackground = true
                    self?.setSceneActive(false)
                }
            }.store(in: &activityObservations)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applicationInBackground = false
                    self?.setSceneActive(false)
                }
            }.store(in: &activityObservations)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.setSceneActive(true) }
            }.store(in: &activityObservations)
    }

    var selectedIndex: Int? { playlist.episodes.firstIndex { $0.id == selectedEpisodeID } }
    var selectedEpisode: AIDramaEpisode? { selectedIndex.map { playlist.episodes[$0] } }
    private var pictureInPictureOwnsPlayback: Bool { playback?.pictureInPictureActive == true || playback?.pictureInPicturePending == true }
    private var mayPlay: Bool { !preloading && presented && (!sceneInBackground || pictureInPictureOwnsPlayback) && !transitioning && (attached || pictureInPictureOwnsPlayback) && !manuallyPaused }
    private var mayResolve: Bool { presented && sceneActive && !transitioning }

    func setPresented(_ value: Bool, sceneActive: Bool) {
        presented = value
        self.sceneActive = sceneActive
        if sceneActive { applicationInBackground = false }
        sceneInBackground = !sceneActive && applicationInBackground
        if !value || !sceneInBackground { backgroundTransition?.cancel(); backgroundTransition = nil }
        if !value || !sceneActive {
            transitioning = false; transitionGeneration = nil
            if playlist.episodes.count > 1 { Task { await mediaCache.stop() } }
        }
        if value, sceneInBackground { scheduleBackgroundReconciliation() }
        else { reconcile() }
    }

    func setSceneActive(_ value: Bool) {
        sceneActive = value
        if value { applicationInBackground = false }
        // SwiftUI's .inactive/.background update can precede UIKit's background
        // notification. Only the notification may authorize background teardown.
        sceneInBackground = !value && applicationInBackground
        if !sceneInBackground { backgroundTransition?.cancel(); backgroundTransition = nil }
        if !value {
            transitioning = false; transitionGeneration = nil
            if playlist.episodes.count > 1 { Task { await mediaCache.stop() } }
        }
        if sceneInBackground { scheduleBackgroundReconciliation() }
        else {
            reconcile()
            if value, playback?.loading == false { preparePlaylistWindow() }
        }
    }

    private func scheduleBackgroundReconciliation() {
        guard backgroundTransition == nil else { return }
        backgroundTransition = Task { @MainActor [weak self] in
            // MPV owns the AVKit transition. Let all didEnterBackground observers
            // mark a pending PiP before deciding whether its decoder may be released.
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.backgroundTransition = nil
            guard self.sceneInBackground, !self.sceneActive else { return }
            self.reconcile()
        }
    }

    func promotePreloadedVideo() {
        guard preloading else { return }
        #if DEBUG
        promotionStartedAt = ProcessInfo.processInfo.systemUptime
        lastPromotionToPlaybackSeconds = nil
        #endif
        preloading = false
        manuallyPaused = false
        // A recommendation always starts at its first frame; warming never writes progress.
        controller?.finishPreloading()
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
        guard controller === player else { player.perform("pause", value: 0); return }
        // Inline containment can change while AVKit owns the same decoder.
        // Detaching that surface must not stop the PiP movie or change pause intent.
        if !pictureInPictureOwnsPlayback { player.perform("pause", value: 0) }
        attached = false
        // Representable dismantling must not publish into SwiftUI's closing graph.
        savePosition(recordHistory: false)
    }

    private func reconcile() {
        if presented, !sceneActive, !sceneInBackground {
            // .inactive also means Control Center, a system sheet or an orientation
            // transition. Retain the current owner and playback intent; starting or
            // pausing PiP here races AVKit's actual background transition.
            cancelResolution()
            savePosition()
            applyPlaybackIntent()
            return
        }
        guard mayResolve else {
            if presented, pictureInPictureOwnsPlayback {
                savePosition(); applyPlaybackIntent(); return
            }
            invalidateCurrent()
            releaseActivity()
            return
        }
        if !preloading { acquireActivity() }
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

    private func rebuildForViewport(_ size: CGSize) {
        guard !preloading, presented, sceneActive, !transitioning, !pictureInPictureOwnsPlayback,
              let episode = selectedEpisode, let stream = currentStream else { return }
        let resolvedAt = streamResolvedAt
        let fresh = Date().timeIntervalSince(resolvedAt) < 45
        pendingViewport = size
        #if DEBUG
        let promotionStart = promotionStartedAt
        let promotionLatency = lastPromotionToPlaybackSeconds
        #endif
        invalidateCurrent()
        #if DEBUG
        // A fresh rendering surface is still part of the same committed promotion.
        // Include its cost in the metric rather than losing the pending measurement.
        promotionStartedAt = promotionStart
        lastPromotionToPlaybackSeconds = promotionLatency
        #endif
        if fresh {
            install(stream, episode: episode, token: generation)
            streamResolvedAt = resolvedAt
        } else { error = nil; reconcile() }
    }

    private func preparePlaylistWindow() {
        guard !preloading, presented, sceneActive, playlist.episodes.count > 1, let index = selectedIndex else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ai-disable-prefetch") { return }
        #endif
        let count = defaults.integer(forKey: "AnPinime.AIDrama.preloadCount") == 10 ? 10 : 5
        let next = Array(playlist.episodes.dropFirst(index + 1).prefix(count))
        let previous = Array(playlist.episodes.prefix(index).suffix(3))
        let current = selectedEpisodeID
        Task { await mediaCache.prepare(next: next, previous: previous, current: current) }
    }

    private func install(_ stream: AIDramaStream, episode: AIDramaEpisode, token: UUID) {
        currentStream = stream
        streamResolvedAt = Date()
        // A new state prevents old EOF counts, callbacks and timers crossing episode boundaries.
        let state = PlaybackState()
        let rememberSpeed = defaults.object(forKey: "AnPinime.rememberSpeed") as? Bool ?? true
        let rate = rememberSpeed ? (defaults.object(forKey: "AnPinime.playbackRate") as? Double ?? 1) : 1
        state.rate = rate.isFinite ? min(3, max(0.25, rate)) : 1
        state.userPaused = true
        let player = MPVPlaybackController(url: stream.url, headers: stream.headers, playback: state, preloading: preloading, resizesEmbeddedSurface: true, initialViewport: pendingViewport)
        pendingViewport = nil
        player.onViewportChange = { [weak self, weak player] size in
            guard let self, self.generation == token, self.controller === player else { return }
            self.rebuildForViewport(size)
        }
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
        state.chooseOption = { [weak self, weak player] kind, id in
            guard let self, self.generation == token, self.controller === player else { return }
            player?.choose(kind, id: id)
        }
        state.importSubtitle = { [weak self, weak player] url, slot in
            guard let self, self.generation == token, self.controller === player else { return }
            player?.addSubtitle(url, slot: slot)
        }
        pendingResume = preloading ? nil : positions[episode.id].flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
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
        state.$loading.removeDuplicates().sink { [weak self] loading in
            guard !loading else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.preparePlaylistWindow()
            }
        }.store(in: &observations)
        Publishers.CombineLatest(state.$pictureInPictureActive, state.$pictureInPicturePending)
            .dropFirst().sink { [weak self] active, pending in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                // A failed start can clear pending without ever becoming active.
                // Release that owner in background too, rather than leaving audio
                // or a renderer alive indefinitely after the system rejected PiP.
                if !active, !pending, self.sceneInBackground { self.reconcile() }
            }
        }.store(in: &observations)
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
        state.$currentTime.sink { [weak self, weak state] time in
            guard let self, self.generation == token, self.selectedEpisodeID == episode.id else { return }
            #if DEBUG
            if let started = self.promotionStartedAt, !self.preloading, self.presented,
               !self.manuallyPaused, !self.transitioning, state?.playing == true, time > 0.1 {
                self.lastPromotionToPlaybackSeconds = ProcessInfo.processInfo.systemUptime - started
                self.promotionStartedAt = nil
            }
            #endif
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
                guard !self.preloading else { return }
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
        if !(defaults.object(forKey: "AnPinime.autoNext") as? Bool ?? true) {
            setPaused(true)
        } else if playlist.episodes.indices.contains(index + 1) {
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
        #if DEBUG
        promotionStartedAt = nil
        lastPromotionToPlaybackSeconds = nil
        #endif
        currentStream = nil
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
        controller?.onViewportChange = nil
        controller?.shutdown()
        #if DEBUG
        if AIDramaDebugSupport.enabled, let player = controller { AIDramaDebugSupport.shared.stopped(player) }
        #endif
        controller = nil
        teardownPlayer = nil
        attached = false
    }

    private func savePosition(time: Double? = nil, recordHistory: Bool = true) {
        guard !preloading else { return }
        guard let id = selectedEpisodeID, let state = playback else { return }
        if let target = pendingResume {
            // Teardown can happen between issuing a seek and MPV's confirming poll.
            positions[id] = target
            lastSavedTime = target
            persistPositions()
            if recordHistory, let episode = selectedEpisode, state.currentTime > 0 {
                AIDramaHistoryStore.shared.record(series: playlist.series, episode: episode,
                                                  position: target, duration: state.duration)
            }
            return
        }
        let position = time ?? state.currentTime
        guard position.isFinite, position > 0 else { return }
        // Completed episodes start again instead of reopening on a final frame.
        positions[id] = state.duration > 0 && position >= state.duration - 1 ? 0 : position
        lastSavedTime = position
        persistPositions()
        if recordHistory, let episode = selectedEpisode {
            AIDramaHistoryStore.shared.record(series: playlist.series, episode: episode,
                                              position: position, duration: state.duration)
        }
    }

    private func persistPositions() {
        defaults.set(positions, forKey: "AnPinime.AIDrama.positions." + playlist.series.id)
        defaults.set(selectedEpisodeID, forKey: "AnPinime.AIDrama.selected." + playlist.series.id)
    }

    private func persistPauseIntent() {
        guard !preloading else { return }
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
        backgroundTransition?.cancel()
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
