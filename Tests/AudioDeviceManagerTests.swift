import Testing
@testable import SiggiSig

@Test func testListAudioDevices() {
    let devices = AudioDeviceManager.listOutputDevices()
    #expect(!devices.isEmpty, "Should find at least one output device")
}

@Test func testDeviceHasNameAndID() {
    let devices = AudioDeviceManager.listOutputDevices()
    guard let first = devices.first else {
        Issue.record("No devices found")
        return
    }
    #expect(!first.name.isEmpty)
    #expect(first.id != 0)
}
