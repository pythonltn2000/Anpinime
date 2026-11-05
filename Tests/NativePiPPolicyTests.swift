import Foundation

/// Linux/macOS: swiftc AnyAnime/NativePiPPolicy.swift Tests/NativePiPPolicyTests.swift -o /tmp/native-pip-policy-tests
@main
struct NativePiPPolicyTests {
    private static var checks = 0

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError("FAIL: " + message) }
        checks += 1
        print("PASS: " + message)
    }

    static func main() {
        verifyReadiness()
        verifyRetryRecovery()
        verifyInterruptedRequest()
        verifyForegroundAndControls()
        print("\(checks) native PiP policy checks passed")
    }

    private static func verifyReadiness() {
        // Exercise every combination so that a missing single gate cannot allow
        // auto entry, including a prepared controller with no enqueued frame.
        var enabledCombinations = 0
        for bits in 0..<64 {
            let enabled = NativePiPPolicy.automaticAllowed(
                preference: bits & 1 != 0, eligible: bits & 2 != 0,
                playing: bits & 4 != 0, frameReady: bits & 8 != 0,
                outputPrimed: bits & 16 != 0, sourceAttached: bits & 32 != 0)
            guard enabled == (bits == 63) else {
                fatalError("FAIL: readiness combination \(bits) bypassed a gate")
            }
            if enabled { enabledCombinations += 1 }
        }
        require(enabledCombinations == 1, "all six actual-readiness gates are required across 64 combinations")
        require(!NativePiPPolicy.automaticAllowed(preference: true, eligible: true, playing: false,
            frameReady: true, outputPrimed: true, sourceAttached: true), "buffering or paused playback disarms automatic entry")
        require(!NativePiPPolicy.automaticAllowed(preference: true, eligible: true, playing: true,
            frameReady: true, outputPrimed: true, sourceAttached: false), "detaching the real source view disarms automatic entry")
    }

    private static func verifyRetryRecovery() {
        var retry = NativePiPSnapshotRetry()
        require(!retry.beginAttempt(now: 0, eligible: false), "ineligible decoder state never submits a screenshot")
        require(retry.totalAttempts == 0, "waiting for valid dimensions does not spend the burst")
        for attempt in 0..<3 {
            let now = Double(attempt) / 4
            require(retry.beginAttempt(now: now, eligible: true), "eligible snapshot attempt \(attempt + 1) is allowed")
            require(!retry.beginAttempt(now: now + 0.1, eligible: true), "only one screenshot command may be pending")
            retry.completeAttempt(frameReady: false, now: now)
        }
        require(!retry.beginAttempt(now: 2.49, eligible: true), "three failed frames require a full two-second cooldown")
        require(retry.beginAttempt(now: 2.5, eligible: true), "a fourth attempt can recover in the same playback session")
        retry.completeAttempt(frameReady: true, now: 2.5)
        require(retry.frameReady && !retry.pending && retry.totalAttempts == 4, "only acknowledged frame readiness completes bootstrap")
        require(!retry.beginAttempt(now: 100, eligible: true), "a ready foreground sample stops further snapshot requests")
    }

    private static func verifyInterruptedRequest() {
        var retry = NativePiPSnapshotRetry()
        require(retry.beginAttempt(now: 10, eligible: true), "a command starts pending")
        // The owner has expired the reply ID before completing a timed-out
        // attempt. The replacement receives a new ID in the controller.
        retry.completeAttempt(frameReady: false, now: 12)
        require(retry.beginAttempt(now: 12, eligible: true), "an expired async command can be replaced")
        retry.completeAttempt(frameReady: false, now: 12)
        retry.completeAttempt(frameReady: true, now: 13)
        require(!retry.frameReady, "unsolicited or duplicate completion cannot invent frame readiness")
        require(retry.beginAttempt(now: 13, eligible: true), "retry remains available after ignored duplicate completion")
        retry.completeAttempt(frameReady: false, now: 13)
        require(!retry.beginAttempt(now: 14, eligible: true), "timeout failures count toward burst throttling")
        require(retry.beginAttempt(now: 15, eligible: true), "timeout recovery resumes after cooldown")
        var newSession = NativePiPSnapshotRetry()
        require(newSession.beginAttempt(now: 0, eligible: true), "a new playback session has independent retry state")
    }

    private static func verifyForegroundAndControls() {
        require(!NativePiPPolicy.shouldStopOnForeground(returnedFromBackground: false, transitioningOrActive: false),
                "Control Center return preserves the armed inline bridge")
        require(NativePiPPolicy.shouldStopOnForeground(returnedFromBackground: true, transitioningOrActive: false),
                "actual background return can release the prior bridge")
        require(NativePiPPolicy.shouldStopOnForeground(returnedFromBackground: false, transitioningOrActive: true),
                "active or pending PiP closes through its asynchronous stop handshake")
        var accepted = 0
        for bits in 0..<16 {
            let allowed = NativePiPPolicy.acceptsControls(stopped: bits & 1 != 0, stopping: bits & 2 != 0,
                sourceMatchesController: bits & 4 != 0, sourceIsActive: bits & 8 != 0)
            guard allowed == (bits == 12) else { fatalError("FAIL: control combination \(bits) bypassed ownership") }
            if allowed { accepted += 1 }
        }
        require(accepted == 1, "only the live current PiP controller accepts controls across 16 combinations")
    }
}
