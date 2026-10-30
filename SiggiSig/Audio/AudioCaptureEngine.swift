@preconcurrency import AVFoundation
import CoreAudio
import os

struct MeterLevels: Sendable, Equatable {
    let rms: Float      // 0.0 to 1.0
    let peak: Float     // 0.0 to 1.0
}

/// Channel slot and pan for one route. Written on the main actor, read on the audio
/// scheduling queue and in the meter tap, so access goes through a lock.
final class RouteParams: Sendable {
    private let state: OSAllocatedUnfairLock<(slot: Int, pan: Float)>

    init(slot: Int, pan: Float = 0) {
        state = OSAllocatedUnfairLock(initialState: (slot, pan))
    }

    var slot: Int {
        get { state.withLock { $0.slot } }
        set { state.withLock { $0.slot = newValue } }
    }

    var pan: Float {
        get { state.withLock { $0.pan } }
        set { state.withLock { $0.pan = newValue } }
    }
}

@MainActor
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var activeStreams: [pid_t: ManagedStream] = [:]
    nonisolated static let maxStereoSlots = 8  // BlackHole 16ch = 8 stereo pairs
    private let audioQueue = DispatchQueue(label: "com.siggisig.audio-scheduling", qos: .userInteractive)
    private var meterCallbacks: [pid_t: @Sendable (MeterLevels) -> Void] = [:]

    private struct ManagedStream {
        let appStream: AppAudioStream
        let playerNode: AVAudioPlayerNode
        let routeMixer: AVAudioMixerNode
        let params: RouteParams
        var channelSlot: Int { params.slot }  // 0-7, maps to stereo pair
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
        guard let format16ch = Self.makeOutputFormat() else {
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
        if let preferred = preferredSlot,
           (0..<Self.maxStereoSlots).contains(preferred),
           !activeStreams.values.contains(where: { $0.channelSlot == preferred }) {
            slot = preferred
        } else {
            guard let freeSlot = nextFreeSlot() else {
                throw AudioCaptureError.noSlotsAvailable
            }
            slot = freeSlot
        }

        let playerNode = AVAudioPlayerNode()
        let routeMixer = AVAudioMixerNode()
        try Self.connectRoute(player: playerNode, mixer: routeMixer, in: engine)
        let params = RouteParams(slot: slot)

        playerNode.play()

        // AVAudioPlayerNode isn't Sendable; it's only used for scheduleBuffer on audioQueue.
        nonisolated(unsafe) let node = playerNode
        let queue = self.audioQueue
        let appStream = AppAudioStream(app: app) { buffer, _ in
            queue.async {
                Self.schedule(buffer, on: node, params: params)
            }
        }

        try await appStream.start()

        activeStreams[app.id] = ManagedStream(
            appStream: appStream,
            playerNode: playerNode,
            routeMixer: routeMixer,
            params: params
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

    var usedSlots: Set<Int> {
        Set(activeStreams.values.map(\.channelSlot))
    }

    func reassignChannel(for app: CaptureApp, to newSlot: Int) {
        guard (0..<Self.maxStereoSlots).contains(newSlot) else { return }
        // Takes effect from the next captured chunk; the graph is left untouched.
        activeStreams[app.id]?.params.slot = newSlot
    }

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

    func setPan(for app: CaptureApp, pan: Float) {
        guard let managed = activeStreams[app.id] else { return }
        // AVAudioMixerNode.pan has no effect on a 16-channel input; balance is applied in schedule().
        managed.params.pan = pan
    }

    func installMeterTap(for app: CaptureApp, callback: @escaping @Sendable (MeterLevels) -> Void) {
        guard let managed = activeStreams[app.id] else { return }
        meterCallbacks[app.id] = callback

        let params = managed.params
        let bufferSize: AVAudioFrameCount = 1024
        managed.routeMixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            if let levels = Self.meterLevels(buffer, slot: params.slot) {
                callback(levels)
            }
        }
    }

    /// RMS and peak of the route's own channel pair in a 16-channel buffer. Measuring all
    /// 16 channels would dilute the RMS with the 14 silent ones.
    nonisolated static func meterLevels(_ buffer: AVAudioPCMBuffer, slot: Int) -> MeterLevels? {
        guard let channelData = buffer.floatChannelData,
              slot >= 0, slot * 2 + 1 < Int(buffer.format.channelCount) else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        var rmsSum: Float = 0.0
        var peak: Float = 0.0
        for ch in [slot * 2, slot * 2 + 1] {
            let samples = channelData[ch]
            for i in 0..<frameLength {
                rmsSum += samples[i] * samples[i]
                peak = max(peak, abs(samples[i]))
            }
        }

        let rms = sqrtf(rmsSum / Float(frameLength * 2))
        // Clamp to 0...1
        return MeterLevels(rms: min(rms, 1.0), peak: min(peak, 1.0))
    }

    func removeMeterTap(for app: CaptureApp) {
        guard let managed = activeStreams[app.id] else { return }
        managed.routeMixer.removeTap(onBus: 0)
        meterCallbacks.removeValue(forKey: app.id)
    }

    // MARK: - Graph construction

    /// The 16-channel format feeding BlackHole. Formats above 2 channels need an explicit
    /// layout: `AVAudioFormat(standardFormatWithSampleRate:channels: 16)` returns nil.
    nonisolated static func makeOutputFormat(sampleRate: Double = 48000) -> AVAudioFormat? {
        guard let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 16) else {
            return nil
        }
        return AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
    }

    /// Attaches and connects playerNode → routeMixer → mainMixerNode, 16 channels wide.
    /// Each route places its own audio on its channel pair (see schedule()), so the
    /// mixers just sum discrete channels.
    static func connectRoute(player: AVAudioPlayerNode, mixer: AVAudioMixerNode, in engine: AVAudioEngine) throws {
        guard let format = makeOutputFormat() else {
            throw AudioCaptureError.engineStartFailed
        }
        engine.attach(player)
        engine.attach(mixer)
        engine.connect(player, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
    }

    /// Copies a captured stereo chunk onto the route's channel pair of a 16-channel buffer,
    /// with balance applied, and schedules it. Called on audioQueue.
    nonisolated static func schedule(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode, params: RouteParams) {
        let slot = params.slot
        let gains = balanceGains(pan: params.pan)
        guard (0..<maxStereoSlots).contains(slot),
              let stereo = convertToStereo(buffer),
              let outputFormat = makeOutputFormat(),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: stereo.frameLength),
              let src = stereo.floatChannelData,
              let dst = output.floatChannelData else { return }

        let frames = Int(stereo.frameLength)
        output.frameLength = stereo.frameLength
        for ch in 0..<Int(outputFormat.channelCount) {
            dst[ch].update(repeating: 0, count: frames)
        }
        for i in 0..<frames {
            dst[slot * 2][i] = src[0][i] * gains.left
            dst[slot * 2 + 1][i] = src[1][i] * gains.right
        }
        player.scheduleBuffer(output)
    }

    /// Balance for a stereo source: centre leaves both sides at unity, and moving towards
    /// one side turns the other down (-1 = left only, +1 = right only).
    nonisolated static func balanceGains(pan: Float) -> (left: Float, right: Float) {
        let pan = max(-1, min(1, pan))
        return (min(1, 1 - pan), min(1, 1 + pan))
    }

    // MARK: - Private

    private func nextFreeSlot() -> Int? {
        let usedSlots = Set(activeStreams.values.map(\.channelSlot))
        return (0..<Self.maxStereoSlots).first { !usedSlots.contains($0) }
    }

    /// ScreenCaptureKit is configured for 48 kHz stereo float, so this is normally a no-op.
    private nonisolated static func convertToStereo(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return nil }
        if buffer.format == stereo { return buffer }

        guard let converter = AVAudioConverter(from: buffer.format, to: stereo) else { return nil }
        let ratio = stereo.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: capacity) else { return nil }

        // Supply the input once, then report no more data so the converter doesn't loop on it.
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? converted : nil
    }
}
