import XCTest
@testable import RecordItApp

final class TeleprompterTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    func testUsesTheAppLaunchServicesKnowsByBundleIdentifier() {
        let registered = URL(fileURLWithPath: "/Applications/Telemprompit.app")

        let url = teleprompterAppURL(
            urlForBundleIdentifier: { $0 == teleprompterBundleIdentifier ? registered : nil },
            fileExists: { _ in true },
            homeDirectory: home
        )

        XCTAssertEqual(url, registered)
    }

    func testFallsBackToTheStagedAppInTheUsersApplicationsFolder() {
        let url = teleprompterAppURL(
            urlForBundleIdentifier: { _ in nil },
            fileExists: { $0 == "/Users/someone/Applications/Telemprompit.app" },
            homeDirectory: home
        )

        XCTAssertEqual(url?.path, "/Users/someone/Applications/Telemprompit.app")
    }

    func testFindsNothingWhenTelemprompitIsNotInstalled() {
        XCTAssertNil(teleprompterAppURL(
            urlForBundleIdentifier: { _ in nil },
            fileExists: { _ in false },
            homeDirectory: home
        ))
    }
}
