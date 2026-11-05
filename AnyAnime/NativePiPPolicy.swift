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

    static func canAcknowledgeRestore(ownerAlive: Bool, applicationForeground: Bool,
                                      sceneForeground: Bool, sourceAttached: Bool, layoutReady: Bool) -> Bool {
        ownerAlive && applicationForeground && sceneForeground && sourceAttached && layoutReady
    }
}

/// One AVKit restore request owns one completion. Consume it before invoking
/// external code, which can synchronously request restoration again.
struct NativePiPRestoreHandshake {
    private(set) var pendingID: UInt64?
    private var sequence: UInt64 = 0

    mutating func begin() -> UInt64 {
        sequence &+= 1
        pendingID = sequence
        return sequence
    }

    mutating func consume(_ requestID: UInt64) -> Bool {
        guard pendingID == requestID else { return false }
        pendingID = nil
        return true
    }
}

/// The render queue must keep ownership until the main queue has consumed the
/// buffer. A serial render queue alone cannot bound queued main-thread work.
final class NativePiPFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !pending else { return false }
        pending = true
        return true
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        pending = false
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
