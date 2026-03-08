import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
    let channelCount: Int
}

enum AudioDeviceManager {
    static func listOutputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard let name = getDeviceName(deviceID),
                  let channelCount = getOutputChannelCount(deviceID),
                  channelCount > 0 else { return nil }
            return AudioDevice(id: deviceID, name: name, channelCount: channelCount)
        }
    }

    static func findDevice(named targetName: String) -> AudioDevice? {
        listOutputDevices().first { $0.name.contains(targetName) }
    }

    private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        ) == noErr, let cfName = name?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    private static func getOutputChannelCount(_ deviceID: AudioDeviceID) -> Int? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return nil }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer
        ) == noErr else { return nil }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
