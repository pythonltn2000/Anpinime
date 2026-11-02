import XCTest

/// Exercises the real five-tab app with separate fixture and bounded live checks.
final class AIDramaUITests: XCTestCase {
    private var app: XCUIApplication!
    private let seriesID = "7000000000000000001"
    private var liveDeadline: Date?
    private var attachedFailureAccessibilityTree = false
    private var isLiveTest: Bool { name.contains("testLivePineDrama") }

    private struct PlayerState: Decodable {
        let selectedEpisodeID: String?
        let resolving: Bool
        let manuallyPaused: Bool
        let currentTime: Double
        let mediaInfo: String
        let ownedPlayers: Int
        let maximumOwnedPlayers: Int
        let playerCreations: Int
        let cancelledResolutions: Int
    }

    private enum HarnessError: Error { case failed(String) }

    override func setUpWithError() throws {
        continueAfterFailure = false
        attachedFailureAccessibilityTree = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        if isLiveTest {
            executionTimeAllowance = 115
            liveDeadline = Date().addingTimeInterval(108)
        }
        app.launchArguments = [isLiveTest ? "--ai-drama-live-smoke" : "--ai-drama-smoke"]
        app.launch()
    }

    override func record(_ issue: XCTIssue) {
        if app != nil && !attachedFailureAccessibilityTree {
            // Set this before querying AX so a snapshot failure cannot recurse.
            attachedFailureAccessibilityTree = true
            let tree = app.debugDescription
            let limit = 30_000
            let suffix = tree.count > limit ? "\n[Accessibility tree truncated at 30,000 characters]" : ""
            let attachment = XCTAttachment(string: String(tree.prefix(limit)) + suffix)
            attachment.name = "ai-drama-failure-accessibility-tree"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.record(issue)
    }

    override func tearDownWithError() throws {
        if app != nil {
            capture("final-ui-state")
            attachTelemetry()
            app.terminate()
        }
    }

    func testVerticalEpisodesPlaylistAndLifecycle() throws {
        let health = try fixtureJSON("/__smoke__/health")
        XCTAssertEqual(health["service"] as? String, "anpinime-ai-drama-fixture")
        XCTAssertEqual(health["episodeCount"] as? Int, 40)
        try assertFiveTabs()

        let series = app.buttons["aidrama.series." + seriesID]
        try waitFor("The local AI drama catalog appears") { series.exists && series.isHittable }
        series.tap()
        try waitForPlaying(episode: 1)
        assertNoSocialControls()
        capture("episode-01-portrait-playing")

        // A native drag commits episode 2, whose API response takes four seconds.
        dragToNextEpisode()
        try waitFor("Episode 2 starts its delayed resolution", timeout: 3) {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(2) && state.resolving
        }
        let delayed = try fixtureJSON("/__smoke__/stats?wait_for=resolve_started&episode=2")
        XCTAssertTrue(hasEvent(delayed, "resolve_started", episode: 2), "The delayed request reached the fixture")
        XCTAssertFalse(hasEvent(delayed, "resolve_finished", episode: 2), "Swipe again before episode 2 resolves")

        dragToNextEpisode()
        try waitForPlaying(episode: 3)
        try assertStableSelection(episode: 3, duration: 5)
        let third = try requirePlayerState()
        XCTAssertGreaterThanOrEqual(third.cancelledResolutions, 1)
        XCTAssertEqual(third.ownedPlayers, 1)
        XCTAssertEqual(third.maximumOwnedPlayers, 1)
        XCTAssertEqual(third.playerCreations, 2, "Only episodes 1 and 3 acquired players")
        let afterDelay = try fixtureJSON("/__smoke__/stats")
        XCTAssertTrue(hasEvent(afterDelay, "resolve_finished", episode: 2), "The stale response window was exercised")
        if let secondStarted = eventTime(afterDelay, "resolve_started", episode: 2),
           let thirdStarted = eventTime(afterDelay, "resolve_started", episode: 3),
           let secondFinished = eventTime(afterDelay, "resolve_finished", episode: 2) {
            XCTAssertLessThan(secondStarted, thirdStarted)
            XCTAssertLessThan(thirdStarted, secondFinished, "Episode 3 was requested before episode 2 returned")
        } else {
            XCTFail("Missing delayed-resolution event ordering")
        }
        XCTAssertTrue(hasEvent(afterDelay, "media", episode: 3), "MPV requested the distinct episode 3 clip")
        XCTAssertFalse(hasEvent(afterDelay, "media", episode: 2), "The canceled episode never acquired media")
        capture("episode-03-after-canceled-resolution")

        let playlist = app.buttons["aidrama.playlist.open"]
        XCTAssertTrue(playlist.label.contains("40"), "The full series has 40 episodes")
        playlist.tap()
        try waitFor("The complete episode drawer opens") { self.app.buttons["aidrama.playlist.close"].isHittable }
        XCTAssertTrue(app.navigationBars["Danh sách tập (40)"].exists)
        let last = app.buttons["aidrama.playlist.episode." + episodeID(40)]
        let episodeList = app.scrollViews["aidrama.playlist.episodes"]
        for _ in 0..<12 {
            if last.isHittable { break }
            if episodeList.exists { episodeList.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(last.isHittable, "Episode 40 is available in the full series playlist")
        capture("complete-playlist-episode-40")
        last.tap()
        try waitForPlaying(episode: 40)
        XCTAssertTrue(app.staticTexts["aidrama.episode.index"].label.contains("40/40"))
        XCTAssertTrue(try hasEvent(fixtureJSON("/__smoke__/stats"), "media", episode: 40))
        capture("episode-40-portrait-playing")

        let pause = app.buttons["aidrama.playpause"]
        XCTAssertEqual(pause.label, "Tạm dừng")
        pause.tap()
        try waitFor("Manual pause takes effect") { self.playerState()?.manuallyPaused == true }
        try assertPausedTimeStable(duration: 2)
        XCUIDevice.shared.press(.home)
        try waitFor("The app enters the background") {
            self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
        }
        app.activate()
        try waitFor("The paused episode restores decoded portrait media") {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(40) && state.manuallyPaused
                && state.ownedPlayers == 1 && state.currentTime > 0.5
                && state.mediaInfo.contains("360 × 640")
        }
        XCTAssertEqual(pause.label, "Phát")
        try assertPausedTimeStable(duration: 2)
        capture("episode-40-manual-pause-after-reactivation")

        app.buttons["aidrama.close"].tap()
        try assertFiveTabs()
        try waitFor("Closing releases the native player") {
            let owner = self.app.descendants(matching: .any).matching(identifier: "aidrama.debug.ownedPlayers").firstMatch
            guard owner.exists else { return false }
            let raw = owner.value as? String ?? owner.label
            return Int(raw) == 0
        }
        XCTAssertFalse(app.buttons["aidrama.close"].exists)
        capture("five-native-tabs-after-player-close")
    }

    func testLivePineDramaPlaylistAndVideo() throws {
        let liveSeriesID = "7676620083434656784"
        let liveTitle = "Thần Ẩm Thực Ở Ngục Tù Cổ Đại"
        let firstID = "7676620734394862865"
        let secondID = "7676620627842731265"
        let lastID = "7676620695161310481"
        let series = app.buttons["aidrama.series." + liveSeriesID]
        let catalogCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "aidrama.series."))
        try waitForLive("The fresh PineDrama catalog loads", timeout: 15) { catalogCards.count > 0 }
        for _ in 0..<5 {
            try requireLiveBudget()
            if series.exists && series.isHittable { break }
            let catalog = app.scrollViews.firstMatch
            if catalog.exists { catalog.swipeUp() } else { break }
        }
        guard series.exists && series.isHittable else {
            XCTFail("The fresh catalog does not contain \(liveTitle) (\(liveSeriesID))")
            throw HarnessError.failed("Required live series is absent; no substitute series is allowed")
        }
        series.tap()
        try waitForLivePlaying(id: firstID, number: 1)
        XCTAssertEqual(app.staticTexts["aidrama.series.title"].label.lowercased(), liveTitle.lowercased())
        XCTAssertTrue(app.buttons["aidrama.playlist.open"].label.contains("40"))
        assertNoSocialControls()
        attachTelemetry(name: "live-episode-01-decoded-state")
        capture("live-pinedrama-episode-01-portrait-playing")

        dragToNextEpisode()
        try waitForLivePlaying(id: secondID, number: 2)
        attachTelemetry(name: "live-episode-02-decoded-state")
        capture("live-pinedrama-episode-02-after-vertical-swipe")

        app.buttons["aidrama.playlist.open"].tap()
        try waitForLive("The live 40-episode drawer opens", timeout: 5) {
            self.app.buttons["aidrama.playlist.close"].isHittable
        }
        XCTAssertTrue(app.navigationBars["Danh sách tập (40)"].exists)
        let last = app.buttons["aidrama.playlist.episode." + lastID]
        let episodes = app.scrollViews["aidrama.playlist.episodes"]
        for _ in 0..<8 {
            try requireLiveBudget()
            if last.isHittable { break }
            if episodes.exists { episodes.swipeUp() } else { app.swipeUp() }
        }
        guard last.isHittable else {
            XCTFail("The complete live playlist does not expose the real episode 40")
            throw HarnessError.failed("Required last live episode is absent")
        }
        last.tap()
        try waitForLivePlaying(id: lastID, number: 40)
        attachTelemetry(name: "live-episode-40-decoded-state")
        capture("live-pinedrama-episode-40-portrait-playing")
        app.buttons["aidrama.close"].tap()
    }

    private func episodeID(_ number: Int) -> String { String(Int64(7_000_000_000_000_000_100) + Int64(number)) }

    private func assertFiveTabs() throws {
        let tabs = app.tabBars.firstMatch
        try waitFor("The native five-tab bar is visible") { tabs.exists && tabs.buttons.count == 5 }
        for title in ["Trang chủ", "Tìm kiếm", "Thể loại", "Phim AI", "Cài đặt"] {
            XCTAssertTrue(tabs.buttons[title].exists, "Missing native tab: \(title)")
        }
        XCTAssertFalse(tabs.buttons["More"].exists)
        XCTAssertFalse(tabs.buttons["Thêm"].exists)
    }

    private func assertNoSocialControls() {
        for identifier in ["aidrama.like", "aidrama.comment", "aidrama.share"] {
            XCTAssertFalse(app.buttons[identifier].exists)
        }
        for label in ["Thích", "Bình luận", "Chia sẻ", "Like", "Comment", "Share"] {
            XCTAssertFalse(app.buttons[label].exists)
        }
    }

    private func dragToNextEpisode() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
        start.press(forDuration: 0.05, thenDragTo: finish)
    }

