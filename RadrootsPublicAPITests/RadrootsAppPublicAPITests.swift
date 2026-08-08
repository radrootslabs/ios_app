import RadrootsApp
import SwiftUI
import UIKit
import XCTest

final class RadrootsAppPublicAPITests: XCTestCase {
    @MainActor
    func testSupportedPublicSurfaceCompilesForAnExternalConsumer() {
        XCTAssertEqual(RadrootsAppRelease.version, "0.1.0-alpha")
        let appView: any View = RadrootsAppView()
        let appDelegate: any UIApplicationDelegate = RadrootsAppDelegate()
        _ = appView
        _ = appDelegate
    }
}
