# Per-App Channel Routing Fix

**Status:** Implemented on `fix/review-findings`, awaiting review
**Date:** 2026-10-30

## Summary

SiggiSig's core promise is that each routed app lands on its own stereo pair of BlackHole 16ch,
so a DAW can record each app on its own track. On current macOS, that has never worked:

1. **The audio engine never started.** `AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 16)`
   returns `nil` (formats above 2 channels need an explicit channel layout), so `setup()` threw before
   `engine.start()`. The "Failed to start audio engine" message was cleared as soon as an app was routed,
   so the UI looked normal while nothing played.
2. **Per-slot placement did nothing.** Routes were placed on their pair by setting
   `auAudioUnit.channelMap` on each route's `AVAudioMixerNode`. That property has no effect on a mixer
   node (it reads back `nil`), so even with the engine running, every app would be summed onto Ch 1-2.
   Reassigning a channel only changed the label.

Both were found in an adversarial code review and confirmed with offline renders. No release has been
tagged on GitHub, but `dist/SiggiSig-1.0.0.dmg` exists locally; anyone given that build has this bug.

## Design

Each route is 16 channels wide end to end, and places its own audio on its pair before it reaches
the mixers:

```
SCStream (48 kHz stereo) → schedule(): copy L/R onto Ch slot*2, slot*2+1 of a 16-ch buffer,
                                       balance applied, other 14 channels silent
                         → AVAudioPlayerNode (16 ch) → route AVAudioMixerNode (16 ch)
                         → mainMixerNode (16 ch) → outputNode → BlackHole 16ch
```

- **Placement:** `AudioCaptureEngine.schedule(_:on:params:)` runs on the existing audio scheduling queue
  (not the real-time render thread). It converts to 48 kHz stereo if needed (normally a no-op), copies
  the samples onto the route's pair and schedules the 16-channel buffer.
- **Volume:** unchanged, `routeMixer.outputVolume`. Verified to work on 16-channel connections.
- **Pan:** `AVAudioMixerNode.pan` has no effect on a 16-channel input, so pan is applied as stereo
  balance during the copy: centre leaves both sides at unity; moving towards one side turns the other
  down linearly (−1 = left only, +1 = right only). This matches how the mixer's pan behaved on the
  previous stereo connection.
- **Channel reassignment:** updates the route's slot only. The next captured chunk (~10–20 ms) lands on
  the new pair. No graph changes, which also removes one place where the engine graph was mutated on
  the main actor while the audio queue was scheduling.
- **Shared state:** slot and pan live in `RouteParams`, a small `Sendable` class backed by
  `OSAllocatedUnfairLock`, written on the main actor and read on the audio queue and in the meter tap.
- **Meters:** measure only the route's own pair. Measuring all 16 channels would read ~9 dB low.
- **Slot validation:** out-of-range slots (e.g. from a hand-edited `session.json`) are rejected in
  `startCapture` and `reassignChannel`, and dropped in `schedule`, rather than crashing.

## Tests

`Tests/AudioRoutingTests.swift` renders the real graph offline with manual rendering mode, so it runs
without BlackHole or Screen Recording permission:

- output format is 16 ch / 48 kHz
- a route on slot 3 lands on Ch 7-8 only
- two routes (slots 0 and 7) don't bleed into each other
- reassigning mid-stream moves later audio to the new pair
- hard-left pan silences the right channel; balance gain values
- meters read only the route's pair (RMS not diluted)
- a 44.1 kHz input is converted and lands on its pair

## Alternatives considered

| Option | Why not (for now) |
|---|---|
| `AVAudioSourceNode` per route fed from a ring buffer | Avoids per-chunk allocation and could shave latency, but needs a real-time-safe lock-free ring buffer, which is a lot more code and easy to get subtly wrong in Swift 6. Worth revisiting if latency matters. |
| One `AVAudioEngine` per app, using the output unit's channel map | CoreAudio mixes multiple clients on one device, so this may work, but it's untested, means up to 8 engines, and reassignment likely needs a restart. |
| Channel map on the shared output node | Device-wide, can't place apps individually. |

## Open questions for reviewers

1. **Pan law:** linear balance (current) vs equal-power. Balance keeps a centred stereo source at unity,
   which seems right for routing to a DAW, where the DAW owns the mix.
2. **Lock on the audio path:** the meter tap and scheduling queue take an unfair lock briefly per chunk.
   Neither runs on the render thread, so this seems acceptable. Agree?
3. **Allocation per chunk:** each ~10 ms chunk allocates a 16-channel buffer on the scheduling queue
   (`AppAudioStream` already allocates one per chunk too). Fine for now, or pool buffers?
4. **Latency:** is the current player-node path good enough, or is the source-node approach worth it?

## Not in this change

Other review findings, to follow as separate commits: routes leaking when an app quits, double-click
starting duplicate captures, session restore running twice after a setup retry, pending routes not
reserving their slots, apps without bundle IDs never reconnecting, no handling of device
sample-rate changes, and the remaining cross-thread engine access.
