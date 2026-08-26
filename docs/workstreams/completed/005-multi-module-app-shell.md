# Workstream 005: Multi-Module App Shell

## Objective

Turn a single-purpose window into a multi-screen app, with today's entire
experience preserved intact as its first screen.

## Required outcome

- Navigation between a listening screen and the learning modules, native to
  macOS rather than a port of the web's home-screen grid.
- "Listen" — the current `ContentView` in full, unchanged in behaviour — is the
  default screen at launch.
- Global settings that outlive navigation: input/output device, monitor,
  sensitivity, tuning.
- Audio keeps running across navigation. Switching screens must not restart the
  engine, re-prompt for the microphone, or drop the direct-monitoring path.
- Detection workers idle when no visible screen consumes them.
- Window minimums re-measured, not guessed.
- Per-module state restores through the workstream 001 practice-state document.

## Non-goals

- Module content (workstream 006). This ships the shell with placeholders.
- Redesigning the listening screen. It moves; it does not change.
- A preferences window, accounts, or sync.

## Verified findings driving this workstream

1. **The window is sized to one screen's needs.** `FretworkApp.swift` sets
   `minWidth: 1180, minHeight: 700`, both documented as measured rather than
   guessed: 1180 from the header's natural width at its tightest, 700 from the
   full stack including the board's 260 pt floor. A sidebar changes the first
   number and a different screen composition changes the second.
2. **`AppState` is a single `@MainActor @Observable` owner** wiring audio
   callbacks to published properties, and `CLAUDE.md` names it as *the* owner of
   UI state. Per-module state should hang off it or off child models it owns —
   not a second parallel state system.
3. **Observation cost is the known hazard.** `ContentView` splits every
   audio-rate read into leaf views on purpose, and `CLAUDE.md` records a measured
   `.pickerStyle(.segmented)` leak of ~1800 `ObservationRegistrar` contexts per
   30 s at 30 Hz, with per-update cost growing as uptime grows. A navigation
   chrome that re-renders at detection rate would reintroduce this at the
   top level.
4. **Device changes already restart the engine, with a debounce and an attempt
   cap** (`scheduleRestart`/`attemptRestart`), because an uncapped restart loop
   was a real bug. Navigation must not become a new trigger for that path.
5. **Sparkle's "Check for Updates…" lives in a `CommandGroup`** built around a
   single `WindowGroup`. Adding scenes must not detach that menu item.

## Execution contract

1. Work in phase order; the listening screen must work at every phase.
2. Gates after every phase: kill stale processes, `xcodebuild … test`,
   `git diff --check`.
3. Smoke-test after Phases 2 and 3 — both touch what runs while audio is live.
4. Measure every new minimum with the `NSHostingView` harness (workflow 4).
5. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline

1. Record `git status --short`, a clean test run, and smoke-test numbers.
2. Measure the current screen's natural size again, so a later regression is
   attributable.

## Phase 1 — Extract the listening screen

### Tasks

1. Move `ContentView`'s body into a `ListenScreen`, leaving `ContentView` as a
   container. No behavioural change, no restructuring of the leaf-view split.
2. Verify the detection experience is untouched.

### Exit criteria

- Visually and behaviourally identical; tests and smoke-test clean.

## Phase 2 — Navigation shell

### Files

- `Fretlight/Views/AppShell.swift` (new)
- `Fretlight/FretlightApp.swift`

### Tasks

1. Add a `NavigationSplitView` with Listen first and the ten modules listed in
   the web's pedagogical order.
2. Keep the sidebar entirely free of audio-rate reads — it is static chrome.
3. Preserve the Sparkle command group.
4. Re-measure `minWidth`/`minHeight` with the sidebar present and record both
   derivations in the source comment, matching the existing style.

### Tests and audit

- Smoke-test: navigating repeatedly does not restart the engine, climb CPU, or
  accumulate registrar contexts. Compare `heap` class counts against a fresh
  launch per `CLAUDE.md`, and keep the window composited — an occluded window
  measures clean regardless.

### Exit criteria

- Navigation works, audio is continuous across it, CPU is flat over time.

## Phase 3 — Global settings and worker gating

### Tasks

1. Lift device pickers, monitor, sensitivity and tuning into shell-level
   settings reachable from any screen, persisted through the practice-state
   document.
2. Promote the fretboard flip to a persisted global preference. It is currently
   a per-session `AppState` flag that resets on every launch, which is worse
   than either finishing or removing it — a player who prefers the
   player's-eye view has to re-flip it each time. With ten boards it must be
   one preference applied everywhere, not a per-board toggle. Derive the row
   count from the tuning rather than the hardcoded `5 - string`.
3. Gate the detection workers on whether a visible screen consumes them, using
   the existing `setChordDetectionEnabled` pattern — `ChordAnalysisWorker` is
   already written so that an idle mode costs one `write` per render block
   rather than a running detector.
4. Ensure gating never reaches the restart path.

### Exit criteria

- A module screen that needs no detection leaves the detectors idle.
- Settings survive navigation, relaunch and a device change.

## Phase 4 — Module placeholders and routing

### Tasks

1. Register all ten modules with title, blurb and a placeholder screen, sourced
   from the same catalogue the web keeps in `modules/catalog.json` so titles and
   order cannot drift between the two apps.
2. Restore the last-viewed screen only if that is wanted; the web deliberately
   does **not** persist its active module and always opens home. Decide, record
   the decision, and be consistent.

### Exit criteria

- All ten entries navigate to a placeholder that reads its own practice state.

## Phase 5 — Final gates

1. Build, test, smoke-test, direct launch of the archived build.
2. Update `CLAUDE.md` with the re-measured minimums and any new observation
   findings.
