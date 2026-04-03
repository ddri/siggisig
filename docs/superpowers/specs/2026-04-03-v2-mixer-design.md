# SiggiSig v2 Design: Volume Controls, Meters, Session Persistence

## Overview

Three features that transform the right side of the UI from a static channel list into a functional mixer strip view, plus session persistence across launches.

## Feature 1: Volume Controls

- Vertical faders per active route, mixer-console style
- Range: -∞ to +6dB (silent to slight boost), default 0dB
- Applied as gain on the `AVAudioPlayerNode` before it hits BlackHole
- Fader position persisted as part of session save

## Feature 2: Visual Audio Meters

- Gradient bar with peak hold, per route, next to the fader
- Green → yellow → red gradient
- Peak indicator sticks for ~2 seconds then decays
- Driven by tapping audio levels from the player node (~60fps update)
- Meter shows post-fader level (what's actually going to the DAW)

## Feature 3: Session Persistence

- Save active routes to a JSON file (`~/Library/Application Support/SiggiSig/session.json`)
- Stores: bundle ID, app name, channel slot, volume level
- On launch: restore saved routes, auto-connect running apps
- Greyed-out strips for saved apps not currently running
- Auto-connect when a saved app launches (detected by existing workspace observer)
- Session auto-saves on every route change (add/remove/volume)

## Layout Change

- Right side becomes mixer strip view
- Each strip: app icon, name, vertical meter, vertical fader, channel label
- Only shows active + saved routes (no empty slots)
- Greyed-out for saved-but-not-running apps
- "X of 8 channels free" indicator at bottom
- Left side (app picker) stays the same

## Architecture

### Modified Files

- `AudioCaptureEngine`: add gain control API (`setVolume(for:volume:)`), add level metering tap on each player node
- `RouterState` / `Route`: add `volume: Float` property (default 0.0 dB)
- `RouterViewModel`: integrate session restore/save, volume changes, meter level updates
- `ActiveRoutesView` → replaced by new `MixerView`

### New Files

- `SessionStore`: handles JSON read/write to `~/Library/Application Support/SiggiSig/session.json`
- `MixerStripView`: single channel strip SwiftUI view (meter + fader + label)
- `MixerView`: collection of `MixerStripView` strips with available-slots indicator

### Data Flow

```
App audio → ScreenCaptureKit → AVAudioPlayerNode
                                    ↓
                              gain (fader) applied
                                    ↓
                              level tap (meter reading)
                                    ↓
                              AVAudioEngine mainMixerNode → BlackHole 16ch → DAW
```

### Session JSON Format

```json
{
  "routes": [
    {
      "bundleID": "com.spotify.client",
      "appName": "Spotify",
      "channelSlot": 0,
      "volume": 0.0
    }
  ]
}
```

### Session Restore Flow

1. On launch, read `session.json`
2. For each saved route, reserve the channel slot in `RouterState`
3. Check which saved apps are currently running (match by bundle ID)
4. For running apps: start audio capture immediately
5. For non-running apps: show greyed-out strip, watch for app launch via workspace observer
6. When a saved app launches: auto-start capture on its reserved slot

## What's NOT Changing

- Left side app picker UI
- Setup wizard flow
- Audio capture engine core (ScreenCaptureKit → AVAudioEngine → BlackHole)
- Channel assignment logic (still auto-assigns next free slot)
- Package.swift / Xcode project structure
- Unit test targets