    private func waitForPlaying(episode: Int) throws {
        try waitFor("Episode \(episode) decodes portrait video and advances", timeout: 25) {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(episode) && !state.resolving
                && state.currentTime > 1 && state.mediaInfo.contains("360 × 640")
                && state.ownedPlayers == 1 && !state.manuallyPaused
        }
        let before = try requirePlayerState().currentTime
        try waitFor("Episode \(episode) playback time keeps advancing", timeout: 8) {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(episode) && state.currentTime > before + 0.8
        }
        XCTAssertEqual(app.staticTexts["aidrama.episode.index"].value as? String, episodeID(episode))
    }

    private func waitForLivePlaying(id: String, number: Int) throws {
        var firstDecodedTime: Double?
        try waitForLive("Live episode \(number) decodes portrait video and keeps advancing", timeout: 25) {
            guard let state = self.playerState(), state.selectedEpisodeID == id, !state.resolving,
                  !state.manuallyPaused, state.ownedPlayers == 1, state.currentTime > 1,
                  self.isDecodedPortrait(state.mediaInfo) else { return false }
            guard let before = firstDecodedTime else {
                firstDecodedTime = state.currentTime
                return false
            }
            return state.currentTime > before + 0.8
        }
        let index = app.staticTexts["aidrama.episode.index"]
        XCTAssertEqual(index.value as? String, id)
        XCTAssertTrue(index.label.contains("\(number)/40"))
        XCTAssertEqual(try requirePlayerState().maximumOwnedPlayers, 1)
    }

