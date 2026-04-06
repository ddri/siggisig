# Pan Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pan knob per mixer strip, positioning apps in the stereo field before the DAW.

**Architecture:** Pan is applied on the per-route `AVAudioMixerNode` via its `pan` property (-1.0 to +1.0). The data flows through the same pipeline as volume: UI → ViewModel → RouterState + AudioCaptureEngine → session persistence.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (AVAudioMixerNode.pan)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `SiggiSig/State/RouterState.swift` | Modify | Add `pan` to Route, add `setPan` method |
| `SiggiSig/State/SessionStore.swift` | Modify | Add `pan` to SavedRoute |
| `SiggiSig/Audio/AudioCaptureEngine.swift` | Modify | Add `setPan(for:pan:)` method |
| `SiggiSig/ViewModels/RouterViewModel.swift` | Modify | Add `setPan` method, wire save + restore |
| `SiggiSig/Views/MixerStripView.swift` | Modify | Add pan slider UI |
| `SiggiSig/Views/MixerView.swift` | Modify | Add `onPanChange` callback, pass pan binding |
| `SiggiSig/ContentView.swift` | Modify | Wire `onPanChange` to ViewModel |
| `Tests/SiggiSigTests/RouterStateTests.swift` | Modify | Add pan tests |

---

### Task 1: Add pan to Route and RouterState

**Files:**
- Modify: `SiggiSig/State/RouterState.swift:3-18` (Route struct) and `:46-49` (add setPan method)
- Modify: `Tests/SiggiSigTests/RouterStateTests.swift`

- [ ] **Step 1: Write the failing test**

In `Tests/SiggiSigTests/RouterStateTests.swift`, add:

```swift
func testSetPan() {
    var state = RouterState()
    state.addRoute(appName: "Test", bundleID: "com.test", pid: 100, slot: 0)
    state.setPan(pid: 100, pan: -0.5)
    XCTAssertEqual(state.routes.first?.pan, -0.5)
}

func testSetPanClampsToRange() {
    var state = RouterState()
    state.addRoute(appName: "Test", bundleID: "com.test", pid: 100, slot: 0)
    state.setPan(pid: 100, pan: 2.0)
    XCTAssertEqual(state.routes.first?.pan, 1.0)
    state.setPan(pid: 100, pan: -2.0)
    XCTAssertEqual(state.routes.first?.pan, -1.0)
}

func testRouteDefaultPanIsCenter() {
    var state = RouterState()
    state.addRoute(appName: "Test", bundleID: "com.test", pid: 100, slot: 0)
    XCTAssertEqual(state.routes.first?.pan, 0.0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testSetPan`
Expected: FAIL — `pan` property and `setPan` method don't exist yet.

- [ ] **Step 3: Add pan property to Route and setPan to RouterState**

In `SiggiSig/State/RouterState.swift`, add `pan` to the Route struct:

```swift
struct Route: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let bundleID: String?
    let pid: pid_t
    var slot: Int
    var volume: Float = 0.0  // dB, 0.0 = unity gain
    var pan: Float = 0.0     // -1.0 (left) to +1.0 (right), 0.0 = center
    // ... rest unchanged
}
```

Add `setPan` method after `setVolume`:

```swift
mutating func setPan(pid: pid_t, pan: Float) {
    guard let index = routes.firstIndex(where: { $0.pid == pid }) else { return }
    routes[index].pan = min(max(pan, -1.0), 1.0)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter testSetPan && swift test --filter testRouteDefaultPan`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add SiggiSig/State/RouterState.swift Tests/SiggiSigTests/RouterStateTests.swift
git commit -m "feat: add pan property to Route and setPan to RouterState"
```

---

### Task 2: Add pan to session persistence

**Files:**
- Modify: `SiggiSig/State/SessionStore.swift:3-8` (SavedRoute struct)
- Modify: `SiggiSig/ViewModels/RouterViewModel.swift:153-168` (saveSession) and `:180-190` (restoreSession)

- [ ] **Step 1: Add pan to SavedRoute**

In `SiggiSig/State/SessionStore.swift`, add `pan` to SavedRoute with a default for backward compatibility:

```swift
struct SavedRoute: Codable, Equatable {
    let bundleID: String
    let appName: String
    let channelSlot: Int
    let volume: Float
    var pan: Float = 0.0

