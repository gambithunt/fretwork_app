# Workstream 004: General-Purpose Fretboard View

## Objective

Generalise the fretboard from a detection display into the shared surface every
learning module draws on, and make today's detection board one of its consumers.

This is the highest-leverage piece of the port. Nine of the ten web modules
render through one `Fretboard.svelte`; without its Swift equivalent, every
module reinvents dot layout, animation and hit-testing.

## Required outcome

- A `FretboardView` taking a list of dots rather than detection results, where
  each dot carries: position, label, colour, stable id, radius, alpha, optional
  ring and ring alpha, optional outline, and label colour.
- Dots animate between layouts by **id**, so a changed selection slides existing
  dots to new positions instead of cross-fading everything.
- Per-dot pulse, driven by playback callbacks, so visuals and audio stay in time.
- Interaction: tap a dot, tap an empty cell, long-press a dot — each optional, so
  read-only boards stay read-only.
- Configurable fret count (12, 15 and 22 are all in use) and configurable
  tuning, with correct open-string labels.
- Overlays: grouping or sequence annotations across a set of dot ids.
- Keyboard navigation between positions.
- The existing detection board renders through it with no visible change, flip
  control included.
- Accessibility: the board is describable to VoiceOver, not an opaque canvas.

## Non-goals

- Module-specific content or controls (workstream 006).
- PNG export and sharing. The web's `fretboard-export.ts` composites its own
  image; on macOS that should later be `NSSharingServicePicker` and drag-out,
  and it is deliberately deferred.
- Changing detection behaviour or `FretPositionResolver`.

## Verified findings driving this workstream

1. **Today's board is display-only and detection-shaped.** `FretboardView` takes
   `mode`, `note`, `positions`, `chord` and `flipped`, and derives its markers
   internally from `ChordShapeResolver` in chords mode. Modules need to supply
   dots directly; the detection derivation moves up into a small adapter so the
   view itself stops knowing about `DetectionMode`.
