import XCTest

/// Launches the real five-tab app against a loopback PineDrama wire fixture.
final class AIDramaUITests: XCTestCase {
    private var app: XCUIApplication!
    private let seriesID = "7000000000000000001"

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
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ai-drama-smoke"]
        app.launch()
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

    private func attachTelemetry() {
        let element = app.descendants(matching: .any).matching(identifier: "aidrama.debug.state").firstMatch
        let state = element.exists ? (element.value as? String ?? element.label) : "Player is not presented"
        let attachment = XCTAttachment(string: state)
        attachment.name = "ai-drama-player-state"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let stats = try? fixtureJSON("/__smoke__/stats"),
           let data = try? JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let fixture = XCTAttachment(string: text)
            fixture.name = "ai-drama-local-fixture-events"
            fixture.lifetime = .keepAlways
            add(fixture)
        }
    }
}