    private func isDecodedPortrait(_ info: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*[×x]\s*(\d+)"#) else { return false }
        let value = info as NSString
        guard let match = expression.firstMatch(in: info, range: NSRange(location: 0, length: value.length)),
              let width = Int(value.substring(with: match.range(at: 1))),
              let height = Int(value.substring(with: match.range(at: 2))) else { return false }
        return width > 0 && height > width
    }

    private func requireLiveBudget() throws {
        guard let liveDeadline, liveDeadline.timeIntervalSinceNow > 0 else {
            XCTFail("The bounded live playback check exhausted its time budget")
            throw HarnessError.failed("Live test exceeded its 108-second action budget")
        }
    }

    private func waitForLive(_ message: String, timeout: TimeInterval, condition: @escaping () -> Bool) throws {
        try requireLiveBudget()
        try waitFor(message, timeout: max(0.1, min(timeout, liveDeadline!.timeIntervalSinceNow)), condition: condition)
    }

    private func assertStableSelection(episode: Int, duration: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(duration)
        var changed = false
        try waitFor("The selected episode survives a late response", timeout: duration + 3) {
            guard let state = self.playerState() else { return false }
            if state.selectedEpisodeID != self.episodeID(episode) { changed = true; return true }
            return Date() >= deadline
        }
        XCTAssertFalse(changed, "A stale resolution replaced the committed episode")
    }