3. User-visible structural change with no learning content yet: hold the version
   bump for workstream 006 unless shipping standalone, and say so in the commit.

## Implementation Record

### Phase 0 — Baseline

Re-measuring the listening screen found a **pre-existing defect**: it needed
772pt of height against a declared window minimum of 700, so the window could
be dragged 72pt below what its contents fit in, forcing the fretboard under its
own 260pt floor. The 700 was derived honestly (682, rounded up) but the
derivation lived only in a source comment, so nothing failed when the screen
later grew. That is the real lesson: **a measured constant with no test is a
guess as soon as anything around it changes.** `WindowSizeTests` now re-renders
through an off-screen `NSHostingView` on every run.

### Phase 1 — Extract the listening screen

`ContentView`'s body moved verbatim into `ListenScreen`, with `ContentView`
kept as a thin container. The leaf-view split and its explanatory comments moved
with it untouched.

### Phase 2 — Navigation shell

`AppShell` wraps a `NavigationSplitView` around Listen plus the ten modules.
`LearningModule` mirrors `../fretwork/src/lib/modules/catalog.json` — ids,
titles, blurbs and order — and `LearningModuleTests` compares against that file
directly, skipping when the web repo is not checked out beside this one. It
earned its place immediately by catching a blurb reconstructed from truncated
terminal output.

**Audio start moved to `ContentView`.** It was in `ListenScreen`'s `.task`,
which was correct while that was the only screen: a screen's `.task` re-runs
every time the screen reappears, and `AppState.start()` is a full
stop-and-rebuild of the graph. Left there, every return to Listen would have
renegotiated the device, re-prompted for the microphone, dropped the
direct-monitoring path, and fed the restart path `AudioEngine` debounces and
attempt-caps because an uncapped restart loop was once a real bug.
`AudioEngine.graphBuildCount` now counts builds and
`AppShellNavigationTests` asserts navigation never moves it.

**`NSHostingView` cannot measure a `NavigationSplitView` off-screen** — it
reports 0 x 0, so "the declared minimum contains the shell" passed no matter how
wrong the number was. A vacuous assertion is worse than none, so the 0 x 0 is
now pinned by its own test and the minimum is *composed* from parts that can be
measured: the sidebar's declared floor plus the widest detail screen.

### Phase 3 — Global settings and worker gating

Devices, rescan, monitor, sensitivity, tuning and board orientation moved out of
the listening screen's header into `GlobalSettingsView`, reachable from the
shell's toolbar on every screen. The header keeps a read-only summary of the
signal path — the first thing to check when nothing is detected — and the
detection-mode control, which is that screen's own mode rather than a setting.

That move paid for itself in window size: seven controls in one non-wrapping row
were what made the window wide. The listening screen went from **1159pt to
727pt**, and the window minimum from 1359 to 927, rounded to **950 x 800**.

**Tuning became a real setting.** The document has carried `tuningID` since
workstream 001, but nothing ever read it back — the field was written and never
used. `AppState.tuning` now restores from it and persists changes.

**Board orientation moved into the document.** It was a per-session flag that
reset every launch, so a player who prefers the player's-eye view re-flipped it
each time; with a board on ten module screens it has to be one preference
applied everywhere. Decoding follows the existing field-by-field pattern, so a
document without the field — or with a malformed one — keeps every other
setting.

The tuning-derived row count this phase also asks for turned out to be **already
done**: `BoardGeometry` takes `strings` and every caller passes
`tuning.openMIDINotes.count`. Recorded rather than redone.

**Detection gating** flips the flag the workers already read, never a graph
rebuild — `testGatingNeverRebuildsTheGraph` asserts that, because reaching
`startSynchronously` from a screen change is exactly the failure this phase
exists to avoid.

### Phase 4 — Module placeholders and routing

All ten register with real title, blurb and board ceiling from the mirrored
catalogue. **Decision on restoring the last screen: it is not restored.** The
app always opens on Listen, matching the web app's deliberate choice to always
open home; reopening on a screen the player has forgotten they left is worse
than a consistent starting point. `testTheSelectedScreenIsNotPersisted` pins it,
including that the document has no field for it at all.

### Phase 5 — Final gates

Full suite **249 tests green**. Release build launches directly from its bundle
with no dyld failure, audio running (two live `com.apple.audio.IOThread.client`
threads).

Soaked for three minutes with the window composited: `ObservationRegistrar`
count flat at 27 throughout, memory flat at ~89 MB, CPU 6–10%. No accumulation.

**Version held**, as the phase instructs: this is a structural change with no
learning content behind it yet. 0.3.0 already covers the playback engine and
nothing here is a separate user-facing feature.

#### A long detour worth not repeating

Three times this session the app hung on launch, blocked in `mach_msg` inside
`AudioDeviceCreateIOProcID` waiting for a coreaudiod reply — 0% CPU, an empty
window, `prepareSamplePlayback` timing out, and any test touching `AppState()`
taking exactly 60s. The obvious theory was that `pkill -9` (which `CLAUDE.md`'s
workflow 3 recommends) left the device claimed. **Tested directly and it is
false**: three launch/`SIGKILL` cycles left audio working every time, as did
three clean-quit cycles, and the tests that had taken 60s each ran in 0.001s
once the condition cleared. It has not been reproduced on demand. Clear it with
`sudo killall coreaudiod` or by replugging, and do not go hunting it again.

Two measurement traps came out of that detour and are now in `CLAUDE.md`: CPU
alone is not a liveness signal for this app (a composited window with audio
running measured 0.0%, and an occluded one always does), and the app has **no
timeout** on that Core Audio call, which is a genuine robustness gap rather than
only a local nuisance.
