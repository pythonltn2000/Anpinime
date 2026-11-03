import XCTest
import CoreFoundation

/// Exercises the independent AI library with separate fixture and bounded live checks.
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
        let subtitleTrack: String?
    }

    private enum HarnessError: Error { case failed(String) }
    private struct LiveEpisode: Codable {
        let id: String
        let number: Int
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        attachedFailureAccessibilityTree = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        if isLiveTest {
            executionTimeAllowance = 115
            liveDeadline = Date().addingTimeInterval(108)
        } else {
            executionTimeAllowance = 240
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
        try assertAITabs()

        let series = app.buttons["aidrama.series." + seriesID]
        try waitFor("The local AI drama catalog appears") { series.exists && series.isHittable }
        series.tap()
        try waitForPlaying(episode: 1)
        assertNoSocialControls()
        capture("episode-01-portrait-playing")

        let initialSubtitle = try requirePlayerState().subtitleTrack ?? ""
        XCTAssertFalse(initialSubtitle.isEmpty || initialSubtitle == "off", "Fixture has an active embedded subtitle")
        for id in ["off", initialSubtitle] {
            app.buttons["Cài đặt phát"].tap()
            let subtitles = app.buttons["player.settings.subtitles"]
            XCTAssertTrue(subtitles.waitForExistence(timeout: 5))
            subtitles.tap()
            let choice = app.buttons["player.track.subtitles." + id]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            app.buttons["Đóng cài đặt"].tap()
            try waitFor("AI settings select the actual native subtitle track") { self.playerState()?.subtitleTrack == id }
        }
        capture("episode-01-native-subtitle-menu-selection")

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
        try assertAITabs()
        try waitFor("Closing releases the native player") {
            let owner = self.app.descendants(matching: .any).matching(identifier: "aidrama.debug.ownedPlayers").firstMatch
            guard owner.exists else { return false }
            let raw = owner.value as? String ?? owner.label
            return Int(raw) == 0
        }
        XCTAssertFalse(app.buttons["aidrama.close"].exists)
        capture("four-ai-tabs-after-player-close")

        // History is a user-visible route back to the exact episode, including its pause state.
        let history = app.buttons["aidrama.history." + seriesID]
        for _ in 0..<8 {
            if history.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(history.isHittable, "Watching creates an entry on the AI home screen")
        history.tap()
        try waitFor("History resumes the exact last watched episode") {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(40) && !state.resolving
                && state.manuallyPaused && state.currentTime > 0.5
                && state.mediaInfo.contains("360 × 640") && state.ownedPlayers == 1
        }
        capture("history-resumes-episode-40")
        app.buttons["aidrama.close"].tap()
    }

    func testShortFeedSwipeFullscreenAndFullPlaylist() throws {
        try assertAITabs()
        XCTAssertFalse(app.buttons["Làm mới Phim AI"].exists)
        app.tabBars.buttons["Phim ngắn"].tap()
        try waitFor("Native short feed decodes its landscape recommendation", timeout: 25) {
            guard let state = self.playerState() else { return false }
            return state.selectedEpisodeID == self.episodeID(5) && state.currentTime > 1 && state.mediaInfo.contains("640 × 360")
        }
        XCTAssertEqual(app.staticTexts["aidrama.shorts.title"].label, "Short Feed Fixture 1")
        assertNoSocialControls()
        capture("short-feed-landscape-in-portrait")
        let before = try requirePlayerState().currentTime
        app.buttons["aidrama.shorts.fullscreen"].tap()
        try waitFor("Fullscreen rotates the same short video") { self.app.frame.width > self.app.frame.height }
        XCTAssertEqual(try requirePlayerState().selectedEpisodeID, episodeID(5))
        try waitFor("Fullscreen retains advancing playback") { (self.playerState()?.currentTime ?? 0) > before + 0.5 }
        capture("short-feed-fullscreen-landscape")
        app.buttons["aidrama.shorts.fullscreen"].tap()
        try waitFor("Exiting fullscreen returns to portrait") { self.app.frame.width < self.app.frame.height }
        dragToNextEpisode()
        let secondID = String(Int64(7_000_000_000_000_000_100) + 100 + 3)
        try waitFor("A vertical swipe plays the next actual recommendation", timeout: 25) {
            self.playerState()?.selectedEpisodeID == secondID && (self.playerState()?.currentTime ?? 0) > 1
        }
        try waitFor("Near the feed end loads the next native page") {
            guard let stats = try? self.fixtureJSON("/__smoke__/stats"), let events = stats["events"] as? [[String: Any]] else { return false }
            return events.contains { $0["event"] as? String == "short_feed" && $0["page"] as? Int == 2 }
        }
        capture("short-feed-next-recommendation")
        app.buttons["aidrama.shorts.all"].tap()
        try waitFor("Play all opens the exact recommendation episode in its full playlist", timeout: 25) {
            self.app.buttons["aidrama.playlist.open"].exists && self.playerState()?.selectedEpisodeID == secondID
        }
        XCTAssertTrue(app.buttons["aidrama.playlist.open"].label.contains("40"))
        app.buttons["aidrama.close"].tap()
        app.tabBars.buttons["Trang chủ"].tap()
        try waitFor("Leaving the short feed releases its player") {
            let owner = self.app.buttons["aidrama.debug.ownedPlayers"]
            return owner.exists && (owner.value as? String) == "0"
        }
    }

    func testCatalogPagingFiltersAndLibraryChoices() throws {
        try assertAITabs()
        try waitFor("The AI home has a real catalog card") {
            self.app.buttons["aidrama.series." + self.seriesID].isHittable
        }

        // The second page must append from scrolling, without the refresh action.
        app.tabBars.buttons["Khám phá"].tap()
        app.segmentedControls["aidrama.explore.mode"].buttons["Mới"].tap()
        let newScroll = app.scrollViews["aidrama.new.results"]
        let secondPage = app.buttons["aidrama.series." + fixtureSeriesID(3012)]
        try scrollUntilHittable(secondPage, in: newScroll, message: "Scrolling appends new works page 2")
        XCTAssertTrue(secondPage.label.contains("New Fixture 13"))
        let newStats = try fixtureJSON("/__smoke__/stats")
        XCTAssertEqual(eventCount(newStats, "catalog_started", feed: "new", page: 1), 1,
                       "Infinite paging does not refresh and replace page 1")
        XCTAssertEqual(eventCount(newStats, "catalog_started", feed: "new", page: 2), 1)
        capture("new-works-appends-native-cursor-page-2")

        app.segmentedControls["aidrama.explore.mode"].buttons["Thịnh hành"].tap()
        let hot = app.buttons["aidrama.series." + fixtureSeriesID(1000)]
        try waitFor("The hot ranking finishes loading") { hot.isHittable }
        let previousHotRequests = eventCount(try fixtureJSON("/__smoke__/stats"), "catalog_started", feed: "hot", page: 1)
        app.tabBars.buttons["Cài đặt"].tap()
        app.buttons["Làm mới danh sách phim"].tap()
        try waitFor("Refreshing starts a delayed hot ranking request") {
            guard let stats = try? self.fixtureJSON("/__smoke__/stats") else { return false }
            return self.eventCount(stats, "catalog_started", feed: "hot", page: 1) > previousHotRequests
        }
        app.tabBars.buttons["Khám phá"].tap()
        let latestSegment = app.segmentedControls["aidrama.ranking.mode"].buttons["Mới nhất"]
        XCTAssertTrue(latestSegment.isHittable)
        latestSegment.tap()
        let latest = app.buttons["aidrama.series." + fixtureSeriesID(2000)]
        try waitFor("Switching ranking displays the latest response") { latest.isHittable }
        try waitFor("The former hot response reaches its stale-response window", timeout: 8) {
            guard let stats = try? self.fixtureJSON("/__smoke__/stats") else { return false }
            return self.eventCount(stats, "catalog_finished", feed: "hot", page: 1) > previousHotRequests
        }
        XCTAssertTrue(latest.isHittable)
        XCTAssertFalse(hot.exists, "A late hot response must not replace the selected latest ranking")
        XCTAssertTrue(latestSegment.isSelected)
        capture("latest-ranking-survives-delayed-hot-response")

        app.segmentedControls["aidrama.explore.mode"].buttons["Danh mục"].tap()
        let fantasy = app.buttons["aidrama.filter.background.7628991192537158672"]
        let revenge = app.buttons["aidrama.filter.character.7628991193891820560"]
        let story = app.buttons["aidrama.filter.story.7628991193543840769"]
        let recent = app.buttons["aidrama.filter.releaseTime.days:7"]
        try waitFor("All four native category filter rows are usable") {
            [fantasy, revenge, story, recent].allSatisfy { $0.isHittable }
        }
        fantasy.tap()
        try waitFor("The first category selection starts its delayed response") {
            guard let stats = try? self.fixtureJSON("/__smoke__/stats") else { return false }
            return self.categoryEventCount(stats, "catalog_started", mask: 1, days: 0) > 0
        }
        revenge.tap()
        story.tap()
        recent.tap()
        let filtered = app.buttons["aidrama.series." + fixtureSeriesID(4707)]
        let categories = app.scrollViews["aidrama.categories.results"]
        try scrollUntilHittable(filtered, in: categories, message: "The four combined filters load the matching catalog")
        XCTAssertTrue(filtered.label.contains("Category 7-7 Fixture 1"))
        try waitFor("The earlier single-filter response completes", timeout: 8) {
            guard let stats = try? self.fixtureJSON("/__smoke__/stats") else { return false }
            return self.categoryEventCount(stats, "catalog_finished", mask: 1, days: 0) > 0
        }
        XCTAssertTrue(filtered.isHittable)
        XCTAssertFalse(app.buttons["aidrama.series." + fixtureSeriesID(4100)].exists,
                       "An obsolete filter response must not overwrite the combined selection")
        let filteredSecondPage = app.buttons["aidrama.series." + fixtureSeriesID(4719)]
        try scrollUntilHittable(filteredSecondPage, in: categories, message: "The combined category selection appends its own next page")
        capture("four-native-filters-and-category-cursor-paging")

        app.buttons["aidrama.library.choose"].tap()
        try assertLibraryChoices()
        app.buttons["library.choice.movie"].tap()
        try assertTabs(["Trang chủ", "Tìm kiếm", "Thể loại", "Cài đặt"])
        let sourceMenu = app.buttons["movie.source.choose"]
        try waitFor("The movie source chooser is available") { sourceMenu.isHittable }
        sourceMenu.tap()
        for source in ["film4k", "phim4k", "kkphim"] {
            XCTAssertTrue(app.buttons["movie.source." + source].exists, "Existing source ID remains independently selectable: \(source)")
        }
        app.buttons["movie.source.phim4k"].tap()
        try waitFor("The selected movie source is Premium") { sourceMenu.value as? String == "Anpinime Premium" }
        try openLibraryChooserFromSettings()
        app.buttons["library.choice.aiDrama"].tap()
        try assertAITabs()
        app.buttons["aidrama.library.choose"].tap()
        app.buttons["library.choice.movie"].tap()
        try assertTabs(["Trang chủ", "Tìm kiếm", "Thể loại", "Cài đặt"])
        XCTAssertEqual(app.buttons["movie.source.choose"].value as? String, "Anpinime Premium",
                       "Entering AI preserves the user's selected movie provider")
        try openLibraryChooserFromSettings()
        try assertLibraryChoices()
        app.buttons["library.choice.anime"].tap()
        try assertTabs(["Trang chủ", "Tìm kiếm", "Thể loại", "Lịch chiếu", "Cài đặt"])
        try openLibraryChooserFromSettings()
        app.buttons["library.choice.aiDrama"].tap()
        try assertAITabs()
        capture("independent-ai-library-after-movie-and-anime")
    }

    func testLivePineDramaPlaylistAndVideo() throws {
        try assertAITabs()
        let catalogCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "aidrama.series."))
        try waitForLive("The fresh PineDrama catalog loads", timeout: 15) { catalogCards.count > 0 }
        // Commit the objective before requesting its panel; never try another series.
        let firstCard = catalogCards.element(boundBy: 0)
        let identifier = firstCard.identifier
        let cardLabel = firstCard.label
        let liveSeriesID = String(identifier.dropFirst("aidrama.series.".count))
        guard firstCard.isHittable, oracleIdentifier(liveSeriesID) != nil,
              let countPattern = try? NSRegularExpression(pattern: #"(\d+)\s+tập$"#),
              let countMatch = countPattern.firstMatch(in: cardLabel, range: NSRange(location: 0, length: (cardLabel as NSString).length)),
              let total = Int((cardLabel as NSString).substring(with: countMatch.range(at: 1))), total >= 2 else {
            throw HarnessError.failed("The first fresh catalog card lacks a valid series ID or episode count")
        }
        let expected = try livePanelOracle(seriesID: liveSeriesID, expectedCount: total)
        let first = expected[0], second = expected[1], final = expected[expected.count - 1]
        let oracleFields: [String: Any] = [
            "selectionPolicy": "First actual fresh catalog card, fixed before the single panel request",
            "seriesID": liveSeriesID, "catalogLabel": cardLabel, "episodeCount": total,
            "panelEpisodeCount": expected.count, "oracleRequestCount": 1,
            "targets": [first, second, final].map { ["id": $0.id, "number": $0.number] as [String: Any] }
        ]
        let oracleData = try JSONSerialization.data(withJSONObject: oracleFields, options: [.sortedKeys])
        let oracleAttachment = XCTAttachment(string: String(decoding: oracleData, as: UTF8.self))
        oracleAttachment.name = "live-selected-catalog-panel-oracle"
        oracleAttachment.lifetime = .keepAlways
        add(oracleAttachment)
        let series = app.buttons[identifier]
        guard series.isHittable else { throw HarnessError.failed("The originally selected catalog card disappeared") }
        series.tap()
        try waitForLivePlaying(id: first.id, number: first.number, total: total)
        let displayedTitle = app.staticTexts["aidrama.series.title"].label
        XCTAssertFalse(displayedTitle.isEmpty)
        XCTAssertTrue(cardLabel.contains(displayedTitle))
        XCTAssertTrue(app.buttons["aidrama.playlist.open"].label.contains("(\(total))"))
        assertNoSocialControls()
        attachTelemetry(name: "live-episode-01-decoded-state")
        capture("live-pinedrama-episode-01-portrait-playing")

        dragToNextEpisode()
        try waitForLivePlaying(id: second.id, number: second.number, total: total)
        attachTelemetry(name: "live-episode-02-decoded-state")
        capture("live-pinedrama-episode-02-after-vertical-swipe")

        app.buttons["aidrama.playlist.open"].tap()
        try waitForLive("The complete live episode drawer opens", timeout: 5) {
            self.app.buttons["aidrama.playlist.close"].isHittable
        }
        XCTAssertTrue(app.navigationBars["Danh sách tập (\(total))"].exists)
        let last = app.buttons["aidrama.playlist.episode." + final.id]
        let episodes = app.scrollViews["aidrama.playlist.episodes"]
        for _ in 0..<8 {
            try requireLiveBudget()
            if last.isHittable { break }
            if episodes.exists { episodes.swipeUp() } else { app.swipeUp() }
        }
        guard last.isHittable else {
            XCTFail("The complete live playlist does not expose its independently verified last episode")
            throw HarnessError.failed("Required last live episode is absent")
        }
        last.tap()
        try waitForLivePlaying(id: final.id, number: final.number, total: total)
        attachTelemetry(name: "live-episode-\(final.number)-decoded-state")
        capture("live-pinedrama-episode-\(final.number)-portrait-playing")
        app.buttons["aidrama.close"].tap()
    }

    func testLivePineDramaShortFeedAndPlaylist() throws {
        try assertAITabs()
        app.tabBars.buttons["Phim ngắn"].tap()
        try waitForLive("A native live feed video decodes and advances", timeout: 30) {
            guard let state = self.playerState() else { return false }
            return state.currentTime > 1 && state.ownedPlayers == 1 && self.isDecodedVideo(state.mediaInfo, portraitOnly: false)
        }
        let all = app.buttons["aidrama.shorts.all"]
        let fields = (all.value as? String ?? "").split(separator: "|").map(String.init)
        guard fields.count == 4, let number = Int(fields[2]), let total = Int(fields[3]), total > 0 else {
            throw HarnessError.failed("Live short feed metadata is absent")
        }
        let episodes = try livePanelOracle(seriesID: fields[0], expectedCount: total)
        XCTAssertTrue(episodes.contains { $0.id == fields[1] && $0.number == number })
        capture("live-short-feed-native-video")
        attachTelemetry(name: "live-short-feed-decoded-state")
        assertNoSocialControls()
        app.buttons["aidrama.shorts.fullscreen"].tap()
        try waitForLive("The same live recommendation rotates to fullscreen", timeout: 8) { self.app.frame.width > self.app.frame.height }
        XCTAssertEqual(try requirePlayerState().selectedEpisodeID, fields[1])
        capture("live-short-feed-fullscreen")
        app.buttons["aidrama.shorts.fullscreen"].tap()
        try waitForLive("The live feed returns to portrait", timeout: 8) { self.app.frame.width < self.app.frame.height }
        all.tap()
        try waitForLivePlaying(id: fields[1], number: number, total: total, portraitOnly: false)
        app.buttons["aidrama.playlist.open"].tap()
        try waitForLive("The live feed opens its independently verified complete playlist", timeout: 5) {
            self.app.buttons["aidrama.playlist.close"].isHittable
        }
        let final = episodes.last!
        let last = app.buttons["aidrama.playlist.episode." + final.id]
        for _ in 0..<10 {
            try requireLiveBudget()
            if last.isHittable { break }
            app.swipeUp()
        }
        guard last.isHittable else { throw HarnessError.failed("Last native feed episode missing") }
        last.tap()
        try waitForLivePlaying(id: final.id, number: final.number, total: total, portraitOnly: false)
        attachTelemetry(name: "live-short-feed-final-episode-decoded-state")
        capture("live-short-feed-final-episode")
        app.buttons["aidrama.close"].tap()
    }

    /// One independent native panel request, only from the simulator test runner.
    private func livePanelOracle(seriesID: String, expectedCount: Int) throws -> [LiveEpisode] {
        try requireLiveBudget()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let fields = [
            "aid": "845221", "app_name": "tiktok_drama", "app_package": "com.ss.iphone.ttmd.video",
            "channel": "App Store", "version_code": "46.6.0", "app_version": "46.6.0", "build_number": "466003",
            "device_platform": "iphone", "device_type": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iPhone17,3",
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", "os_api": String(os.majorVersion),
            "language": "vi", "app_language": "vi", "locale": "vi_VN", "sys_region": "VN", "region": "VN",
            "content_language": "vi", "tz_name": TimeZone.current.identifier,
            "tz_offset": String(TimeZone.current.secondsFromGMT()), "collection_id": seriesID
        ]
        var components = URLComponents(string: "https://api-va.tiktokv.com/tiktok/md/collection/episode_panel/v1/")!
        components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("PineDrama/466003 CFNetwork/Darwin", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: LiveOracleRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let finished = expectation(description: "Single independent native episode panel")
        var received: Data?
        var status: Int?
        var transportFailed = false
        session.dataTask(with: request) { data, response, error in
            received = data
            status = (response as? HTTPURLResponse)?.statusCode
            transportFailed = error != nil
            finished.fulfill()
        }.resume()
        guard XCTWaiter.wait(for: [finished], timeout: min(13, max(0.1, liveDeadline!.timeIntervalSinceNow))) == .completed,
              !transportFailed, status == 200, let received, !received.isEmpty, received.count <= 2 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: received) as? [String: Any],
              oracleInteger(object["status_code"]) == 0, let rows = object["episode_list"] as? [[String: Any]] else {
            throw HarnessError.failed("The single bounded native panel oracle failed")
        }
        var episodes: [LiveEpisode] = []
        var ids = Set<String>(), numbers = Set<Int>()
        for row in rows {
            if (row["is_intro"] as? NSNumber)?.boolValue == true
                || ["1", "true"].contains((row["is_intro"] as? String)?.lowercased() ?? "") { continue }
            guard let id = oracleIdentifier(row["video_id_str"]) ?? oracleIdentifier(row["video_id"]),
                  let number = oracleInteger(row["seq_id"]), number > 0, oracleInteger(row["num"]) == number,
                  ids.insert(id).inserted, numbers.insert(number).inserted else {
                throw HarnessError.failed("The native panel oracle returned invalid or duplicate real episodes")
            }
            episodes.append(LiveEpisode(id: id, number: number))
        }
        episodes.sort { $0.number < $1.number }
        guard episodes.count == expectedCount, episodes.map(\.number) == Array(1...expectedCount) else {
            throw HarnessError.failed("The native panel oracle does not match the complete catalog episode count")
        }
        return episodes
    }

    private func oracleIdentifier(_ raw: Any?) -> String? {
        let value: String
        if let text = raw as? String { value = text }
        else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                !["f", "d"].contains(String(cString: number.objCType)) { value = number.stringValue }
        else { return nil }
        guard !value.isEmpty, value.utf8.count <= 19, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let exact = UInt64(value), exact > 0, exact <= UInt64(Int64.max) else { return nil }
        return value
    }

    private func oracleInteger(_ raw: Any?) -> Int? {
        if let text = raw as? String { return Int(text) }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
        return Int(number.stringValue)
    }

    private func episodeID(_ number: Int) -> String { String(Int64(7_000_000_000_000_000_100) + Int64(number)) }

    private func assertAITabs() throws {
        try assertTabs(["Trang chủ", "Phim ngắn", "Khám phá", "Cài đặt"])
    }

    private func assertTabs(_ titles: [String]) throws {
        let tabs = app.tabBars.firstMatch
        try waitFor("The selected library's native tabs are visible") { tabs.exists && tabs.buttons.count == titles.count }
        for title in titles {
            XCTAssertTrue(tabs.buttons[title].exists, "Missing native tab: \(title)")
        }
        XCTAssertFalse(tabs.buttons["More"].exists)
        XCTAssertFalse(tabs.buttons["Thêm"].exists)
    }

    private func assertLibraryChoices() throws {
        try waitFor("The library chooser has three independent choices") {
            ["anime", "movie", "aiDrama"].allSatisfy { self.app.buttons["library.choice." + $0].exists }
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.choice.")).count, 3)
    }

    private func openLibraryChooserFromSettings() throws {
        app.tabBars.buttons["Cài đặt"].tap()
        let choose = app.buttons["Đổi thư viện"]
        for _ in 0..<6 {
            if choose.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(choose.isHittable)
        choose.tap()
        try assertLibraryChoices()
    }

    private func fixtureSeriesID(_ offset: Int) -> String {
        String(Int64(7_000_000_000_000_000_001) + Int64(offset))
    }

    private func scrollUntilHittable(_ element: XCUIElement, in scroll: XCUIElement, message: String) throws {
        for _ in 0..<14 {
            if element.isHittable { return }
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        try waitFor(message, timeout: 5) { element.isHittable }
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
        // Cross more than half the pager so a deliberate slow drag commits the page.
        let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
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

    private func waitForLivePlaying(id: String, number: Int, total: Int, portraitOnly: Bool = true) throws {
        var firstDecodedTime: Double?
        try waitForLive("Live episode \(number) decodes portrait video and keeps advancing", timeout: 25) {
            guard let state = self.playerState(), state.selectedEpisodeID == id, !state.resolving,
                  !state.manuallyPaused, state.ownedPlayers == 1, state.currentTime > 1,
                  self.isDecodedVideo(state.mediaInfo, portraitOnly: portraitOnly) else { return false }
            guard let before = firstDecodedTime else {
                firstDecodedTime = state.currentTime
                return false
            }
            return state.currentTime > before + 0.8
        }
        let index = app.staticTexts["aidrama.episode.index"]
        XCTAssertEqual(index.value as? String, id)
        XCTAssertTrue(index.label.contains("\(number)/\(total)"))
        XCTAssertEqual(try requirePlayerState().maximumOwnedPlayers, 1)
    }

    private func isDecodedVideo(_ info: String, portraitOnly: Bool) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*[×x]\s*(\d+)"#) else { return false }
        let value = info as NSString
        guard let match = expression.firstMatch(in: info, range: NSRange(location: 0, length: value.length)),
              let width = Int(value.substring(with: match.range(at: 1))),
              let height = Int(value.substring(with: match.range(at: 2))) else { return false }
        return width > 0 && height > 0 && (!portraitOnly || height > width)
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

    private func eventCount(_ stats: [String: Any], _ event: String, feed: String, page: Int) -> Int {
        (stats["events"] as? [[String: Any]] ?? []).filter {
            $0["event"] as? String == event && $0["feed"] as? String == feed && $0["page"] as? Int == page
        }.count
    }

    private func categoryEventCount(_ stats: [String: Any], _ event: String, mask: Int, days: Int) -> Int {
        (stats["events"] as? [[String: Any]] ?? []).filter {
            $0["event"] as? String == event && $0["feed"] as? String == "category"
                && $0["mask"] as? Int == mask && $0["days"] as? Int == days
        }.count
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

private final class LiveOracleRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
