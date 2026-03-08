@preconcurrency import AVFoundation
import CoreAudio

final class AudioCaptureEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var activeStreams: [pid_t: ManagedStream] = [:]
    private let maxStereoSlots = 8  // BlackHole 16ch = 8 stereo pairs

    private struct ManagedStream {
        let appStream: AppAudioStream
        let playerNode: AVAudioPlayerNode
        let channelSlot: Int  // 0-7, maps to stereo pair
    }

    var blackHoleDevice: AudioDevice? {
        AudioDeviceManager.findDevice(named: "BlackHole 16ch")
    }

    func setup() throws {
        guard let device = blackHoleDevice else {
            throw AudioCaptureError.blackHoleNotFound
        }

        // Set AVAudioEngine output to BlackHole
        let outputNode = engine.outputNode
        guard let audioUnit = outputNode.audioUnit else {
            throw AudioCaptureError.engineStartFailed
        }

        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.engineStartFailed
        }

        engine.prepare()
        try engine.start()
    }

    func startCapture(for app: CaptureApp) async throws -> Int {
        if let existing = activeStreams[app.id] {
            return existing.channelSlot
        }

        guard let slot = nextFreeSlot() else {
            throw AudioCaptureError.engineStartFailed
        }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        // Connect player to output with channel mapping
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        // Set channel map: route to the correct stereo pair
        let channelMap = makeChannelMap(slot: slot, totalChannels: 16)
        playerNode.auAudioUnit.channelMap = channelMap

        playerNode.play()

        let appStream = AppAudioStream(app: app)
        nonisolated(unsafe) let node = playerNode
        appStream.onAudioBuffer = { [weak self] buffer, format in
            self?.scheduleBuffer(buffer, format: format, on: node)
        }

        try await appStream.start()

        activeStreams[app.id] = ManagedStream(
            appStream: appStream,
            playerNode: playerNode,
            channelSlot: slot
        )

        return slot
    }

    func stopCapture(for app: CaptureApp) async {
        guard let managed = activeStreams.removeValue(forKey: app.id) else { return }
        await managed.appStream.stop()
        managed.playerNode.stop()
        engine.detach(managed.playerNode)
    }

    func stopAll() async {
        for (_, managed) in activeStreams {
            await managed.appStream.stop()
            managed.playerNode.stop()
            engine.detach(managed.playerNode)
        }
        activeStreams.removeAll()
        engine.stop()
    }

    func isCapturing(_ app: CaptureApp) -> Bool {
        activeStreams[app.id] != nil
    }

    func channelSlot(for app: CaptureApp) -> Int? {
        activeStreams[app.id]?.channelSlot
    }

    var activeAppCount: Int { activeStreams.count }

    // MARK: - Private

    private func nextFreeSlot() -> Int? {
        let usedSlots = Set(activeStreams.values.map(\.channelSlot))
        return (0..<maxStereoSlots).first { !usedSlots.contains($0) }
    }

    private func makeChannelMap(slot: Int, totalChannels: Int) -> [NSNumber] {
        // Map stereo input (ch 0,1) to output channels (slot*2, slot*2+1)
        // -1 means "no audio on this channel"
        var map = [NSNumber](repeating: -1, count: totalChannels)
        map[slot * 2] = 0      // left channel
        map[slot * 2 + 1] = 1  // right channel
        return map
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, on playerNode: AVAudioPlayerNode) {
        // Convert format if needed
        let outputFormat = playerNode.outputFormat(forBus: 0)
        if format == outputFormat {
            playerNode.scheduleBuffer(buffer)
        } else if let converter = AVAudioConverter(from: format, to: outputFormat) {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: buffer.frameCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if error == nil {
                playerNode.scheduleBuffer(convertedBuffer)
            }
        }
    }
}
