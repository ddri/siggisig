# SiggiSig

A native macOS audio routing utility that captures per-app audio and pipes it to virtual audio devices for isolated multi-track recording and monitoring in DAWs.

Built with Swift, SwiftUI, ScreenCaptureKit, and CoreAudio.

---

## Features

- **Per-App Audio Capture:** Route individual applications (Spotify, Discord, Chrome, Logic, etc.) directly without capturing unwanted system sounds.
- **Multi-Track Virtual Output:** Automatically assigns apps to discrete stereo pairs on [BlackHole 16ch](https://existential.audio/blackhole/) (up to 8 stereo channels).
- **Native Mixer Strips:**
  - dB-scaled volume faders with audio taper (-60 dB to +6 dB).
  - High-precision audio peak meters with peak hold.
  - Stereo pan controls (-1.0 to +1.0) with double-tap center reset.
  - Clickable channel assignment menus to swap BlackHole stereo slots on the fly.
- **Menu Bar Utility & Background Routing:**
  - Operates as a background macOS utility with a waveform menu bar extra.
  - Glanceable active route summary right in the menu bar.
  - Closing the mixer window (Cmd+W) hides the window while your audio routes continue running uninterrupted.
- **Session Persistence & Auto-Reconnect:**
  - Remembers routes, levels, pans, and channel slots across reboots (`~/Library/Application Support/SiggiSig/session.json`).
  - Automatically re-routes applications when they launch or quit.
- **Modern Resizable UI:** Flexible SwiftUI interface supporting custom window sizes and horizontal strip scrolling.

---

## Requirements

- macOS 15.0+ (Sequoia)
- [BlackHole 16ch](https://existential.audio/blackhole/) (virtual audio driver)
- Xcode 16+ & XcodeGen (`brew install xcodegen`)

---

## Quick Start

### 1. Run from Source

```bash
# Using SwiftPM
swift build
swift run

# Or open in Xcode
open Package.swift
```

### 2. Build & Package Distributable Release

Use the included release packaging script to build an optimized Release bundle and DMG:

```bash
# Builds dist/SiggiSig.app and dist/SiggiSig-1.0.0.dmg signed with your local certificate:
./scripts/package.sh

# Or sign with Developer ID and notarize with Apple:
./scripts/package.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize "AC_PROFILE"
```

To install, simply open `dist/SiggiSig-1.0.0.dmg` and drag SiggiSig to `/Applications`.

---

## DAW Setup Guide

1. **Configure Audio Device:**
   - In your DAW (Ableton Live, Logic Pro, Reaper, FL Studio, etc.), open **Audio Preferences**.
   - Set **Audio Input Device** to **BlackHole 16ch**.
2. **Enable Stereo Inputs:**
   - Enable stereo input pairs:
     - Input 1/2 (Channel 1-2)
     - Input 3/4 (Channel 3-4)
     - Input 5/6 (Channel 5-6)
     - ... up to Input 15/16.
3. **Route in SiggiSig:**
   - Launch SiggiSig and click an app in the left panel to route it.
   - Look at the channel badge (e.g. `Ch 1-2` or `Ch 3-4`).
4. **Arm DAW Tracks:**
   - Set Track 1 input to `Ext. In 1/2` for App 1.
   - Set Track 2 input to `Ext. In 3/4` for App 2.
   - Arm tracks and record isolated app streams!

---

## Architecture

- **ScreenCaptureKit** captures per-process audio as `CMSampleBuffer`.
- **AVAudioEngine** and **AVAudioMixerNode** handle fader gain, stereo panning, level metering, and multi-channel hardware output.
- **BlackHole 16ch** acts as the virtual multi-channel audio loopback bus.
- **CoreAudio Hardware Listeners** detect audio device connects/disconnects dynamically.
- **SwiftUI + AppKit** deliver the resizable mixer interface, setup wizard, and menu bar extra.

---

## License

MIT
