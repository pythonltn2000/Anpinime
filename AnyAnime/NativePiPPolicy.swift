import Foundation

/// State gates shared by the native bridge and controller. These describe app
/// readiness; only AVKit can report whether a system PiP window starts.
enum NativePiPPolicy {
    static func automaticAllowed(preference: Bool, eligible: Bool, playing: Bool,
                                 frameReady: Bool, outputPrimed: Bool, sourceAttached: Bool) -> Bool {
        preference && eligible && playing && frameReady && outputPrimed && sourceAttached
    }

    static func shouldStopOnForeground(returnedFromBackground: Bool, transitioningOrActive: Bool) -> Bool {
        returnedFromBackground || transitioningOrActive
    }

    static func acceptsControls(stopped: Bool, stopping: Bool,
                                sourceMatchesController: Bool, sourceIsActive: Bool) -> Bool {
        !stopped && !stopping && sourceMatchesController && sourceIsActive
    }
}

/// A missing decoder frame may recover later in the same playback session.
/// Limit each unsuccessful burst, then retry after a cooldown; never exhaust a
/// lifetime attempt counter. The caller owns request IDs and asynchronous reply
/// timeouts, and completes expired requests before submitting a replacement.
struct NativePiPSnapshotRetry {
    private(set) var pending = false
    private(set) var frameReady = false
    private(set) var attemptsInBurst = 0
    private(set) var nextAttemptAt: TimeInterval = 0
    private(set) var totalAttempts = 0

    mutating func beginAttempt(now: TimeInterval, eligible: Bool) -> Bool {
        guard eligible, !pending, !frameReady, now >= nextAttemptAt else { return false }
        pending = true
        attemptsInBurst += 1
        totalAttempts += 1
        return true
    }

    mutating func completeAttempt(frameReady: Bool, now: TimeInterval) {
        guard pending else { return }
        pending = false
        self.frameReady = frameReady
        if frameReady { return }
        if attemptsInBurst >= 3 {
            attemptsInBurst = 0
            nextAttemptAt = now + 2
        }
    }
}
