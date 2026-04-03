@preconcurrency import AVFoundation
import CoreAudio

struct MeterLevels: Sendable {
    let rms: Float      // 0.0 to 1.0
    let peak: Float     // 0.0 to 1.0
}

@MainActor
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var activeStreams: [pid_t: ManagedStream] = [:]
    private let maxStereoSlots = 8  // BlackHole 16ch = 8 stereo pairs
    private let audioQueue = DispatchQueue(label: "com.siggisig.audio-scheduling", qos: .userInteractive)
    private var meterCallbacks: [pid_t: @Sendable (MeterLevels) -> Void] = [:]

    private struct ManagedStream {
        let appStream: AppAudioStream
        let playerNode: AVAudioPlayerNode
        let routeMixer: AVAudioMixerNode
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
        guard let format16ch = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 16) else {
            throw AudioCaptureError.engineStartFailed
        }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format16ch)

        engine.prepare()
        try engine.start()
    }

    func startCapture(for app: CaptureApp, preferredSlot: Int? = nil) async throws -> Int {
        if let existing = activeStreams[app.id] {
            return existing.channelSlot
        }

        let slot: Int
        if let preferred = preferredSlot, !activeStreams.values.contains(where: { $0.channelSlot == preferred }) {
            slot = preferred
        } else {
            guard let freeSlot = nextFreeSlot() else {
                throw AudioCaptureError.noSlotsAvailable
            }
            slot = freeSlot
        }

        let playerNode = AVAudioPlayerNode()
        let routeMixer = AVAudioMixerNode()
        engine.attach(playerNode)
        engine.attach(routeMixer)

        // Connect: playerNode → routeMixer → mainMixerNode
        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw AudioCaptureError.engineStartFailed
        }
        engine.connect(playerNode, to: routeMixer, format: stereoFormat)
        engine.connect(routeMixer, to: engine.mainMixerNode, format: stereoFormat)

        // Set channel map on routeMixer to route stereo to correct pair in 16ch output
        let channelMap = makeChannelMap(slot: slot, totalChannels: 16)
        routeMixer.auAudioUnit.channelMap = channelMap

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
            routeMixer: routeMixer,
            channelSlot: slot
        )

        return slot
    }

    func stopCapture(for app: CaptureApp) async {
        guard let managed = activeStreams.removeValue(forKey: app.id) else { return }
        meterCallbacks.removeValue(forKey: app.id)
        await managed.appStream.stop()
        let node = managed.playerNode
        let mixer = managed.routeMixer
        let eng = self.engine
        audioQueue.sync {
            mixer.removeTap(onBus: 0)
            node.stop()
            eng.detach(node)
            eng.detach(mixer)
        }
    }

    func stopAll() async {
        meterCallbacks.removeAll()
        for (_, managed) in activeStreams {
            await managed.appStream.stop()
            let node = managed.playerNode
            let mixer = managed.routeMixer
            let eng = self.engine
            audioQueue.sync {
                mixer.removeTap(onBus: 0)
                node.stop()
                eng.detach(node)
                eng.detach(mixer)
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

    /// Convert dB value to linear gain with audio taper.
    /// Range: -∞ (silent) to +6dB (≈2.0 linear)
    private func dbToLinear(_ db: Float) -> Float {
        if db <= -60.0 { return 0.0 }
        return powf(10.0, db / 20.0)
    }

    func setVolume(for app: CaptureApp, db: Float) {
        guard let managed = activeStreams[app.id] else { return }
        managed.routeMixer.outputVolume = dbToLinear(db)
    }

    func installMeterTap(for app: CaptureApp, callback: @escaping @Sendable (MeterLevels) -> Void) {
        guard let managed = activeStreams[app.id] else { return }
        meterCallbacks[app.id] = callback

        let bufferSize: AVAudioFrameCount = 1024
        managed.routeMixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            var rmsSum: Float = 0.0
            var peak: Float = 0.0
            let channelCount = Int(buffer.format.channelCount)

            for ch in 0..<channelCount {
                let samples = channelData[ch]
                for i in 0..<frameLength {
                    let sample = abs(samples[i])
                    rmsSum += samples[i] * samples[i]
                    if sample > peak { peak = sample }
                }
            }

            let totalSamples = Float(frameLength * channelCount)
            let rms = sqrtf(rmsSum / totalSamples)

            // Clamp to 0...1
            let clampedRMS = min(rms, 1.0)
            let clampedPeak = min(peak, 1.0)

            callback(MeterLevels(rms: clampedRMS, peak: clampedPeak))
        }
    }

    func removeMeterTap(for app: CaptureApp) {
        guard let managed = activeStreams[app.id] else { return }
        managed.routeMixer.removeTap(onBus: 0)
        meterCallbacks.removeValue(forKey: app.id)
    }

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
