import Foundation
import Testing
@testable import SiggiSig

@Test func testSaveAndLoadSession() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = SessionStore(directory: tempDir)
    let routes = [
        SavedRoute(bundleID: "com.spotify.client", appName: "Spotify", channelSlot: 0, volume: 0.0),
        SavedRoute(bundleID: "com.google.Chrome", appName: "Chrome", channelSlot: 1, volume: -6.0),
    ]
    try store.save(routes: routes)

    let loaded = try store.load()
    #expect(loaded.count == 2)
    #expect(loaded[0].bundleID == "com.spotify.client")
    #expect(loaded[0].volume == 0.0)
    #expect(loaded[1].bundleID == "com.google.Chrome")
    #expect(loaded[1].volume == -6.0)
}

@Test func testLoadReturnsEmptyWhenNoFile() {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let store = SessionStore(directory: tempDir)
    let loaded = try? store.load()
    #expect(loaded == nil || loaded!.isEmpty)
}
