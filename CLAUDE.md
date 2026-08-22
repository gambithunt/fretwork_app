# Agent Instructions

## Scope

Fretwork: a macOS SwiftUI app (not iOS) that captures guitar input, monitors it
live to chosen output speakers/headphones, and shows detected notes on a
22-fret fretboard. Swift 6, strict concurrency enabled, macOS 14+ only.

Naming note: the Xcode project/target/scheme are still named `Fretlight`
(original name); the product/display name and Swift module are `Fretwork`
(renamed later). `@testable import Fretwork` in tests, not `Fretlight`.

Layout:
- `Fretlight/Audio/` — Core Audio plumbing: dual-engine capture/playback,
  ring buffers, device enumeration/watching, sensitivity mapping.
- `Fretlight/Pitch/` — pure DSP/logic, no Core Audio: YIN pitch detection,
  frequency→note mapping, tuning, fretboard-position resolution.
- `Fretlight/Models/AppState.swift` — the one `@MainActor @Observable` owner
  of UI state; wires Audio callbacks to published properties.
- `Fretlight/Views/` — SwiftUI.

## Workflows

1. **Build**: `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build`
2. **Test**: same command with `test` in place of `build`. Kill stale app
   processes first — a leftover `Fretwork.app`/`Fretlight.app` process from a
   previous run can hang the test-host launch with no clear error:
   `pkill -9 -f "Fretwork.app/Contents/MacOS\|Fretlight.app/Contents/MacOS"`
3. **Smoke-test a runtime/audio change**: launch the built binary directly in
   the background, sample `ps -p <pid> -o pid,pcpu,time` twice a few seconds
   apart (CPU should be stable, not climbing — a pegged core signals a
   busy-spin bug), and check its stdout/stderr for `-10877` or other
   `kAudioUnitErr_*`/Core Audio errors. Always `pkill` the process when done;
   check `ps aux | grep Fretwork` first since old runs accumulate.
4. **Measuring SwiftUI layout without a real display**: write a throwaway
   `swiftc` harness that builds `NSHostingView(rootView:)` around the view in
   question and reads `.fittingSize`. This is how every `minWidth`/`minHeight`
   in `FretworkApp.swift` was derived — measured, never guessed.
5. **Isolating a Core Audio error from a single console-log line**: don't
   trust one snapshot — `-10877` and friends can come from several unrelated
   layers (device HAL, an unowned playback graph, plain CPU starvation).
   Reproduce it in isolation first: an offline/manual-rendering
   `AVAudioEngine`, an off-screen render, or a standalone `swiftc` harness
   copying just the relevant files, before changing production code.

## Decisions

| Situation | Use | Avoid |
| --- | --- | --- |
| Routing audio to independently-chosen input and output devices | Two separate `AVAudioEngine` instances (`AudioEngine.swift`) | One engine's `inputNode`+`outputNode` — they share one AUHAL, so `kAudioOutputUnitProperty_CurrentDevice` can only bind one physical device |
| Feeding captured audio back out for monitoring | `AVAudioPlayerNode` + scheduled buffers (`AudioMonitorWorker`) | `AVAudioSourceNode`'s render callback — hit `kAudioUnitErr_InvalidElement` (-10877) consistently on real interfaces here |
| A background loop polling a shared buffer/queue | Check the throttle/cap condition *before* consuming, and sleep on every non-productive path | Consuming then discarding on a failed post-check — an unyielding busy-spin that once starved the real Core Audio I/O thread |
| A Text/Image whose displayed value changes rapidly under an active `.animation()` | `.contentTransition(.numericText())` / `.contentTransition(.symbolEffect(.replace))`, or branch with `.transition()` per state | Letting the view's content just mutate in place — produces overlapping/garbled rendering |
| Two sibling views that need independent placement (e.g. a title and a controls row) | A sequential `HStack`/`VStack` | `ZStack` + alignment to "center" one over the other — doesn't reserve space, can genuinely overlap depending on width |
| A custom `View` that also needs `Animatable` | Mark `animatableData` `nonisolated` | Leaving it inferred — strict concurrency flags it as crossing an actor boundary, since `Animatable`'s requirement isn't itself `@MainActor` |
| A stored property whose init needs to capture `self` | Give the property a plain default, assign its callback in `init()`'s body (see `AudioDeviceWatcher` / `AppState.deviceWatcher`) | Passing a `[weak self]`-capturing closure straight into that property's own initializer — two-phase init rejects any use of `self` before every other stored property has a value |
| Renaming the app / product | Update `@testable import <ModuleName>` in both test files too | Leaving old imports — `PRODUCT_NAME` changes the Swift module name; the test target silently fails to build |
| A screen mixing audio-rate readouts with static controls | Read the fast-changing `@Observable` properties inside one small leaf `View` per readout (see `TunerSection`/`LevelSection`/`TelemetrySection`/`BoardSection` in `ContentView.swift`) | Reading them in the parent's `body`. `@Observable` tracks reads per view body, so one 30Hz property read there rebuilds every sibling — device pickers and all |
| Writing an `@Observable` property on every audio frame | Compare first and assign only on a real change (see `unclearSignalMessage`, `appendToHistory`) | Assigning unconditionally — storing an equal value still fires `withMutation` and invalidates every observer |