    // Backward-compatible decoding for sessions saved before pan was added
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decode(String.self, forKey: .appName)
        channelSlot = try container.decode(Int.self, forKey: .channelSlot)
        volume = try container.decode(Float.self, forKey: .volume)
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
    }

    init(bundleID: String, appName: String, channelSlot: Int, volume: Float, pan: Float = 0.0) {
        self.bundleID = bundleID
        self.appName = appName
        self.channelSlot = channelSlot
        self.volume = volume
        self.pan = pan
    }
}
```

- [ ] **Step 2: Update saveSession in RouterViewModel**

In `SiggiSig/ViewModels/RouterViewModel.swift`, update `saveSession()` to include pan:

```swift
private func saveSession() {
    var savedRoutes = routerState.routes.map { route in
        SavedRoute(
            bundleID: route.bundleID ?? "",
            appName: route.appName,
            channelSlot: route.slot,
            volume: route.volume,
            pan: route.pan
        )
    }
    savedRoutes.append(contentsOf: pendingRoutes)
    do {
        try sessionStore.save(routes: savedRoutes)
    } catch {
        // Session save failures are non-fatal, don't show to user
    }
}
```

- [ ] **Step 3: Update restoreSession in RouterViewModel**

Find where volume is restored during session restore and add pan restore alongside it. After the existing lines:
```swift
routerState.setVolume(pid: app.id, volume: saved.volume)
engine.setVolume(for: app, db: saved.volume)
```

Add:
```swift
routerState.setPan(pid: app.id, pan: saved.pan)
engine.setPan(for: app, pan: saved.pan)
```

Note: `engine.setPan` will be implemented in Task 3. This will cause a compile error until then — that's expected.

- [ ] **Step 4: Build to verify SavedRoute changes compile**

Run: `swift build 2>&1 | head -20`
Expected: Errors about missing `engine.setPan` — that's fine, confirms SavedRoute and state changes are correct.

- [ ] **Step 5: Commit**

```bash
git add SiggiSig/State/SessionStore.swift SiggiSig/ViewModels/RouterViewModel.swift
git commit -m "feat: add pan to session persistence with backward-compatible decoding"
```

---

### Task 3: Add setPan to AudioCaptureEngine and RouterViewModel

**Files:**
- Modify: `SiggiSig/Audio/AudioCaptureEngine.swift:180-183` (add setPan after setVolume)
- Modify: `SiggiSig/ViewModels/RouterViewModel.swift:113-120` (add setPan after setVolume)

- [ ] **Step 1: Add setPan to AudioCaptureEngine**

In `SiggiSig/Audio/AudioCaptureEngine.swift`, add after the `setVolume` method:

```swift
func setPan(for app: CaptureApp, pan: Float) {
    guard let managed = activeStreams[app.id] else { return }
    managed.routeMixer.pan = pan
}
```

- [ ] **Step 2: Add setPan to RouterViewModel**

In `SiggiSig/ViewModels/RouterViewModel.swift`, add after the `setVolume` method:

```swift
func setPan(for pid: pid_t, pan: Float) {
    routerState.setPan(pid: pid, pan: pan)
    if let route = routerState.routes.first(where: { $0.pid == pid }) {
        let fakeApp = CaptureApp(id: pid, name: route.appName, bundleIdentifier: route.bundleID, icon: nil)
        engine.setPan(for: fakeApp, pan: pan)
    }
    scheduleSave()
}
```

- [ ] **Step 3: Build to verify everything compiles**

Run: `swift build`
Expected: BUILD SUCCEEDED — all compile errors from Task 2 should now be resolved.

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add SiggiSig/Audio/AudioCaptureEngine.swift SiggiSig/ViewModels/RouterViewModel.swift
git commit -m "feat: add setPan to AudioCaptureEngine and RouterViewModel"
```

---

### Task 4: Add pan slider to MixerStripView

**Files:**
- Modify: `SiggiSig/Views/MixerStripView.swift:3-12` (add pan binding) and `:31-45` (add pan slider to layout)

