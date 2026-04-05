# SiggiSig v3: Pan Controls, Menubar Mode, Signing, Polished UI

## Overview

Four features to take SiggiSig from "works for me" to "shareable product."

## Feature 1: Pan Controls

Add a pan knob/slider per mixer strip, positioning apps in the stereo field before the DAW.

- Range: -1.0 (full left) to +1.0 (full right), default 0.0 (center)
- Applied on the per-route `AVAudioMixerNode` via `pan` property
- Persisted in session JSON alongside volume
- UI: small horizontal slider or knob below the fader in MixerStripView

**Files to modify:**
- `Route` — add `pan: Float` property
- `RouterState` — add `setPan` method
- `AudioCaptureEngine` — add `setPan(for:pan:)` method using `routeMixer.pan`
- `RouterViewModel` — add `setPan` method, wire to engine + state + save
- `SavedRoute` — add `pan` field
- `MixerStripView` — add pan control
- `MixerView` / `ContentView` — wire pan callback

## Feature 2: Menubar-Only Mode

Run as a menu bar utility — click the icon to show/hide the main window.

- Menu bar icon (waveform SF Symbol)
- Click to toggle main window visibility
- Window hidden on close (Cmd+W) instead of quitting
- App keeps running in background
- Right-click menu bar icon for Quit option
- Dock icon hidden when running as menubar app

**Files to modify/create:**
- `SiggiSigApp.swift` — add MenuBarExtra, handle window lifecycle
- `ContentView.swift` — may need window management changes
- Info.plist — add `LSUIElement` to hide dock icon (or toggle)

## Feature 3: Signing & Notarization

Code sign and notarize for distribution outside the App Store.

- Requires Apple Developer Program membership ($99/year) — confirm David has this
- If only Personal Team (free), can sign for local use but not notarize for distribution
- Developer ID certificate for distribution outside App Store
- Notarization via `xcrun notarytool`
- Create a DMG or ZIP for distribution

**Steps:**
1. Confirm developer account type
2. Set up Developer ID signing in Xcode
3. Archive and export
4. Notarize with Apple
5. Create distributable DMG

## Feature 4: Polished UI

Visual refinements to make it feel professional.

### Window resizing
- Make window resizable with minimum size constraints
- Mixer strips reflow/scroll as window changes
- App list and mixer split adjustable

### Drag-to-reorder mixer strips
- Drag mixer strips to rearrange order in the mixer view
- Visual feedback during drag (strip lifts, others shift)
- Order persisted in session

### Visual polish
- Subtle background for mixer strips (card-like appearance)
- Better visual separation between strips
- App name truncation with tooltip on hover
- Smooth animations for route add/remove

### Theming
- Respect system dark/light mode (should already work with SwiftUI)
- Verify all custom colors work in both modes

## Implementation Order

1. **Pan controls** — smallest feature, extends existing mixer strip pattern
2. **Menubar mode** — changes app lifecycle, should be done before UI polish
3. **Polished UI** — visual pass with app in final form factor
4. **Signing & notarization** — last step before sharing

## Current Architecture Context

The audio chain per route is:
```
ScreenCaptureKit → AVAudioPlayerNode → RouteMixerNode → mainMixerNode → BlackHole 16ch
```

Volume is applied via `routeMixer.outputVolume`. Pan will use `routeMixer.pan`.
Meter taps are installed on `routeMixer`.
Session saves to `~/Library/Application Support/SiggiSig/session.json`.
XcodeGen config in `project.yml`, Xcode project in `SiggiSig.xcodeproj`.
Code signing configured with David Ryan Personal Team.
