# SiggiSig Manual Testing Guide

## Prerequisites
- BlackHole 16ch installed
- Ableton Live (or any DAW)

## Test 1: Setup Wizard
1. Delete app preferences (fresh state)
2. Launch SiggiSig
3. Verify BlackHole detection shows green checkmark
4. Verify Screen Recording permission prompt appears
5. Grant permission, verify "Get Started" button appears

## Test 2: App Discovery
1. Open Chrome and Safari
2. Verify both appear in the app list
3. Close Safari, verify it disappears within 3 seconds

## Test 3: Basic Audio Routing
1. Open Chrome, play a YouTube video
2. In SiggiSig, click Chrome in the app list
3. Verify it appears in Active Routes as "Ch 1-2"
4. In Ableton, create an audio track with input "BlackHole 16ch 1-2"
5. Arm the track, verify audio levels show YouTube audio
6. Record, verify playback contains the audio

## Test 4: Multi-App Routing
1. Route Chrome → Ch 1-2
2. Route Spotify → Ch 3-4
3. In Ableton, create two tracks on Ch 1-2 and Ch 3-4
4. Verify each track receives only its respective app audio

## Test 5: App Quit Handling
1. Route Chrome → Ch 1-2
2. Quit Chrome
3. Verify route is removed from Active Routes
4. Verify Ch 1-2 shows as "free"

## Test 6: BlackHole Disconnect
1. Route an app
2. Uninstall/disable BlackHole (or change audio device settings)
3. Verify error message appears in status bar
