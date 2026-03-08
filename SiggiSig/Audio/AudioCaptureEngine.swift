@preconcurrency import AVFoundation
import CoreAudio

@MainActor
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var activeStreams: [pid_t: ManagedStream] = [:]
    private let maxStereoSlots = 8  // BlackHole 16ch = 8 stereo pairs
    private let audioQueue = DispatchQueue(label: "com.siggisig.audio-scheduling", qos: .userInteractive)

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

        // Connect mainMixerNode to outputNode with explicit 16-channel format
        let format16ch = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 16)!
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format16ch)

        engine.prepare()
        try engine.start()
    }

    func startCapture(for app: CaptureApp) async throws -> Int {
        if let existing = activeStreams[app.id] {
            return existing.channelSlot
        }

        guard let slot = nextFreeSlot() else {
            throw AudioCaptureError.noSlotsAvailable
        }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)

        // Connect player to mainMixerNode with stereo format
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: stereoFormat)

        // Set channel map: route stereo input to the correct pair in 16ch output
        let channelMap = makeChannelMap(slot: slot, totalChannels: 16)
        playerNode.auAudioUnit.channelMap = channelMap

        playerNode.play()

        nonisolated(unsafe) let node = playerNode
        let queue = self.audioQueue
        let weakSelf = self
        let appStream = AppAudioStream(app: app) { buffer, format in
            queue.async { [weak weakSelf] in
                weakSelf?.scheduleBuffer(buffer, format: format, on: node)
            }
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
        let node = managed.playerNode
        let eng = self.engine
        audioQueue.sync {
            node.stop()
            eng.detach(node)
        }
    }

    func stopAll() async {
        for (_, managed) in activeStreams {
            await managed.appStream.stop()
            let node = managed.playerNode
            let eng = self.engine
            audioQueue.sync {
                node.stop()
                eng.detach(node)
            }
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

    private nonisolated func scheduleBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, on playerNode: AVAudioPlayerNode) {
        // Called on audioQueue
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
