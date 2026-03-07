# SiggiSig — Design Document

**Date:** 2026-03-08
**Target:** macOS 15 Sequoia+
**Language:** Swift / SwiftUI

## Purpose

A macOS app that captures per-app audio using ScreenCaptureKit and routes each app to separate stereo pairs on BlackHole 16ch, so DAWs like Ableton can record each source independently.

## Architecture

**Approach: ScreenCaptureKit → AVAudioEngine → BlackHole 16ch**

```
┌─────────────────────────────────────────────┐
│              SwiftUI App                     │
│  ┌─────────────┐  ┌──────────────────────┐  │
│  │ App Picker   │  │ Channel Assignment   │  │
│  └─────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────┤
│            Audio Engine Layer                │
│                                             │
│  SCStream ──▶ AVAudioPlayerNode ──▶ Mixer   │
│  (per app)    (per app)             Node    │
│                                      │      │
│                              BlackHole 16ch │
├─────────────────────────────────────────────┤
│           BlackHole 16ch                     │
│  Ch 1-2: App A  │  Ch 3-4: App B  │ ...    │
├─────────────────────────────────────────────┤
│           Ableton / DAW                      │
│  Track 1: BlackHole 1-2                      │
│  Track 2: BlackHole 3-4                      │
└─────────────────────────────────────────────┘
```

- Single shared `AVAudioEngine`, output set to BlackHole 16ch
- One `SCStream` per captured app (audio-only, no video)
- `SCStreamOutput` delegate receives `CMSampleBuffer`, converts to `AVAudioPCMBuffer`
- Each source feeds a dedicated `AVAudioPlayerNode` → `AVAudioMixerNode` → engine output
- Channel mapping routes each mixer node to a specific stereo pair on the 16ch output
- Engine runs continuously; individual streams start/stop as apps are added/removed

## Audio Format

- 48kHz sample rate
- 32-bit float (internal processing)
- Stereo per source
- DAW determines final bit depth on recording (e.g. 24-bit in Ableton)

## Latency

- ScreenCaptureKit: ~10-20ms capture latency
- AVAudioEngine: negligible
- Total: ~20ms — fine for recording

## App Picker & Process Discovery

- Query `NSWorkspace.shared.runningApplications` for GUI apps on launch
- Display as list with app icon + name
- Audio activity indicator via CoreAudio process tap APIs (green dot = producing audio, grey = silent)
- Selecting an app auto-assigns to next free stereo pair on BlackHole
- No persistence in v1 — fresh state each launch
- Manual channel assignment deferred to v2

## Permissions

- Screen Recording permission required (macOS prompt on first use)
- Audio-only capture, no video frames requested

## First-Launch Setup Wizard

1. Check for BlackHole 16ch via CoreAudio device query
2. If missing: show download link, "Refresh" button to re-check
3. Trigger Screen Recording permission prompt via test `SCStream`
4. Save completion flag; accessible from menu to re-run

## UI Layout

Single-window SwiftUI app:

- **Left panel:** Running apps with audio indicator dot. Click to add to routing.
- **Right panel:** Active routes showing app → channel pair. Click to remove.
- **Status bar:** Summary of active routing state.
- **Settings:** Re-run setup wizard, sample rate, about.

No menubar-only mode in v1.

## Edge Cases

- App quits while captured → detect via `NSWorkspace` notification, tear down stream, free channel pair
- BlackHole disconnected → detect device removal, pause engine, show alert
- Sample rate mismatch → AVAudioEngine handles conversion automatically
- Screen Recording denied → show instructions to enable in System Settings

## Testing Strategy

- **Unit tests:** Audio format conversion, channel mapping logic, app discovery filtering
- **Integration tests:** AVAudioEngine with test signal, verify correct channel output
- **Manual testing:** Play audio in browser, verify in Ableton on expected channel pair
- **Edge cases:** Kill captured app, disconnect BlackHole, deny permissions

## Future Versions

- **v2:** Volume/pan controls per source, persistent assignments, manual channel assignment
- **v3:** Full routing matrix, multiple output devices, menubar mode

## Not In v1

- Volume/pan controls
- Session persistence
- Manual channel assignment
- Menubar-only mode
- UI tests
