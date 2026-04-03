# SiggiSig v2 Design: Volume Controls, Meters, Session Persistence

## Overview

Three features that transform the right side of the UI from a static channel list into a functional mixer strip view, plus session persistence across launches.

## Feature 1: Volume Controls

- Vertical faders per active route, mixer-console style
- Range: -∞ to +6dB (silent to slight boost), default 0dB
- **Audio taper curve**: UI slider position (0.0–1.0) is mapped through a logarithmic/exponential curve before being applied as the `AVAudioPlayerNode` volume multiplier. This ensures the fader feels natural to human hearing — a linear slider-to-volume mapping would put 90% of perceived loudness change in the bottom 20% of the fader throw.
- Fader position persisted as part of session save

## Feature 2: Visual Audio Meters

- Gradient bar with peak hold, per route, next to the fader
- Green → yellow → red gradient
- Peak indicator sticks for ~2 seconds then decays
- Meter shows post-fader level (what's actually going to the DAW)

### Node Topology for Metering

Tapping an `AVAudioPlayerNode` directly yields pre-fader buffer data. To get accurate post-fader readings, insert a dedicated `AVAudioMixerNode` per route:

```
AVAudioPlayerNode → RouteMixerNode → mainMixerNode → BlackHole
                         ↑
                    fader gain applied here
                    meter tap installed here
```

- Apply fader volume to the `RouteMixerNode` (not the player node)
- Install `installTap(on:bufferSize:format:block:)` on the `RouteMixerNode` output
- **Threading**: the tap block runs on a real-time audio thread — do minimal work. Calculate RMS and peak values from the buffer, then dispatch to main actor for UI update. No allocations in the tap block.

## Feature 3: Session Persistence

- Save active routes to a JSON file (`~/Library/Application Support/SiggiSig/session.json`)
- Stores: bundle ID, app name, channel slot, volume level
- On launch: restore saved routes, auto-connect running apps
- Greyed-out strips for saved apps not currently running
- Auto-connect when a saved app launches (detected by existing workspace observer)
- **Debounced auto-save**: session saves are debounced with ~0.5 second delay after the last change. This prevents disk thrashing during fader drags, which can fire hundreds of state changes per second.

## Layout Change

- Right side becomes mixer strip view
- Each strip: app icon, name, vertical meter, vertical fader, channel label
- Only shows active + saved routes (no empty slots)
- Greyed-out for saved-but-not-running apps
- "X of 8 channels free" indicator at bottom
- Left side (app picker) stays the same

## Architecture

### Modified Files

- `AudioCaptureEngine`:
  - `ManagedStream` gains a `routeMixer: AVAudioMixerNode` field
  - New node chain: playerNode → routeMixer → mainMixerNode
  - `setVolume(for:volume:)`: applies audio-tapered gain to the route mixer node
  - `installMeterTap(for:callback:)`: installs tap on route mixer, returns RMS/peak via callback
  - `removeMeterTap(for:)`: removes tap on stop
- `RouterState` / `Route`: add `volume: Float` property (default 0.0 dB)
- `RouterViewModel`: integrate session restore/save, volume changes, meter level updates
- `ActiveRoutesView` → replaced by new `MixerView`

### New Files

- `SessionStore`: handles JSON read/write to `~/Library/Application Support/SiggiSig/session.json`, with debounced save
- `MixerStripView`: single channel strip SwiftUI view (meter + fader + label)
- `MixerView`: collection of `MixerStripView` strips with available-slots indicator

### Data Flow

```
App audio → ScreenCaptureKit → AVAudioPlayerNode
                                    ↓
                              RouteMixerNode (per-route)
                                ├── fader gain applied
                                └── meter tap installed
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
7. **Delayed auto-connect**: when a saved app is detected launching, wait briefly (~1 second) before hooking ScreenCaptureKit, as the app's audio engine may not be initialized at the instant `didLaunchApplicationNotification` fires

### Sample Rate Handling (existing)

ScreenCaptureKit is configured to output 48kHz stereo, matching the engine format. The existing `scheduleBuffer()` in `AudioCaptureEngine` handles mismatches via `AVAudioConverter` as a safety net — no changes needed.

## What's NOT Changing

- Left side app picker UI
- Setup wizard flow
- Audio capture engine core (ScreenCaptureKit → AVAudioEngine → BlackHole)
- Channel assignment logic (still auto-assigns next free slot)
- Package.swift / Xcode project structure
- Unit test targets
