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
  frequency→note mapping, fretboard-position resolution.
- `Fretlight/Theory/` — music theory, ported from the web app at
  `../fretwork`: pitch classes and naming, intervals, scales, chord formulas,
  the 15 tunings, canonical shape data, diatonic harmony, chord discovery.
  `Foundation` only — no Core Audio, no SwiftUI. Anything needing a note,
  interval, scale or chord derives it from here rather than recomputing it.
- `Fretlight/Models/AppState.swift` — the one `@MainActor @Observable` owner
  of UI state; wires Audio callbacks to published properties.
  `PracticeState`/`PracticeStateStore` alongside it own everything persisted.
- `Fretlight/Views/` — SwiftUI.

## Workflows

1. **Build**: `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build`
2. **Test**: same command with `test` in place of `build`. Kill stale app
   processes first — a leftover `Fretwork.app`/`Fretlight.app` process from a
   previous run can hang the test-host launch with no clear error:
   `pkill -9 -f "Fretwork.app/Contents/MacOS|Fretlight.app/Contents/MacOS"`
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
5. **Seeing a transient on screen** (a jolt at launch, a janky animation):
   screen recording is not granted here, so `screencapture`/`CGWindowList`
   return "could not create image from display". Capture the app from *inside*
   the process instead: a `#if DEBUG` task that walks `NSApp.windows` for the
   detail pane's `NSClipView` and calls `cacheDisplay(in:to:)` into an
   `NSBitmapImageRep` every ~16ms, buffering the reps and writing PNGs at the
   end. Two traps: `cacheDisplay` on the window's own `contentView` renders the
   module screens as solid black, because they live inside a `HostingScrollView`
   — target the clip view; and glass cards come out as white blocks, so judge
   layout and content, not material. Pass a sub-rect to keep the frame rate up
   (a full 2760x2052 grab costs ~120ms; a 240x240pt region runs at ~60fps).
   Then diff frames in Python and track the *centroid of the coloured pixels*,
   not a bounding box — that is what showed a pulsing dot moving 4.5pt rather
   than merely growing. Synthetic `NSEvent`s do **not** work for driving SwiftUI
   gestures this way: neither `window.sendEvent` nor `NSApp.postEvent` delivers
   the mouse-up to the gesture, so a `LongPressGesture` fires 450ms later and
   undoes what the tap did. Post a `Notification` the screen listens for in
   DEBUG and wrap the call in the same `withAnimation` the gesture uses.
6. **Isolating a Core Audio error from a single console-log line**: don't
   trust one snapshot — `-10877` and friends can come from several unrelated
   layers (device HAL, an unowned playback graph, plain CPU starvation).
   Reproduce it in isolation first: an offline/manual-rendering
   `AVAudioEngine`, an off-screen render, or a standalone `swiftc` harness
   copying just the relevant files, before changing production code.

## Decisions

