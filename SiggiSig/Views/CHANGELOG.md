# Changelog

All notable changes to SiggiSig are documented here.

## April 6, 2026

### Added

- Pan control on each mixer strip — position apps in the stereo field before they reach the DAW
- Pan values saved and restored with sessions, backward-compatible with older session files
- Double-tap the pan label to snap back to center

## April 4, 2026

### Added

- Volume faders with audio taper (dB-based, -60 to +6 dB range) on each mixer strip
- Visual audio meters with dB scaling, green/yellow/red gradient, and peak hold
- Session persistence — routes, volume, pan, and channel assignments save automatically and restore on launch
- Manual channel assignment — click the channel label on a mixer strip to reassign its BlackHole output pair
- Saved routes appear greyed out when the app isn't running and auto-connect when it launches
- App quit detection automatically cleans up routes

### Improved

- Setup wizard permission step is now informational instead of triggering macOS permission dialogs
- Consistent 24x24 app icons across the interface
- Dynamic type support for all text

### Fixed

- Fader no longer jumps to click position — drags are relative to where you grab
- Audio meters now visible at normal listening levels (dB scaling instead of linear)

## April 2, 2026

### Added

- Per-app audio capture via ScreenCaptureKit — route any running app's audio to BlackHole 16ch
- App picker showing all running applications with audio output
- Setup wizard checking for BlackHole 16ch and Screen Recording permission
- Status bar showing connection state and errors
- Mixer view with horizontal scrolling strip layout
