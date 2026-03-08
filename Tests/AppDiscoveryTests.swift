import Testing
@testable import SiggiSig

@Test func testDiscoverRunningApps() {
    let apps = AppDiscovery.runningApps()
    #expect(!apps.isEmpty, "Should find running GUI apps")
}

@Test func testAppsHaveBundleIdentifier() {
    let apps = AppDiscovery.runningApps()
    for app in apps {
        #expect(app.bundleIdentifier != nil, "\(app.name) should have a bundle ID")
    }
}
