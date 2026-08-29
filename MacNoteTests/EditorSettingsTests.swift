import XCTest
@testable import MacNote

final class EditorSettingsTests: XCTestCase {

    override func tearDownWithError() throws {
        // Restore the default so this test doesn't leak state into other tests
        // via the shared UserDefaults key.
        EditorSettings.shared.resetZoom()
    }

    func testDefaultSize() {
        XCTAssertEqual(EditorSettings.defaultSize, 14)
    }

    func testClampsToMaximum() {
        let settings = EditorSettings.shared
        settings.setFontSize(1000)
        XCTAssertEqual(settings.fontSize, EditorSettings.maxSize)
    }

    func testClampsToMinimum() {
        let settings = EditorSettings.shared
        settings.setFontSize(-5)
        XCTAssertEqual(settings.fontSize, EditorSettings.minSize)
    }

    func testZoomInIncrementsBySizeUnit() {
        let settings = EditorSettings.shared
        settings.resetZoom()
        let before = settings.fontSize
        settings.zoomIn()
        XCTAssertEqual(settings.fontSize, before + 1)
    }

    func testZoomOutDecrementsBySizeUnit() {
        let settings = EditorSettings.shared
        settings.resetZoom()
        let before = settings.fontSize
        settings.zoomOut()
        XCTAssertEqual(settings.fontSize, before - 1)
    }

    func testZoomOutAtMinimumStaysClamped() {
        let settings = EditorSettings.shared
        settings.setFontSize(EditorSettings.minSize)
        settings.zoomOut()
        XCTAssertEqual(settings.fontSize, EditorSettings.minSize)
    }

    func testResetZoomReturnsToDefault() {
        let settings = EditorSettings.shared
        settings.setFontSize(24)
        settings.resetZoom()
        XCTAssertEqual(settings.fontSize, EditorSettings.defaultSize)
    }

    func testFontsTrackCurrentSize() {
        let settings = EditorSettings.shared
        settings.setFontSize(20)
        XCTAssertEqual(settings.regularFont.pointSize, 20)
        XCTAssertEqual(settings.boldFont.pointSize, 20)
    }

    func testSettingSameSizeDoesNotPostNotification() {
        let settings = EditorSettings.shared
        settings.setFontSize(18)
        let expectation = expectation(description: "notification should not fire")
        expectation.isInverted = true
        let token = NotificationCenter.default.addObserver(
            forName: .editorFontSizeChanged, object: nil, queue: nil
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.setFontSize(18) // same value — no change, no notification

        wait(for: [expectation], timeout: 0.2)
    }

    func testSettingNewSizePostsNotification() {
        let settings = EditorSettings.shared
        settings.setFontSize(18)
        let expectation = expectation(description: "notification should fire")
        let token = NotificationCenter.default.addObserver(
            forName: .editorFontSizeChanged, object: nil, queue: nil
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.setFontSize(19)

        wait(for: [expectation], timeout: 0.2)
    }

    func testPersistsAcrossInstances() {
        EditorSettings.shared.setFontSize(22)
        // EditorSettings reads UserDefaults in init(); simulate a fresh
        // instance (e.g. after relaunch) to confirm persistence round-trips.
        let reloaded = EditorSettings()
        XCTAssertEqual(reloaded.fontSize, 22)
    }
}
