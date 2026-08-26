# Workstream 006: Learning Modules

## Objective

Port the web app's ten topics to SwiftUI, in pedagogical order, each reading its
theory from workstream 001, drawing through workstream 004's board, and sounding
through workstream 003's sampled engine.

## Required outcome

- Ten module screens, each restoring its last state from the practice-state
  document and resettable to defaults.
- Every module derives its content from the theory layer. No module
  reimplements interval, scale or chord arithmetic.
- Playback and visual pulses share one callback, so what is heard and what
  lights up cannot drift apart.
- Guided practice on Pentatonic and Scales: four-beat count-in, current and
  next-note emphasis, fretting finger, string/fret/note/degree readout,
  progress, tempo control, start and stop.
- Recall challenges where the web has them (Octaves).
- Progression playback where the web has it (Triads, Note association).
- Sessions are cancellable and cannot emit stale audio or UI updates after stop,
  navigation, selection change or screen disappearance.
- Guided playback state stays transient and is never persisted.

## Non-goals

- Microphone verification of what the player actually played — that is
  workstream 007, and it is what the whole port is building toward.
- PNG export and share (`fretboard-export.ts`, `FretboardShareDialog.svelte`).
  Defer; when it returns it should be `NSSharingServicePicker` and drag-out, not
  a hand-composited image.
- The web's routing, sitemap and SEO metadata — meaningless natively.
- Touch-sizing rules. The web's 40–44 px minimum exists because it is used on a
  tablet with a guitar nearby; macOS controls follow macOS conventions.

## Verified findings driving this workstream

1. **The web modules follow one skeleton** — `ModuleLayout` with `controls`,
   `stage` and `readout` snippets — and `fretwork/AGENTS.md` prescribes it.
   A Swift equivalent should exist before the second module, not after the
   fifth.
2. **`ButtonGroup` over dropdowns is a touch-driven product constraint**, not a
   design preference; it does not transfer. Use idiomatic macOS controls — but
   note `CLAUDE.md`'s measured `.pickerStyle(.segmented)` leak and avoid that
   style in anything rebuilt at audio rate.
3. **Colour comes from a shared palette.** The web reads CSS variables through
   `palette.ts`; the Mac has `NotePalette`, keyed by name string. Degree colours
   and role colours (root, third, fifth) need adding, and the keying should move
   to pitch class once workstream 001 lands.
4. **Two session engines already exist and are tested**: `guided-session.ts`
   (count-in, tempo presets 40–120, generation-token cancellation) and
   `progression-session.ts`. Port both engines and their tests before the
   modules that use them.
5. **The web's own limit is stated in its workstream 002**: "Microphone input,
   pitch detection, scoring, and wait-for-correct-note behavior are not
   included." Keep that boundary here so 007 is a clean addition rather than a
   rewrite.
6. **Module fret ceilings differ**: 12 for shared boards, 15 for Pentatonic and
   Chords, 22 for Triads. Carry each module's ceiling explicitly.

## Execution contract

1. Work in phase order. Each module is a phase; each ships complete before the
   next begins.
2. Gates after every phase: kill stale processes, `xcodebuild … test`,
   `git diff --check`.
3. Port each module's web tests with it.
4. Read audio-rate state in leaf views only.
5. Never persist timers, animation, count-in, active step or playback state.
6. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline and module scaffold

### Tasks

1. Record `git status --short` and a clean test run.
2. Build the Swift equivalent of `ModuleLayout`: a controls region, a stage
   holding the board, and a readout region for stats and theory copy.
3. Extend `NotePalette` with degree and chord-role colours.
4. Port `guided-session.ts` and `progression-session.ts` with their tests,
   including generation-token cancellation.

### Exit criteria

- The scaffold renders an empty module; both session engines pass ported tests.

## Phases 1–10 — The modules

In this order. Each phase: port the module, port its tests, restore and persist
its state, wire playback callbacks to dot pulses, and confirm cancellation on
disappearance.

| Phase | Module | Notes |
| --- | --- | --- |
| 1 | Notes | Simplest board; tap-to-place, chord discovery from placed notes, clear-all. Exercises every interaction path in workstream 004. |
| 2 | Intervals | Root plus one related note; anchor selection across the neck; the reference copy (feel, uses, exercise) ported from the theory layer. |
| 3 | Octaves | Movable two-string shape, tuning-honest fret offsets, plus the recall challenge. |
| 4 | Triads | Shapes and inversions, double-stops, string-set paths, progression playback. Largest of the reference modules. |
| 5 | Chords | Two-level family/formula selector, curated voicings, 15-fret board. |
| 6 | Pentatonic | Five canonical positions, single/pair/path display, guided practice. |
| 7 | Scales | One-octave shapes with fingerings, guided practice ascending and up-down. |
| 8 | Harmonizing | Degree row, diatonic chord per degree, compact voicing. |
| 9 | Note association | The capstone: layered chord/pentatonic/scale, progressions, loop. |
| 10 | Circle of fifths | The one non-fretboard module; SVG ring becomes a SwiftUI shape. |