| Situation | Use | Avoid |
| --- | --- | --- |
| Routing audio to independently-chosen input and output devices | Two separate `AVAudioEngine` instances (`AudioEngine.swift`) | One engine's `inputNode`+`outputNode` — they share one AUHAL, so `kAudioOutputUnitProperty_CurrentDevice` can only bind one physical device |
| Feeding audio out — monitoring or sample playback | An `AVAudioSourceNode` render callback (`MonitorRenderer`, `SamplePlayer`), pulling exactly the frames the device is about to play | `AVAudioPlayerNode` + scheduled buffers. This row used to say the opposite, blaming the source node for `kAudioUnitErr_InvalidElement` (-10877). That diagnosis was wrong: the -10877 was a polling loop busy-spinning hard enough to starve Core Audio's real-time thread, and it happened regardless of the device. With the spin gone, pulling works — and pulling removes the ~46ms queue the pushing design needed. The hazard is a busy-spinning consumer, never the source node |
| A second signal joining the graph's shared mixer | Give each leg its own level, and leave `mainMixerNode.outputVolume` at unity | Driving the slider from the mixer's *output*. That works only while the mixer has one input; the moment a second one arrives, one control governs both |
| A per-leg level on a node feeding a mixer | `AVAudioMixing.volume` if the leg ends in a source-type node (`AVAudioSourceNode`, `AVAudioPlayerNode`, `AVAudioInputNode`, `AVAudioMixerNode`) — it is free, being mixing work already being done | A dedicated `AVAudioMixerNode` as a fader: measured idle CPU 13% → 30%, because it is a full converting mixer and two in series convert twice. Effects (`AVAudioUnitEQ`, `AVAudioUnitDelay`) do **not** conform to `AVAudioMixing`, so `as? AVAudioMixing` on one silently does nothing — it compiles, it runs, and the control just stops working |
| A background loop polling a shared buffer/queue | Check the throttle/cap condition *before* consuming, and sleep on every non-productive path | Consuming then discarding on a failed post-check — an unyielding busy-spin that once starved the real Core Audio I/O thread |
| A momentary emphasis (a pulse, a flash) on a view something *else* positions | A transform — `.scaleEffect`, which scales about the centre and changes no layout | Growing the view's `.frame`. `FretboardDotView` did, while the `.position` centring it lived outside in `DotMotionModifier`. The grow was set inside the caller's `withAnimation` so both animated together; the release is a bare write from a detached task, so `.position` snapped to the final frame's origin while the drawn size was still shrinking — the dot pinned by its top-left, spilling 4.5pt down-right, measured. When a size and the thing positioning it animate in different scopes, only one of them is ever in the transaction |
| A Text/Image whose displayed value changes rapidly under an active `.animation()` | `.contentTransition(.numericText())` / `.contentTransition(.symbolEffect(.replace))`, or branch with `.transition()` per state | Letting the view's content just mutate in place — produces overlapping/garbled rendering |
| Two sibling views that need independent placement (e.g. a title and a controls row) | A sequential `HStack`/`VStack` | `ZStack` + alignment to "center" one over the other — doesn't reserve space, can genuinely overlap depending on width |
| A custom `View` that also needs `Animatable` | Mark `animatableData` `nonisolated` | Leaving it inferred — strict concurrency flags it as crossing an actor boundary, since `Animatable`'s requirement isn't itself `@MainActor` |
| Signing a build for distribution without an Apple Developer account | A self-signed Code Signing certificate, reused for every build | Ad-hoc (`codesign -s -`). Ad-hoc's designated requirement is a bare `cdhash`, so every rebuild is a different app to TCC and the microphone grant is re-prompted on every update. A self-signed cert's requirement is `identifier "..." and certificate leaf H"..."`, which is stable across rebuilds — measured, see Gotchas |
| Info.plist keys that `INFOPLIST_KEY_*` cannot express (e.g. Sparkle's) | A partial `Config/Info.plist` set as `INFOPLIST_FILE`, with `GENERATE_INFOPLIST_FILE` left YES so the two merge | Turning off plist generation, or putting the file inside `Fretlight/` — that folder is a synchronized root group, so the plist would also be copied in as a resource |
| A stored property whose init needs to capture `self` | Give the property a plain default, assign its callback in `init()`'s body (see `AudioDeviceWatcher` / `AppState.deviceWatcher`) | Passing a `[weak self]`-capturing closure straight into that property's own initializer — two-phase init rejects any use of `self` before every other stored property has a value |
| Renaming the app / product | Update `@testable import <ModuleName>` in both test files too | Leaving old imports — `PRODUCT_NAME` changes the Swift module name; the test target silently fails to build |
| A screen mixing audio-rate readouts with static controls | Read the fast-changing `@Observable` properties inside one small leaf `View` per readout (see `TunerSection`/`LevelSection`/`TelemetrySection`/`BoardSection` in `ContentView.swift`) | Reading them in the parent's `body`. `@Observable` tracks reads per view body, so one 30Hz property read there rebuilds every sibling — device pickers and all |
| Writing an `@Observable` property on every audio frame | Compare first and assign only on a real change (see `unclearSignalMessage`, `appendToHistory`) | Assigning unconditionally — storing an equal value still fires `withMutation` and invalidates every observer |
| Porting a fret array or string index from `../fretwork` | Reverse it — web string 0 is the high e, this app's is the Low E — and prove it with a test asserting the *sounded pitch classes*, not the numbers | Transcribing as-is. A reversed array is still six plausible fret numbers: it compiles, it renders, and it is wrong |
| A generator whose output is fixed fret offsets (open-chord charts, pentatonic boxes) | Take no `Tuning` parameter at all, so misuse is a compile error (see `ScaleShapes.pentatonicPosition`) | Accepting a `Tuning` it cannot honour. Those frets do not transpose, they detune — the box silently stops being the scale it claims to be. This slipped in twice |
| Decoding a persisted settings document | Decode field by field, each with its own fallback (`PracticeState.Settings`) | Synthesised `Decodable` — one unrecognised enum case throws and takes every other setting down with it |
| Refactoring a view that must look unchanged | Render it off-screen to PNGs before and after and compare pixels (`DetectionBoardSnapshotTests`, gated on `TEST_RUNNER_FRETWORK_SNAPSHOT_DIR`) | Reading the diff and calling it equivalent. The detection board's rewrite looked right and was placing every dot wrongly; only the pixels said so |
| A learning module's rules | A `@MainActor @Observable` model with the audio call injected as a closure, and a thin screen over it (see `NotesModuleModel` / `NotesModuleScreen`) | Putting the rules in the `View`. Every module's real content — what the shape *is* — then needs a rendered view to test |
| A module's persisted selection | The thing's own id or `short` (`intervalShort`, `formulaID`, a voicing's id) | An index into a catalogue or a voicing list. Both change length, so an index silently re-points at a different chord or shape rather than failing |
| A generator's position/index convention | Check it against the generator, not against the UI's numbering — `ScaleShapes.pentatonicPosition` is 0-based, and so is the web's saved value | Assuming the 1-based numbering the screen shows. A shifted box is still a plausible-looking shape, so this fails silently and looks right |
| Emphasising the current step of a guided run | Pass the **run** to `GuidedPresentation.decorate`, not the shape it was built from | Passing the shape. An up-and-down run is nearly twice as long, so past the turn the index emphasises the wrong note or none at all |
| A module built on fixed fret shapes, when tuning is a global setting | Say so on screen (`StandardTuningNotice`) — Chords, Pentatonic, Harmonizing | Drawing the shape anyway. Those frets do not transpose, they detune, and the board looks equally confident either way |
| Placing a view that also carries a `.transition(.modifier(...))` | Let the transition's identity state position it, and nothing else | Adding `.position` on top. Both apply, the dot lands where neither asked, and it is invisible in a static reading of the code |
| Aligning recorded samples on their attack | Re-measure the onset from the audio at build time (`scripts/build-sample-library.sh`) | Trusting the mark the recorder wrote. A noise-floor-derived threshold fires late on a soft attack, so a fixed rewind lands *inside* the transient — measured across 138 real takes, onsets ranged 0–43 ms against a nominal 15 |
| Choosing a lossy codec for sampled audio | Decode both builds back to PCM, correlate to find the offset, and check it is 0 before comparing anything else | Judging on bitrate or on an SNR figure alone. Encoder priming shifting the attack is what disqualifies a codec for a sampled instrument, and an SNR computed at the wrong offset hides it |

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
  `AudioEngine` feeds `AudioAnalysisWorker`, `ChordAnalysisWorker`, the split
  path's `MonitorRenderer` and — in DEBUG — `SampleRecorder`, each from its own
  ring).
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
- Embedding any framework requires `LD_RUNPATH_SEARCH_PATHS` to include
  `@executable_path/../Frameworks`. These build configurations were written by
  hand and never had it, so the first embedded framework (Sparkle) was copied
  into the bundle correctly and dyld still aborted on launch with `Library not
  loaded: @rpath/...`. **The test suite cannot catch this** — xctest injects
  `DYLD_FRAMEWORK_PATH` pointing at the build products directory, where the
  framework also sits, so tests pass against an app that cannot launch. Only
  running the archived build directly shows it.
- Xcode's *default* for an unset build setting is not the template's value.
  `SWIFT_OPTIMIZATION_LEVEL` unset means `-Onone`, not `-O`, so an otherwise
  healthy-looking Release configuration shipped an unoptimized binary for
  months. Check with `xcodebuild -showBuildSettings`: a setting that is absent
  from the output entirely has no value at all.
- Sparkle is **vendored**, not a Swift package: `Frameworks/Sparkle.xcframework`
  is linked and embedded directly, and `generate_keys`/`sign_update`/
  `generate_appcast` live in `Tools/sparkle/`. Do not reintroduce it as an SPM
  dependency — its binary-target cache wedged repeatedly (`already exists in
  file system`, then a resolve that stopped with `"artifacts": []`) and took
  the Xcode GUI build down with it while `xcodebuild` still worked.
  `docs/releasing.md` has the upgrade procedure, including that the
  xcframework's `DebugSymbolsPath` key must be deleted when the dSYMs are
  stripped. `sign_update --ed-key-file -` reads the private key from stdin,
  which is how CI signs without writing the key to disk.
- A backgrounded/occluded window is occlusion-throttled to ~0% CPU, so a
  hidden window measures clean no matter how bad the bug is. Any CPU
  comparison has to run with the window actually composited (`onscreen`).

- A settle/debounce window that exists to ignore *your own* churn has to be
  measured from when that work **finishes**, not when it starts.
  `AudioEngine.startSynchronously` armed its 1.5s window at the top of a build
  that can take seconds, and the configuration change its own
  `setBufferFrameSize` provokes is only delivered once the build releases
  `graphQueue` — so on a device slower to bind than the window is long, the
  build's own churn arrived with the window already expired, was read as the
  device renegotiating, and restarted the graph, which produced the same
  notification again. Measured with a 2s injected bind: three full restart
  cycles before the circuit breaker stopped it, each one flashing the
  "Reconnecting" banner and shoving the whole Listen screen down. A built-in
  device binds in ~170ms and never showed it; a USB interface does. Anything
  guarded by a deadline set before slow work is the same bug.

- A SwiftUI text style and a same-size `Font.system` are not the same glyphs.
  Swapping `.caption2.weight(.bold)` for `.system(size: 10, weight: .bold)`
  changed 0.023% of the detection board's pixels — invisible, but it proves
  the two are distinct rasterisations. `FretboardDotView` keeps the text style
  at the default dot radius for exactly this reason and scales only when a
  module asks for a smaller dot.

- `PitchDetector` sized its `scratch` buffer from `maxTau` but `vDSP_vsub`
  wrote `count - tau` floats into it — sized by one derived quantity, written
  according to another. It never corrupted anything because the only caller,
  `AudioAnalysisWorker`, passes exactly 2048 samples against a 2048-element
  buffer: one element under the limit. The first caller to analyse a longer
  window (take verification, at 4096) would have smashed the heap. When a
  buffer's size and its write length come from different expressions, check
  them against each other rather than against the one call site that exists.

- Property observers do not fire for a value assigned inside the type's own
  `init`, so restoring a saved setting there never reaches its `didSet`.
  `AppState` restored `sensitivity` this way for months: the slider showed the
  saved value while the detector ran at its 0.5 default for the whole session,
  until the user happened to move the control. Apply the side effect
  explicitly after assigning, and be suspicious of any `init` that assigns a
  property whose `didSet` does real work.

- A module test that injects its `play:` closure proves the module calls
  *something*, not that anything is connected. Both of the first two modules
  shipped **silently mute** with a green suite: `playSample` is a no-op until
  `prepareSamplePlayback()` has run, and nothing called it. Anything whose
  effect leaves the process — audio, files, the network — needs one test that
  goes the whole way (`SamplePlaybackWiringTests`, `EndToEndPlaybackTests`)
  alongside the fast injected ones.

- A test that needs the real audio device does not belong in the default suite.
  XCTest runs suites in parallel processes that each build an `AudioEngine`, so
  a device-dependent test contends with them: measured at 20s alone and past 45s
  in the suite. Gate it behind `TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`. The
  same applies to reading anything outside the test bundle — see the sandbox
  note below.

- A unit test must not read a file outside the test bundle. The test host is a
  sandboxed app, so a read under `~/Documents` needs a Documents-folder grant,
  and a headless `xcodebuild` run has nobody to answer the prompt — the read
  blocks **indefinitely** and the suite stalls with no failure and no message.
  Mirror the values as literals and gate the live comparison behind
  `TEST_RUNNER_FRETWORK_WEB_REPO` (`NotePaletteTests`, `LearningModuleTests`).

- Graph building lives on `graphQueue`, never `controlQueue`. A device that
  stops answering blocks `AVAudioEngine.inputNode` inside
  `AudioDeviceCreateIOProcID` for as long as it likes — measured at 90+ seconds
  with an interface unplugged mid-session, and it never returned. While those
  shared one queue, every later control action queued silently behind it:
  changing device, monitor level, playing a note, and Retry all did nothing,
  while the window stayed responsive and made it look like audio had merely
  gone quiet. A watchdog reports at 4s (reconnecting) and 15s (error), because
  a `mach_msg` waiting on coreaudiod cannot be cancelled from here — the fix is
  to keep the rest of the app working and tell the player, not to abort the
  call. Anything added to `controlQueue` must be non-blocking.

- `AudioDeviceEnumerator.inputDevices()` costs **~30 seconds per call** in the
  test host when the microphone grant is missing, which it is after any reboot:
  the Debug build is ad-hoc signed, so TCC treats each rebuild as a new app, and
  a headless `xcodebuild` run has nobody to answer the prompt. It does not fail
  — it times out and returns. Spotting it is easy once known, because the
  durations come out as exact multiples of 30s (a test enumerating inputs twice
  takes 60s). Output enumeration is unaffected.

- Core Audio can reach a state where the app hangs **indefinitely** on
  startup, blocked in `mach_msg` inside `AudioDeviceCreateIOProcID` while
  binding a device — `AudioEngine.startSynchronously` never returns, so the
  control queue is stuck and nothing else it owns runs either. Symptoms that
  look unrelated but share this cause: the app at 0% CPU with a window that
  never populates, `prepareSamplePlayback` hitting its timeout, and any test
  touching `AppState()` taking exactly 60s (device enumeration blocking).
  Clear it with `sudo killall coreaudiod` or by replugging the interface. Since
  the queue split above, this degrades to "no audio, with an error" rather than
  a silently dead control surface.
  **`pkill -9` on the app is not the cause** — that was the obvious theory and
  it was tested directly: three launch/`SIGKILL` cycles left audio working
  every time, as did three clean-quit cycles. It has not been reproduced on
  demand, so do not spend a session hunting it; recognise it, clear it, move
  on. Note that the app has no timeout on that call, which is a real
  robustness gap rather than only a local nuisance.

- CPU alone is not a liveness signal for this app. A composited window with
  audio running measured 0.0% while `sample` showed two live
  `com.apple.audio.IOThread.client` threads, and an *occluded* window measures
  0.0% no matter what. To know whether audio is actually running, look for
  those threads in `sample <pid>`, not at `ps`.

- `pkill -f` takes an *extended* regex, so `\|` in its pattern is a literal
  pipe and matches nothing. The stale-process kill in Workflows was written
  that way and silently never killed anything; use an unescaped `|`. Verify a
  pattern with `pgrep -f` before trusting that a `pkill` did something.

- Resources under `Fretlight/` land **flat** in `Contents/Resources/`, because
  it is a `PBXFileSystemSynchronizedRootGroup` rather than a folder reference.
  The bundled note library lives at `Fretlight/Resources/NoteSamples/` in the
  repo and reaches the app as 138 bare `.m4a` files plus `index.json` beside
  everything else. Look them up by filename; a `subdirectory:` argument to
  `Bundle.url(forResource:)` finds nothing. Nothing had to be added to
  `project.pbxproj` for them to ship, which also means nothing warns you if a
  file lands there by accident.

- A take's *recorded* peak and its *shipped* peak are different numbers.
  Accepted takes are normalised to `TakeVerifier.normalizedPeak` on write,
  while the manifest deliberately stores the raw peak so pick force stays
  reviewable. 60 of the 138 masters are `peakFlagged`; that is a note about
  the performance, not a defect in the library. Don't re-record on the flag
  alone — check whether the thing it measures survives normalisation.

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
commit `vX.Y.Z` on `main`. Pushing that tag publishes a real release to real
users — `docs/releasing.md` covers the pipeline, how to test it without
publishing, and the two unrecoverable signing keys it depends on.

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
