import XCTest

final class MovieSearchUITests: XCTestCase {
    func testEachPartOfAResultSelectsThatExactRow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "movie-search-hit"]
        app.launch()
        defer { app.terminate() }
        let selected = app.staticTexts["search-hit.selected"]
        let firstID = "phim4k:https://preview.invalid/movie/search-1"
        let secondID = "phim4k:https://preview.invalid/movie/search-2"
        let first = app.buttons["search-result-" + firstID]
        let second = app.buttons["search-result-" + secondID]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        // Alternate rows so a lingering selection cannot hide an incorrect tap.
        for (row, expected, x) in [(first, firstID, 0.10), (second, secondID, 0.48),
                                   (first, firstID, 0.96), (second, secondID, 0.80)] {
            XCTAssertTrue(row.isHittable)
            row.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in selected.label == expected }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed,
                           "Poster, title, chevron and blank space must select their own row")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "movie-search-exact-row-hit-regions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