## Patterns

One user-facing dial mapped to internal DSP knobs the UI shouldn't expose
directly (`Audio/SensitivitySettings.swift`):

```swift
/// A single user-facing 0...1 "sensitivity" dial, mapped to the two actual
/// DSP knobs that affect it, so the UI doesn't have to expose raw detector
/// internals.
final class SensitivitySettings: @unchecked Sendable {
    // ... NSLock-guarded 0...1 value ...
    var confidenceThreshold: Float { Float(0.90 - 0.24 * value) }
    var yinThreshold: Float { Float(0.06 + 0.12 * value) }
}
```

Follow this shape for any new tunable: one simple public dial, the mapping
math and its rationale documented right on the derived properties, not
scattered across call sites.

## Gotchas

- Don't add a second consumer to `RingBuffer` — it's strictly single-producer/
  single-consumer; a second reader corrupts the shared read cursor. Give each
  consumer its own `RingBuffer` instance fed from the same tap (see how
  `AudioEngine` feeds both `AudioAnalysisWorker` and `AudioMonitorWorker`).
- Don't restart/reconnect audio on every Core Audio device-change
  notification with no cooldown — a failing device can turn one notification
  into an infinite restart loop. Debounce and cap attempts (see
  `AudioEngine.scheduleRestart`/`attemptRestart`).
- Don't assume a `.animation(value:)` wrapping a whole panel is harmless if
  that same value updates on every frame (e.g. a live level meter) — anything
  inside whose *content* (not just a numeric property) changes on that same
  cadence is exactly what glitches. Scope animations narrowly or use a proper
  content transition.
- `.pickerStyle(.segmented)` leaks Observation registrations when it is
  rebuilt at audio rate: measured +1800 live `ObservationRegistrar` contexts
  per 30s at 30Hz, against +0 for the same `Picker` in its default style and
  +0 for the menu-style `DevicePickerView`. Every leaked registration is
  re-hashed on each subsequent property write, so per-update cost grows with
  uptime — an app pegged at 100% after 40 minutes was ~56% of its non-idle
  CPU in `AnyKeyPath` hashing alone, while a fresh launch sat at 13%. The fix
  is to stop rebuilding it that often (see the Decisions rows above), not to
  drop the control.
- CPU that ramps with uptime rather than sitting flat is an accumulation bug,
  not a "slow view". Compare `heap <pid>` class counts against a fresh launch
  — that is what identified this one; `sample`'s "Sort by top of stack"
  section gives self-time, which the call-graph tree does not.
- A backgrounded/occluded window is occlusion-throttled to ~0% CPU, so a
  hidden window measures clean no matter how bad the bug is. Any CPU
  comparison has to run with the window actually composited (`onscreen`).

## Versioning

Two separate fields, both in the `Fretlight` target's build settings
(`project.pbxproj`) — kept separate because App Store Connect/notarization
requires the build number to strictly increase across *every* upload,
including patch rebuilds of the same marketing version:

- `MARKETING_VERSION` — `0.MINOR.PATCH` (stay on `0.x` pre-1.0). Bump MINOR
  when a feature workstream completes (e.g. chord detection); bump PATCH for
  a bugfix-only workstream.
- `CURRENT_PROJECT_VERSION` — plain incrementing integer. Bump +1 alongside
  every MARKETING_VERSION bump.

On any workstream that bumps the version: also add a `CHANGELOG.md` entry
(newest on top, written from the commit's root-cause message) and tag the
commit `vX.Y.Z` on `main`.

## Workstream Checkpoints

- At the end of a completed workstream, check `git status` before reporting
  done — other sessions/tools touch this repo between turns.
- Build, run the test suite, and (for audio/UI-runtime changes) smoke-test
  per Workflows above before committing.
- If there are changes from the completed workstream, commit them with a
  message that states the root cause found and the fix, not just what
  changed — this file's Decisions table exists because those commit messages
  captured the reasoning.
- If the workstream shipped a feature or fix (not a pure refactor/doc/chore),
  bump the version per Versioning above as part of the same commit, update
  `CHANGELOG.md`, and tag it.
- Don't mix unrelated changes into one commit. If unrelated changes are
  already present (uncommitted work from elsewhere), leave them unstaged and
  call them out rather than folding them in.