### Per-phase exit criteria

- Module state restores across navigation and relaunch; reset returns defaults.
- Playback and pulses stay synchronised.
- Stopping, navigating away or changing a selection emits nothing further.
- Ported tests pass.

## Phase 11 — Final gates

### Tasks

1. Full build, test, smoke-test, direct launch of the archived build.
2. Verify CPU is flat across a long session with modules visited repeatedly —
   compare `heap` class counts against a fresh launch, window composited.
3. Update `CLAUDE.md` with module-level findings worth not rediscovering.
4. This is the feature workstream. Bump `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`, write the `CHANGELOG.md` entry, and tag per
   `CLAUDE.md`'s Versioning section.

## Implementation Record

### Phase 0 — Baseline and module scaffold

`ModuleLayout` is the Swift counterpart of the web's three-zone skeleton —
controls, stage, readout — plus `ModulePicker`, `ModuleStat` and `ModuleProse`.
The web's responsive rules do not come across: they exist because that app is
used on a tablet in portrait with a guitar in the way, and this is a Mac window
with a 950 x 800 floor.

**`NotePalette` re-keyed to pitch class** and given the role colours (root,
third, fifth, degree, pentatonic, outside-shape) plus the accent. Finding 3
said the keying should move once workstream 001 landed, and the reason is
concrete: a string key cannot survive the app spelling a note `A♯` in one place
and `B♭` in another. `PitchClass(name:)` was added to parse either spelling,
ASCII `#`/`b` included. Values are the web's hex verbatim rather than the
eyeballed approximations that were there before.

**Both session engines ported as one.** The web keeps `guided-session.ts` and
`progression-session.ts` as separate files with near-identical bodies; they
differ only in that a progression can loop and can hold a step for several
beats. `GuidedSession` takes those as parameters and `ProgressionSession` is a
typealias over it — one implementation of count-in, tempo rescheduling and
generation-token cancellation to keep correct instead of two kept identical by
hand.

The ported tests earned their keep immediately by catching a **real bug in the
port**. The web's `schedule()` calls `clearTimeout` before setting a new timer;
`Clock` has no cancellation, so rescheduling on a tempo change left the original
timer in flight *and* added a new one — the step fired twice, once at the old
interval and once at the new. The generation token does not catch this, because
a tempo change is not a new run. A per-schedule token does.

### Phase 1 — Notes

`NotesModuleModel` holds the rules, `NotesModuleScreen` presents them, and the
model is testable without rendering or audio. The board is both output and
input, and the point of the module is that the two ways of editing it produce
one set of dots: a note button is lit only when **every** position of that note
is on the board, so the buttons can never claim more than the board shows.

Playback and pulses share one callback, which is the required outcome about what
is heard and what lights up not drifting apart. Leaving the screen stops the
run; so does changing tuning, because a tuning change re-pitches every dot and
anything still sounding belongs to the old tuning.

Persisted through the practice-state document as `"string:fret"` keys, the web's
format exactly, so a saved board means the same thing in both apps. An empty
board survives a relaunch rather than being mistaken for "never set" and
refilled with the default Cs.

18 tests, covering both editing paths, deduplication between them, chord
discovery, enharmonic hints, tuning changes, and persistence.

### Two testing traps found along the way

**A unit test must not read a file outside the test bundle.** Both drift checks
originally resolved `../fretwork` from `#filePath` and read it directly. The
test host is a sandboxed app, so a read under `~/Documents` needs a
Documents-folder grant — and in a headless `xcodebuild` run there is nobody to
answer that prompt, so the read blocks **indefinitely**. The suite stalled after
260 tests with no failure and no message, twice, and the first theory was that
the audio stack had wedged again. `sample` on the test host is what showed it
parked in `webVariables`. Both checks now mirror the web's values as literals
for the everyday run and compare against the live repo only when
`TEST_RUNNER_FRETWORK_WEB_REPO` is set — the opt-in convention
`DetectionBoardSnapshotTests` already uses.

**A vacuous assertion is worse than none.** The first CSS parser passed
`.regularExpression` to one `range(of:)` and not the other, so the second was a
literal substring search for the pattern text, matched nothing, and produced an
empty table — every colour comparison then compared against nothing. It failed
only because a separate assertion happened to catch it. The parse count is now
asserted before anything is compared against it.

**The window minimum must not depend on attached hardware.** The listening
screen's new signal-path summary shows device *names*, and the window's minimum
width is derived from that screen's natural size — so plugging in an interface
with a long name silently widened the minimum window. Caught by
`WindowSizeTests` failing when the GP-200 was unplugged mid-session. The summary
is now width-capped and truncates in the middle.

### Status

Suite **286 passing, 0 failures**. Phases 2–10 (Intervals, Octaves, Triads,
Chords, Pentatonic, Scales, Harmonizing, Note association, Circle of fifths) and
Phase 11's final gates remain.
