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
2. Gate the detection workers on whether a visible screen consumes them, using
   the existing `setChordDetectionEnabled` pattern — `ChordAnalysisWorker` is
   already written so that an idle mode costs one `write` per render block
   rather than a running detector.
3. Ensure gating never reaches the restart path.

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

_Append phase-by-phase evidence here._
