@testable import RadrootsApp
import XCTest

final class RadrootsRootShellTests: XCTestCase {
    func testRootInventoryIsExactlyTodayThenAdd() {
        XCTAssertEqual(RadrootsRootTab.allCases.map(\.rawValue), ["today", "add"])
    }

    func testRestorationFailsClosedToToday() {
        XCTAssertEqual(RadrootsRootTab.resolve(nil), .today)
        XCTAssertEqual(RadrootsRootTab.resolve("capture"), .today)
        XCTAssertEqual(RadrootsRootTab.resolve("activity"), .today)
        XCTAssertEqual(RadrootsRootTab.resolve("settings"), .today)
    }

    func testDeepLinksCanSelectOnlyRootTabs() throws {
        XCTAssertEqual(
            try RadrootsRootTab.resolve(url: XCTUnwrap(URL(string: "radroots://today"))),
            .today
        )
        XCTAssertEqual(
            try RadrootsRootTab.resolve(url: XCTUnwrap(URL(string: "radroots://add"))),
            .add
        )
        for removed in ["capture", "activity", "settings", "search", "me"] {
            XCTAssertNil(
                try RadrootsRootTab.resolve(
                    url: XCTUnwrap(URL(string: "radroots://\(removed)"))
                )
            )
        }
    }
}
