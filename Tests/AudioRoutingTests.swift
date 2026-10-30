@preconcurrency import AVFoundation
import Testing
@testable import SiggiSig

// Renders the engine graph offline (no BlackHole needed) to check that audio
// actually reaches the 16-channel output, and which channels it lands on.

@Test func testOutputFormatIsSixteenChannels() throws {
    let format = try #require(AudioCaptureEngine.makeOutputFormat())
    #expect(format.channelCount == 16)
    #expect(format.sampleRate == 48000)
}

/// Per-channel peak level after rendering a full-scale stereo tone through a route on `slot`.
@MainActor
private func renderPeaks(slot: Int) throws -> [Float] {
    let engine = AVAudioEngine()
    let outputFormat = try #require(AudioCaptureEngine.makeOutputFormat())
    try engine.enableManualRenderingMode(.offline, format: outputFormat, maximumFrameCount: 4096)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)

    let player = AVAudioPlayerNode()
    let mixer = AVAudioMixerNode()
    try AudioCaptureEngine.connectRoute(player: player, mixer: mixer, slot: slot, in: engine)

    let stereo = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
    let tone = try #require(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4096))
    tone.frameLength = 4096
    for ch in 0..<2 {
        for i in 0..<4096 {
            tone.floatChannelData![ch][i] = sinf(Float(i) * 2 * .pi * 440 / 48000)
        }
    }

    try engine.start()
    player.scheduleBuffer(tone)
    player.play()

    let output = try #require(AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096))
    let status = try engine.renderOffline(4096, to: output)
    #expect(status == .success)
    engine.stop()

    return (0..<16).map { ch in
        (0..<Int(output.frameLength)).reduce(Float(0)) { max($0, abs(output.floatChannelData![ch][$1])) }
    }
}

@Test @MainActor func testRouteProducesOutput() throws {
    let peaks = try renderPeaks(slot: 0)
    #expect(peaks.max()! > 0.1, "no signal reached the 16-channel output")
}

@Test @MainActor func testRouteLandsOnItsChannelPair() throws {
    let slot = 3
    let peaks = try renderPeaks(slot: slot)
    // Known issue: channelMap has no effect on AVAudioMixerNode, so every route
    // is mixed onto channels 1-2. Remove withKnownIssue once routing is redesigned.
    withKnownIssue("per-slot channel routing is not implemented") {
        for ch in 0..<16 {
            if ch == slot * 2 || ch == slot * 2 + 1 {
                #expect(peaks[ch] > 0.1, "Ch \(ch + 1) should carry the route")
            } else {
                #expect(peaks[ch] < 0.001, "Ch \(ch + 1) should be silent")
            }
        }
    }
}