    private func assertPausedTimeStable(duration: TimeInterval) throws {
        let before = try requirePlayerState().currentTime
        let deadline = Date().addingTimeInterval(duration)
        var resumed = false
        try waitFor("Manual pause keeps playback time stable", timeout: duration + 3) {
            guard let state = self.playerState() else { return false }
            if !state.manuallyPaused || abs(state.currentTime - before) > 0.4 { resumed = true; return true }
            return Date() >= deadline
        }
        XCTAssertFalse(resumed, "Playback advanced while manually paused")
    }

    private func playerState() -> PlayerState? {
        let element = app.descendants(matching: .any).matching(identifier: "aidrama.debug.state").firstMatch
        guard element.exists else { return nil }
        let raw = element.value as? String ?? element.label
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlayerState.self, from: data)
    }

    private func requirePlayerState() throws -> PlayerState {
        guard let state = playerState() else { throw HarnessError.failed("Missing DEBUG player telemetry") }
        return state
    }

    private func waitFor(_ message: String, timeout: TimeInterval = 15, condition: @escaping () -> Bool) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed else {
            capture("failure-" + message)
            attachTelemetry()
            XCTFail(message)
            throw HarnessError.failed(message)
        }
    }

    private func fixtureJSON(_ path: String) throws -> [String: Any] {
        let requestFinished = expectation(description: "Loopback fixture response")
        var received: Data?
        var failure: Error?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: URL(string: "http://127.0.0.1:8768" + path)!) { data, response, error in
            received = data
            failure = error
            if (response as? HTTPURLResponse)?.statusCode != 200 {
                failure = HarnessError.failed("Fixture HTTP status is not 200")
            }
            requestFinished.fulfill()
        }.resume()
        guard XCTWaiter.wait(for: [requestFinished], timeout: 4) == .completed else {
            throw HarnessError.failed("Loopback fixture did not respond")
        }
        if let failure { throw failure }
        guard let received, let result = try JSONSerialization.jsonObject(with: received) as? [String: Any] else {
            throw HarnessError.failed("Invalid loopback fixture JSON")
        }
        return result
    }

    private func hasEvent(_ stats: [String: Any], _ event: String, episode: Int) -> Bool {
        (stats["events"] as? [[String: Any]] ?? []).contains {
            $0["event"] as? String == event && $0["episode"] as? Int == episode
        }
    }

    private func eventTime(_ stats: [String: Any], _ event: String, episode: Int) -> Double? {
        (stats["events"] as? [[String: Any]] ?? []).first {
            $0["event"] as? String == event && $0["episode"] as? Int == episode
        }?["elapsed"] as? Double
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachTelemetry(name: String = "ai-drama-player-state") {
        let element = app.descendants(matching: .any).matching(identifier: "aidrama.debug.state").firstMatch
        let state = element.exists ? (element.value as? String ?? element.label) : "Player is not presented"
        let attachment = XCTAttachment(string: state)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if !isLiveTest, let stats = try? fixtureJSON("/__smoke__/stats"),
           let data = try? JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let fixture = XCTAttachment(string: text)
            fixture.name = "ai-drama-local-fixture-events"
            fixture.lifetime = .keepAlways
            add(fixture)
        }
    }
}
