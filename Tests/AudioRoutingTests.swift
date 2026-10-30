@preconcurrency import AVFoundation
import Testing
@testable import SiggiSig

// Renders the engine graph offline (no BlackHole needed) to check that audio
// actually reaches the 16-channel output, and which channels it lands on.

private let chunkFrames: AVAudioFrameCount = 4096

@Test func testOutputFormatIsSixteenChannels() throws {
    let format = try #require(AudioCaptureEngine.makeOutputFormat())
    #expect(format.channelCount == 16)
    #expect(format.sampleRate == 48000)
}

/// A full-scale 440 Hz stereo chunk in the format ScreenCaptureKit delivers.
private func stereoTone(left: Float = 1, right: Float = 1) throws -> AVAudioPCMBuffer {
    let stereo = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    let tone = try #require(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: chunkFrames))
    tone.frameLength = chunkFrames
    for i in 0..<Int(chunkFrames) {
        let sample = sinf(Float(i) * 2 * .pi * 440 / 48000)
        tone.floatChannelData![0][i] = sample * left
        tone.floatChannelData![1][i] = sample * right
    }
    return tone
}

private func peaks(_ buffer: AVAudioPCMBuffer, frames: Range<Int>? = nil) -> [Float] {
    let range = frames ?? 0..<Int(buffer.frameLength)
    return (0..<Int(buffer.format.channelCount)).map { ch in
        range.reduce(Float(0)) { max($0, abs(buffer.floatChannelData![ch][$1])) }
    }
}

/// An offline engine with one route per entry, each fed `chunks` stereo chunks through the
/// same scheduling path the app uses. `beforeChunk` runs before each chunk is scheduled.
@MainActor
private func render(
    routes: [RouteParams],
    chunks: Int = 1,
    beforeChunk: (Int) -> Void = { _ in }
) throws -> AVAudioPCMBuffer {
    let engine = AVAudioEngine()
    let outputFormat = try #require(AudioCaptureEngine.makeOutputFormat())
    let totalFrames = chunkFrames * AVAudioFrameCount(chunks)
    try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: totalFrames)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)

    let players = try routes.map { _ in
        let player = AVAudioPlayerNode()
        try AudioCaptureEngine.connectRoute(player: player, mixer: AVAudioMixerNode(), in: engine)
        return player
    }

    let tone = try stereoTone()
    for chunk in 0..<chunks {
        beforeChunk(chunk)
        for (player, params) in zip(players, routes) {
            AudioCaptureEngine.schedule(tone, on: player, params: params)
        }
    }

    try engine.start()
    players.forEach { $0.play() }
    let output = try #require(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: totalFrames))
    #expect(try engine.renderOffline(totalFrames, to: output) == .success)
    engine.stop()
    return output
}

private func expectOnly(_ peaks: [Float], channels expected: Set<Int>) {
    for ch in 0..<16 {
        if expected.contains(ch) {
            #expect(peaks[ch] > 0.5, "Ch \(ch + 1) should carry signal")
        } else {
            #expect(peaks[ch] < 0.001, "Ch \(ch + 1) should be silent")
        }
    }
}

@Test @MainActor func testRouteLandsOnItsChannelPair() throws {
    let output = try render(routes: [RouteParams(slot: 3)])
    expectOnly(peaks(output), channels: [6, 7])
}

@Test @MainActor func testRoutesDoNotBleedIntoEachOther() throws {
    let output = try render(routes: [RouteParams(slot: 0), RouteParams(slot: 7)])
    expectOnly(peaks(output), channels: [0, 1, 14, 15])
}

@Test @MainActor func testReassigningSlotMovesLaterAudio() throws {
    let params = RouteParams(slot: 2)
    let output = try render(routes: [params], chunks: 2) { chunk in
        if chunk == 1 { params.slot = 5 }
    }
    let first = Int(chunkFrames)
    expectOnly(peaks(output, frames: 0..<first), channels: [4, 5])
    expectOnly(peaks(output, frames: first..<2 * first), channels: [10, 11])
}

@Test @MainActor func testHardLeftPanSilencesRight() throws {
    let output = try render(routes: [RouteParams(slot: 1, pan: -1)])
    expectOnly(peaks(output), channels: [2])
}

@Test func testPanCentreLeavesBothChannelsAtUnity() {
    let gains = AudioCaptureEngine.balanceGains(pan: 0)
    #expect(gains.left == 1 && gains.right == 1)
    let halfRight = AudioCaptureEngine.balanceGains(pan: 0.5)
    #expect(halfRight.left == 0.5 && halfRight.right == 1)
}

@Test func testMeterReadsOnlyTheRoutesPair() throws {
    let format = try #require(AudioCaptureEngine.makeOutputFormat())
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    for ch in 0..<16 {
        for i in 0..<4 { buffer.floatChannelData![ch][i] = 0 }
    }
    for i in 0..<4 {
        buffer.floatChannelData![8][i] = 0.5
        buffer.floatChannelData![9][i] = 0.5
    }
    let levels = try #require(AudioCaptureEngine.meterLevels(buffer, slot: 4))
    #expect(abs(levels.rms - 0.5) < 0.0001)  // not diluted by the 14 silent channels
    #expect(levels.peak == 0.5)
}

@Test @MainActor func testNon48kInputIsConvertedOntoItsPair() throws {
    let engine = AVAudioEngine()
    let outputFormat = try #require(AudioCaptureEngine.makeOutputFormat())
    try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: chunkFrames)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
    let player = AVAudioPlayerNode()
    try AudioCaptureEngine.connectRoute(player: player, mixer: AVAudioMixerNode(), in: engine)

    let format44 = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
    let tone = try #require(AVAudioPCMBuffer(pcmFormat: format44, frameCapacity: chunkFrames))
    tone.frameLength = chunkFrames
    for ch in 0..<2 {
        for i in 0..<Int(chunkFrames) { tone.floatChannelData![ch][i] = sinf(Float(i) * 2 * .pi * 440 / 44100) }
    }
    AudioCaptureEngine.schedule(tone, on: player, params: RouteParams(slot: 6))

    try engine.start()
    player.play()
    let output = try #require(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkFrames))
    #expect(try engine.renderOffline(chunkFrames, to: output) == .success)
    engine.stop()
    expectOnly(peaks(output), channels: [12, 13])
}