2. **Useful drawing decisions already exist and should survive**: inlay frets
   drawn as a darker bar behind the column rather than as competing dots ("the
   grid is already made of dots, so a second kind would just read as noise"),
   one line weight and opacity so the board reads as a single grid, and strings
   that taper because real ones do.
3. **`flipped` is display-only by design.** Its docstring is explicit that
   `GuitarTuning`'s string indices never change and flipping only chooses which
   screen row each index draws at. Preserve that separation — the dot model must
   stay in string-index space, with flipping applied at layout time only.
4. **Animation is keyed on an identity string today** (`animationKey`, unified to
   `String?` so one `.animation(value:)` covers both modes). The dot-level model
   needs per-dot identity instead; `CLAUDE.md` warns that a value changing under
   an active `.animation()` garbles content unless it uses a proper content
   transition, so scope animations per dot rather than wrapping the board.
5. **A custom `View` that is also `Animatable` must mark `animatableData`
   `nonisolated`** — recorded in `CLAUDE.md` — which this view is likely to hit.

## Execution contract

1. Work in phase order. The detection board must keep working at every phase.
2. Gates after every phase: kill stale processes, `xcodebuild … test`,
   `git diff --check`.
3. Measure layout with the `NSHostingView`/`.fittingSize` harness per `CLAUDE.md`
   workflow 4. Do not guess a minimum size.
4. Read audio-rate state in leaf views only; the board is the single largest
   view in the app and the most expensive thing to invalidate needlessly.
5. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline

1. Record `git status --short`, a clean test run, and a screenshot of the
   current board in both modes and both flip states as the visual bar.

## Phase 1 — Dot model and geometry

### Files

- `Fretlight/Views/Fretboard/FretboardDot.swift`, `BoardGeometry.swift` (new)
- `Fretlight/Views/FretboardView.swift`

### Tasks

1. Define the dot model with all fields listed in Required outcome, including a
   stable id.
2. Extract geometry — string rows, fret columns, inlays, flipping, variable fret
   count and tuning — into its own testable type.
3. Keep the current visual language exactly: inlay bars, line weight, opacity,
   string taper.

### Exit criteria

- Geometry is unit-tested for 12, 15 and 22 frets, flipped and unflipped, and
  for a non-standard tuning's open-string labels.

## Phase 2 — Dot rendering and identity animation

### Tasks

1. Render dots from the model, animating position by id.
2. Support radius, alpha, ring, ring alpha, outline and label colour — these are
   what let Pentatonic and Note association layer boxes behind a focused one.
3. Implement per-dot pulse.

### Exit criteria

- Changing a dot set slides shared ids and fades only genuine additions and
  removals.
- No garbling under rapid changes; verify against the `.contentTransition`
  guidance in `CLAUDE.md`.

## Phase 3 — Interaction, overlays and accessibility

### Tasks

1. Optional dot tap, cell tap and dot long-press, following the semantics
   `Notes.svelte` defines: tap a button to toggle all positions of a note, tap an
   empty cell to place, tap a dot to hear it, long-press to remove one.
2. Overlays across dot id sets.
3. Arrow-key navigation between positions, porting
   `fretboard-key-navigation.ts`.
4. An accessible summary of what is on the board.

### Exit criteria

- A read-only board exposes no interaction; an editable one supports all four
  gestures.

## Phase 4 — Detection board as a consumer

### Files

- `Fretlight/Views/DetectionBoardAdapter.swift` (new)
- `Fretlight/Views/ContentView.swift`

### Tasks

1. Move the `mode`/`note`/`positions`/`chord` → dots derivation out of the view
   into an adapter, including the `ChordShapeResolver` lookup and the
   primary-versus-alternate position ranking.
2. Render the detection board through the general view.
3. Re-measure the window minimums; `FretworkApp.swift`'s 1180x700 was derived
   against the current composition and both numbers are documented as measured.

### Tests and audit

- Detection output is visually unchanged against the Phase 0 screenshots.
- Smoke-test per workflow 3 — this view is invalidated at detection rate.

### Exit criteria

- No visible change to the detection experience, and the board is now general.

## Phase 5 — Final gates

1. Build, test, smoke-test, direct launch of the archived build.
2. Update `CLAUDE.md` with any new layout or animation findings.
3. Pure refactor with no user-facing change: no version bump. Say so in the
   commit.

## Implementation Record

### 2026-08-25 — Complete

Phases 0–5 done. Full suite green; Debug and Release both build.

**Shipped** in `Fretlight/Views/Fretboard/`: `BoardGeometry` (string count, fret
count and label margins all parameters, plus hit-testing), `FretboardDot`,
`BoardCanvas` (the shared neck), `FretboardBoardView` (identity-keyed dot
animation, overlays, gestures, accessibility), `FretboardHitTest`,
`FretboardNavigation`, `FretboardOverlay`, `FretboardAccessibility`,
`DotMotionModifier` and `DetectionBoardAdapter`. `FretboardView` went from 296
lines to 57 and is now a thin consumer.

**Phase 4 was verified against pixels, not a diff.** `DetectionBoardSnapshotTests`
renders the detection board off-screen to PNGs when
`TEST_RUNNER_FRETWORK_SNAPSHOT_DIR` is set, and skips otherwise. Baselines were
captured before the rewire and compared after: all five cases — notes, notes
flipped, notes empty, chords, chords empty — are pixel-identical.

That oracle earned its keep immediately. The first rewire attempt looked
correct and placed every dot wrongly, because the dot carried both a
`.position` and a transition whose identity state also positions. 6240 pixels
differed at a max channel delta of 240. Nothing in a code reading would have
caught it. See the new Decisions row.

A second, smaller finding: swapping `.caption2.weight(.bold)` for a same-size
`Font.system` changed 0.023% of pixels. Invisible, but it proves the two are
distinct rasterisations, so `FretboardDotView` keeps the text style at the
default radius and scales only for the smaller dots the modules will ask for.

**Fixed while reviewing delegated work:** `FretboardOverlay.resolve` used
`Dictionary(uniqueKeysWithValues:)`, which traps on a duplicate dot id. A
duplicate is a module bug, but the honest failure for it is a misdrawn overlay,
not a crashed app.

**Not done:** the smoke test was inconclusive — the headless launch measured
~0.2% CPU, meaning the window was occlusion-throttled, which per Gotchas proves
nothing either way. No audio code changed in this workstream, and the pixel
comparison is the meaningful evidence for a view refactor.

**Not bumped:** no user-visible change. The detection board is pixel-identical
by construction; everything else is scaffolding for workstream 006.
