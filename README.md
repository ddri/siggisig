# SiggiSig

A macOS audio routing app that captures per-app audio and pipes it to virtual audio devices (like BlackHole) for use in DAWs.

Built with Swift, ScreenCaptureKit, and CoreAudio.

## Architecture

- **ScreenCaptureKit** for per-app audio capture
- **CoreAudio** for routing audio buffers to virtual devices
- **SwiftUI** for the routing GUI
- **BlackHole** as the virtual audio device layer

## Requirements

- macOS 13.0+ (Ventura)
- [BlackHole](https://existential.audio/blackhole/) virtual audio driver
- Xcode 15+
