import Testing
@testable import SiggiSig

@Test func testInitialStateEmpty() {
    let state = RouterState()
    #expect(state.routes.isEmpty)
    #expect(state.availableSlots == 8)
}

@Test func testAddRoute() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    #expect(state.routes.count == 1)
    #expect(state.routes[0].appName == "Chrome")
    #expect(state.routes[0].channelPair == "Ch 1-2")
    #expect(state.availableSlots == 7)
}

@Test func testRemoveRoute() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    state.removeRoute(pid: 123)
    #expect(state.routes.isEmpty)
    #expect(state.availableSlots == 8)
}

@Test func testChannelPairLabels() {
    #expect(Route.channelPairLabel(for: 0) == "Ch 1-2")
    #expect(Route.channelPairLabel(for: 1) == "Ch 3-4")
    #expect(Route.channelPairLabel(for: 7) == "Ch 15-16")
}

@Test func testRouteDefaultVolume() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    #expect(state.routes[0].volume == 0.0)
}

@Test func testSetVolume() {
    var state = RouterState()
    state.addRoute(appName: "Chrome", bundleID: "com.google.Chrome", pid: 123, slot: 0)
    state.setVolume(pid: 123, volume: -6.0)
    #expect(state.routes[0].volume == -6.0)
}
