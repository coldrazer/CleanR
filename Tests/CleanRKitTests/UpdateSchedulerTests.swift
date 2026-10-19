import XCTest
@testable import CleanRKit

final class UpdateSchedulerTests: XCTestCase {

    // MARK: - isCheckDue

    func testCheckDueWhenNeverChecked() {
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: Date(), lastCheck: nil, interval: 86_400))
    }

    func testCheckDueAfterInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-90_000) // older than 86_400
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }

    func testNotDueWithinInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-1_000)
        XCTAssertFalse(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }

    func testDueAtExactInterval() {
        let now = Date(timeIntervalSinceReferenceDate: 200_000)
        let last = now.addingTimeInterval(-86_400)
        XCTAssertTrue(UpdateScheduler.isCheckDue(now: now, lastCheck: last, interval: 86_400))
    }

    // MARK: - shouldPrompt

    func testShouldPromptForNewNonSkippedVersion() {
        let r = UpdateChecker.CheckResult.updateAvailable(
            version: "1.13.0", url: URL(string: "https://example.com")!)
        XCTAssertTrue(UpdateScheduler.shouldPrompt(result: r, skippedVersion: nil))
        XCTAssertTrue(UpdateScheduler.shouldPrompt(result: r, skippedVersion: "1.12.0"))
    }

    func testNoPromptForSkippedVersion() {
        let r = UpdateChecker.CheckResult.updateAvailable(
            version: "1.13.0", url: URL(string: "https://example.com")!)
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: r, skippedVersion: "1.13.0"))
    }

    func testNoPromptForUpToDateOrFailed() {
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: .upToDate, skippedVersion: nil))
        XCTAssertFalse(UpdateScheduler.shouldPrompt(result: .failed(message: "x"), skippedVersion: nil))
    }

    // MARK: - updateAction

    func testActionForHomebrewIsBrewCommand() {
        let a = UpdateScheduler.updateAction(
            isHomebrew: true,
            releaseURL: URL(string: "https://example.com")!,
            brewCommand: "brew upgrade --cask cleanr")
        XCTAssertEqual(a, .brewCommand("brew upgrade --cask cleanr"))
    }

    func testActionForDMGIsOpenRelease() {
        let url = URL(string: "https://github.com/coldrazer/CleanR/releases/tag/v1.13.0")!
        let a = UpdateScheduler.updateAction(
            isHomebrew: false, releaseURL: url, brewCommand: "ignored")
        XCTAssertEqual(a, .openRelease(url))
    }
}
