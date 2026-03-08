import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum AudioCaptureError: Error, LocalizedError {
    case appNotFound
    case blackHoleNotFound
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .appNotFound: "Application not found for capture"
        case .blackHoleNotFound: "BlackHole 16ch not found. Please install it."
        case .engineStartFailed: "Failed to start audio engine"
        }
    }
}

final class AppAudioStream: NSObject, @unchecked Sendable, SCStreamOutput {
    let app: CaptureApp
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioFormat) -> Void)?

    private var stream: SCStream?

    init(app: CaptureApp) {
        self.app = app
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let scApp = content.applications.first(where: { $0.processID == app.id }) else {
            throw AudioCaptureError.appNotFound
        }

        guard let display = content.displays.first else {
            throw AudioCaptureError.appNotFound
        }

        let appFilter = SCContentFilter(
            display: display,
            including: [scApp],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Minimize video overhead — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        stream = SCStream(filter: appFilter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame
        ) else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        onAudioBuffer?(pcmBuffer, format)
    }
}