- [ ] **Step 1: Add pan binding to MixerStripView**

Add a `pan` binding after the existing `volume` binding:

```swift
@Binding var volume: Float
@Binding var pan: Float
```

- [ ] **Step 2: Add pan slider to the layout**

Add a horizontal pan slider below the meter+fader HStack and above the channel label. Insert after the `.frame(height: 150)` closing the meter/fader HStack:

```swift
// Pan control
HStack(spacing: 2) {
    Text("L")
        .font(.system(size: 8))
        .foregroundColor(.secondary)
    Slider(value: $pan, in: -1.0...1.0)
        .frame(width: 50)
        .disabled(!isActive)
        .onDoubleClick {
            pan = 0.0
        }
    Text("R")
        .font(.system(size: 8))
        .foregroundColor(.secondary)
}
```

Note: SwiftUI `Slider` doesn't have `onDoubleClick` natively. Use a simpler approach — add a gesture modifier on the slider or just use a tap gesture on a label to reset. Replace the `onDoubleClick` with this approach:

```swift
// Pan control
VStack(spacing: 2) {
    Slider(value: $pan, in: -1.0...1.0)
        .frame(width: 56)
        .disabled(!isActive)
    Text(panLabel)
        .font(.system(size: 9).monospaced())
        .foregroundColor(.secondary)
        .onTapGesture(count: 2) {
            pan = 0.0
        }
}
```

Add a computed property for the pan label:

```swift
private var panLabel: String {
    if abs(pan) < 0.05 { return "C" }
    if pan < 0 { return String(format: "L%.0f", abs(pan) * 100) }
    return String(format: "R%.0f", pan * 100)
}
```

Where `pan` refers to the binding value. Since this is in a View struct, access via the binding's wrappedValue.

- [ ] **Step 3: Build to check for errors**

Run: `swift build 2>&1 | head -30`
Expected: Errors at MixerStripView call sites (MixerView) because `pan` binding is now required. That's expected.

- [ ] **Step 4: Commit**

```bash
git add SiggiSig/Views/MixerStripView.swift
git commit -m "feat: add pan slider to MixerStripView"
```

---

### Task 5: Wire pan through MixerView and ContentView

**Files:**
- Modify: `SiggiSig/Views/MixerView.swift:3-11` (add onPanChange callback) and `:29-44` (pass pan to MixerStripView)
- Modify: `SiggiSig/ContentView.swift:36-51` (add onPanChange closure)

- [ ] **Step 1: Add onPanChange to MixerView**

In `SiggiSig/Views/MixerView.swift`, add after `onVolumeChange`:

```swift
let onPanChange: (pid_t, Float) -> Void
```

- [ ] **Step 2: Pass pan binding to MixerStripView for active routes**

Update the `MixerStripView` instantiation in the `ForEach(routes)` block to include:

```swift
pan: Binding(
    get: { route.pan },
    set: { onPanChange(route.pid, $0) }
),
```

- [ ] **Step 3: Pass pan binding to MixerStripView for pending routes**

Update the `MixerStripView` instantiation in the `ForEach(pendingRoutes)` block to include:

```swift
pan: .constant(saved.pan),
```

- [ ] **Step 4: Wire onPanChange in ContentView**

In `SiggiSig/ContentView.swift`, add `onPanChange` to the MixerView initializer:

```swift
onPanChange: { pid, pan in
    viewModel.setPan(for: pid, pan: pan)
},
```

- [ ] **Step 5: Build and verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add SiggiSig/Views/MixerView.swift SiggiSig/ContentView.swift
git commit -m "feat: wire pan controls through MixerView and ContentView"
```

---

## Post-Implementation Verification

After all tasks are complete:

1. **Build:** `swift build` — should succeed with zero warnings
2. **Tests:** `swift test` — all tests pass
3. **Manual test:** Build in Xcode, route an app, drag pan slider left/right, verify audio shifts in stereo field
4. **Session test:** Set a pan value, quit app, relaunch — pan should restore
5. **Backward compat:** Delete session.json, launch app — should work with default center pan
