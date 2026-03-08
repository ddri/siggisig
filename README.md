# SiggiSig

A macOS audio routing app that captures per-app audio and pipes it to virtual audio devices for use in DAWs.

Built with Swift, ScreenCaptureKit, and CoreAudio.

## Requirements

- macOS 15.0+ (Sequoia)
- [BlackHole 16ch](https://existential.audio/blackhole/)
- Xcode 16+

## Build & Run

```bash
swift build
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Usage

1. Launch SiggiSig
2. Complete the setup wizard (detects BlackHole, requests permissions)
3. Click an app in the left panel to route its audio
4. Each app gets assigned a stereo pair (Ch 1-2, Ch 3-4, etc.)
5. In your DAW, set input to the corresponding BlackHole channel pair
6. Record!

## Architecture

- **ScreenCaptureKit** captures per-app audio as `CMSampleBuffer`
- **AVAudioEngine** converts and routes audio buffers
- **BlackHole 16ch** provides the virtual audio device (up to 8 stereo apps)
- **SwiftUI** for the routing interface
