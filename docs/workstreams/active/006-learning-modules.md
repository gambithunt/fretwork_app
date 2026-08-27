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

### Interlude — the launch hang, fixed

Phase 1's gates could not be run against the real app because it hung on
launch. The diagnosis in workstream 005 was incomplete: the *UI* was fine — the
main thread sat idle in the normal AppKit event loop the whole time — but
`AVAudioEngine.inputNode` was parked in `AudioDeviceCreateIOProcID` waiting on
a `mach_msg` reply from coreaudiod that never came, measured at over 90 seconds
with the interface unplugged mid-session.

The damage was that graph building shared `controlQueue` with the entire
control surface, so everything behind it stopped working **silently**: changing
device, monitor level, playing a note, and even Retry. The window stayed
responsive, which is exactly why it read as "audio went quiet" rather than "the
app is broken".

Graph build and teardown moved to their own queue, leaving `controlQueue`
non-blocking, so the player can still select a different device while a bad one
hangs — which is the action that actually recovers the app. A watchdog reports
at 4s (reconnecting) and 15s (error naming the device). It reports rather than
cancels, because a `mach_msg` waiting on coreaudiod cannot be aborted from
here.

Verified against the real misbehaving device: the graph queue sits stuck while
the control queue stays free, and control operations complete in 0.002s during
a stuck build. Worth knowing: binding a device id that cannot resolve *also*
hangs rather than erroring, so the watchdog is the only thing that reports at
all, not a backstop for an exotic case.

### Phase 2 — Intervals

`IntervalsModuleModel` plus `IntervalsModuleScreen`. The theory was already
there from workstream 001 — `Intervals` (feel, uses, exercise) and
`IntervalShapes` (anchors) — so this phase is mostly presentation and the rules
for keeping an anchor valid.

The module's idea is that an interval is a *shape under the hand*: the same
fifth is a different physical move depending on which string the root is on. So
the board draws three tiers — every root you could anchor on, recessed; the
chosen root, full size; and the notes it reaches, marked in the interval's
colour rather than the note's, because there they mean "a fifth away" rather
than "a G".

The rule that needed care is **re-anchoring**. A saved anchor can become
unreachable when the root, interval or tuning changes, and the module must snap
to the nearest playable one rather than going blank. Tests cover all three
changes across every root and every interval.

The interval's `short` is persisted rather than its index, so a catalogue that
gains an interval cannot silently re-point a saved selection, and an unknown
value falls back the same way the rest of the document does.

17 tests, including that every marked target is exactly the interval above the
anchored root **in pitch** — not merely in pitch class, since the module is
about a physical distance — and that no position is ever drawn twice across all
tiers.

### Interlude — the modules were silently mute

Reported by the user: no sound. The playback engine is gated behind
`prepareSamplePlayback()` so nobody pays 85 MB unless they open a module — and
**nothing ever called it**. `sampleLibrary` stayed nil, no player was attached,
and `playSample` is a silent no-op in that state. Every tap in Notes and
Intervals called into a gate that was never opened.

**306 passing tests could not catch it.** The module tests inject a `play:`
closure so they can run without an audio graph, and that closure was called
faithfully on every tap — the seam that makes the modules testable is exactly
where the bug lived. A green suite proved the modules called *something*, not
that the something was connected.

`AppState` now requests the library the first time a module is opened, which
keeps the memory off anyone who only uses the listening screen while making it
impossible to forget. Two test layers close the gap the module tests
structurally cannot: `SamplePlaybackWiringTests` (deterministic, no hardware)
asserts opening any module loads the library and the listening screen does not,
and `EndToEndPlaybackTests` goes `AppState` → `AudioEngine` → `SamplePlayer`
against a real device.

Silence is also no longer mysterious: a module now says *which* reason applies
when it cannot sound a note.

### Phase 3 — Octaves

`RecallChallenge` ports `recall-challenge.ts` — deliberately not a quiz that
marks you and moves on. A wrong answer goes to an `incorrect` phase you retry
from, so the round advances only once the shape has actually been recalled.

The module's substance is that **the fret offset is tuning-honest**. In standard
tuning the octave shape is "two strings up, two frets across" — except across
the G–B pair, where the major-third gap makes it three. A module drawing a fixed
+2 would be wrong on a third of the neck and still look plausible.

My first two tests here asserted the *wrong numbers*: I claimed the three-fret
case was rooted on strings 1–2 (it is 2–3), and that Drop D would stretch the
low-string shape to four frets when it in fact collapses it to **zero** — the
low string becomes a D, matching the D string, so the octave sits at the same
fret. Both are now derived and pinned: the human-facing literals (2, 2, 3, 3)
plus the invariant they come from, checked across all fifteen tunings.

16 tests, including that the target is hidden while the question stands, that a
wrong answer sounds the note actually picked (hearing that it is not an octave
is the correction), and that a tap mid-round cannot move the shape — otherwise
answering would change the question.

### Phase 4 — Triads

The largest reference module: two exercises sharing a screen, with their
settings kept apart in the document so returning to one does not disturb the
other.

- **Shapes** — one triad or double-stop in every compact voicing, inversions
  callable directly. Dots are coloured by *role* rather than pitch, because the
  lesson is which degree you are fingering.
- **Paths** — every diatonic triad of a key on one three-string set, walked up
  the neck and played back as a progression through the ported
  `ProgressionSession`.

Two more of my test expectations were wrong, both instructive. I asserted a path
walks the diatonic chords *in scale order*; it does not, and should not —
`TriadPaths.diatonicPath` sorts up the neck, because the exercise is to move the
harmony along one string set, so degrees interleave by position. The test now
asserts what the design actually promises: only the key's chords, each voiced
with its own notes, ordered by fret. And I asserted the progression leaves
`idle` synchronously when its state callback hops to the main actor — a real
finding, since the *UI* would have had the same lag and read as the button not
working. The snapshot is now taken synchronously at start as well.

24 tests, including that every voicing contains exactly the triad's notes, that
an inversion is the same notes with a different bass rather than a different
chord, that a voicing stays within a hand's span, that a path never leaves its
string set, and that any selection change stops playback — a progression left
running after a key change would play the old key's chords over the new key's
shapes.

### A test-suite lesson

`EndToEndPlaybackTests` needs the real default device, so under the full suite it
contends with the other test processes XCTest runs in parallel — each of which
also builds an `AudioEngine`. Measured at 20s alone and past 45s in the suite. It
is now opt-in behind `TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`: a
hardware-dependent test in the default run is flaky by construction, and a flaky
test teaches people to ignore red. The bug it was written for stays covered
deterministically by `SamplePlaybackWiringTests`.

### Phase 5 — Chords

The selector is two levels — family (core, sevenths, colour, extensions) then
formula — because sixteen formulas in one flat list is a wall.

**Muted strings are content, not absence.** A voicing's `frets` carries `nil`
for a string the conventional shape does not sound. A diagram that silently
omitted them would teach a chord you cannot actually strum, so they are
reported, named on screen, and skipped by the strum.

**Standard tuning only, and the screen says so.** `ChordVoicings` holds fixed
fret shapes, and `CLAUDE.md`'s rule is that a generator whose output is fixed
fret offsets must not accept a `Tuning` it cannot honour — those frets do not
transpose, they detune. Since tuning is now a global setting, the module shows a
notice when a non-standard tuning is selected rather than drawing a shape that
is quietly wrong.

The saved position is a voicing's own **id**, never an index: the list changes
length with the formula, so an index would silently land on a different shape.
Changing root or formula snaps to the shape nearest the nut.

16 tests. The two that carry the weight run every formula against every root and
assert that each sounded string carries a degree the formula actually contains,
and — from the other direction — that every dot's pitch class is one of the
chord's. A `?` label would mean the shape contains a note the chord does not.

### Phase 6 — Pentatonic

Five two-notes-per-string boxes, shown one at a time, as a pair, or as a
three-box path with the focus in the middle. Neighbours are drawn recessed and
unlabelled: they exist to show how the boxes join, and a fully-labelled neck is
a wall of dots rather than a shape.

First module with **guided practice** — the `GuidedSession` ported in Phase 0
drives it: four-beat count-in, one note per beat, live tempo, and a readout of
string, fret, note, degree, fretting finger and what is coming next.

**A 0-based/1-based mistake, caught by the tests.** `ScaleShapes.pentatonicPosition`
indexes its pattern table directly, so positions are 0–4 — and the web's saved
default is `position: 0` for the same reason. I wrote the model as 1–5, which
made box 5 silently empty and shifted every other box by one: `selectPosition(1)`
showed box 2. Two tests caught it — "every box is two notes per string" and
"every box contains only scale notes" — because a shifted box is still a
plausible-looking pentatonic shape, just the wrong one. Positions are now 0-based
throughout and converted to 1-based only for display.

Standard tuning only, and now said out loud: `StandardTuningNotice` appears on
this module and on Chords when a non-standard tuning is selected globally.
`CLAUDE.md` records that the tuning-parameterisation error slipped into this
generator twice, so the scale-membership assertions run every root against every
box in both qualities, cross-checked against intervals derived independently of
the generator.

18 tests, including that the five boxes together cover the whole scale (no note
unreachable from any position), and that A minor and C major pentatonic come out
as the same five notes.

### Phase 7 — Scales

One-octave major and natural-minor shapes: seven degrees plus the root again on
top, which is what makes a run sound finished rather than stopped. Labels switch
between note names (for learning the neck) and degrees (for learning the scale),
and a run goes up or up-and-back-down.

**This generator does take a tuning**, unlike Pentatonic and Chords.
`ScaleShapes.oneOctaveScale` derives every note from MIDI rather than from fixed
fret offsets, so it transposes honestly instead of detuning — which is why the
two have different signatures, and a test asserts each note's pitch really does
come from the tuning in use.

`GuidedPresentation` ports `guided-presentation.ts` and is now shared with
Pentatonic: mid-run the note to play carries its **fretting finger** instead of
its label, the next note is visible but recessed, and everything else dims to
context. The emphasis *is* the instruction. It applies only while playing —
during the count-in the whole shape stays legible, which is what the count-in is
for.

**A bug caught while wiring that up.** The decorator was given the *shape* while
the snapshot's index counts positions in the *run*. In up-and-down mode the run
is nearly twice as long, so on the way back down it would have emphasised the
wrong note, or none at all once the index ran past the shape's end. It now takes
the run, and a test walks a descending index to prove exactly one note is
emphasised and that it is the right one.

Relabelling deliberately does **not** stop a run — it is a change of view, not
of what is being practised — while changing root, quality, direction or tuning
does.

17 tests, including that minor really is major with a flattened 3rd, 6th and
7th, and that an up-and-down run does not sound the top note twice (the thing
that makes a practice run sound like a stumble).

### Phase 8 — Harmonizing

Pick a key and a degree, and see the chord that falls out of it. The three
stacked scale tones sit beside the chord because they are the *reason* it is
what it is: the chord is the consequence, the stack is the cause.

13 tests, asserting the claim rather than the module's own output — the chord at
each degree must be the set of its three stacked scale tones, and the quality
patterns (major: maj, min, min, maj, maj, min, dim; and the minor equivalent)
must hold in all twelve keys. One more checks a relative major and minor come
out as the same seven chords.

### Phase 10 — Circle of fifths

The one module whose stage is not a fretboard. A ring of twelve keys with the
relative minors on an inner ring, and the selected key's tonic triad on a small
board beside it so the diagram stays connected to the instrument.

The tests assert that the arrangement *means* something, because a ring drawn in
the wrong order still looks like a circle of fifths: every step clockwise is a
fifth, **neighbouring keys share six of their seven notes**, and the key
opposite shares the fewest of any — checked against all eleven others, from
every starting key. One test states the same fact musically: I–IV–V are three
adjacent keys on the ring, which is why those three chords hold so many songs
together.

### Phase 9 — Note association

The capstone: the whole key on one neck at once, each note coloured by what it
is doing over the chord sounding *now* — chord tone, pentatonic, or the rest of
the scale.

**The layering is the lesson, and the test that matters says so directly.**
`testChangingChordRecoloursWithoutMovingAnyDot` asserts that changing the chord
leaves every dot exactly where it was while changing their colours. A dot that
moved would be teaching the opposite of the point: you are not learning where
the notes are, you are learning what they *mean* at a given moment.

Precedence between layers is explicit and tested: a chord tone stays a chord
tone even when it is also in the pentatonic, because while that chord sounds
that is the stronger fact. A note in both keeps its chord colour and gains a
pentatonic ring, so neither fact hides the other.

Each layer can be switched off, because chord tones alone is arpeggio practice,
pentatonic alone is where most solos live, and all three together is what an
improviser is actually seeing. Layer and label changes are view changes and
deliberately do **not** stop playback; changing key, chord or progression does.

A progression written only for major falls back rather than appearing empty when
the key switches to minor — `Progressions.resolve` returns nothing for a mode a
progression was not written for, on the grounds that a ii–V–I borrowed into
minor is a different progression rather than this one relabelled.

15 tests.

### Phase 11 — Final gates

`CLAUDE.md` gained five Decisions rows and three Gotchas from the port: where a
module's rules live, persisting a thing's id rather than its index, checking a
generator's 0-based convention rather than the UI's numbering, giving
`GuidedPresentation` the run rather than the shape, and saying out loud when a
module's fixed shapes do not fit the selected tuning. The Gotchas record the
three testing traps — an injected closure proving only that the module calls
*something*, a device-dependent test in the default suite, and a unit test
reading outside the test bundle.

Version bumped to **0.4.0 / build 4** with a `CHANGELOG.md` entry.

**A test of mine was poisoning the suite.** `AudioEngineWatchdogTests`
deliberately binds a device id that cannot resolve — the pathological Core Audio
path the watchdog exists to report. Measured, that does not stay inside its own
process: it left the HAL unwilling to answer for the other test processes XCTest
runs in parallel, and the full run stalled after 411 passing tests with no
failure and no message. It is now opt-in behind
`TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`, alongside `EndToEndPlaybackTests`.
A test that deliberately wedges a device cannot share a machine with tests that
need one.

| Gate | Result |
| --- | --- |
| Deterministic suites (27 of them, every module) | **305 passed, 0 failed** |
| Full suite | reaches 408–411 passed, **0 failed**, then stalls in device enumeration |
| Release build | succeeds |
| Direct launch of the Release bundle | launches, no dyld failure, 22 MB |
| `git diff --check` | clean |

**Update after the machine was restarted: every gate now passes**, and chasing
the last two failures found two real defects. What follows was written while the
audio stack was still wedged.

**The full-suite gate was not met at the time, and the reason was the machine
rather than the code.** Its audio stack has been wedged since before this phase: any
`AudioObjectGetPropertyData` against the HAL blocks, so every suite that
constructs an `AppState` stalls in `AudioDeviceEnumerator`. Nothing fails —
tests simply never return. It needs the reboot that has not happened yet
(`uptime` shows six days). **No tag has been created**: pushing one publishes to
real users, and this version has not passed its own gates.

### Phase 11 (continued) — after the restart

With a healthy audio stack the full suite runs clean, and the two failures that
remained turned out to be real defects rather than machine noise.

**1. The note library was queued behind device binding.** `prepareSamplePlayback`
decoded the 138 files on `graphQueue`. Reading them needs no audio device at
all, but sitting behind a build meant a device that never answered also stopped
the library from ever loading: measured, `isSampleLibraryLoaded` stayed false
indefinitely, so every module reported "no audio device" when in truth only the
output was missing and the library could have been ready the whole time. It now
decodes on its own queue and only the *attach* touches the graph.

**2. Selecting another device did not recover from a hung one — the claim made
when the queues were split was wrong.** Splitting `controlQueue` from
`graphQueue` kept volume and note triggers alive, but choosing a different
device is *itself* graph work and queued behind the hang. Measured: after a hung
bind, selecting working hardware never took effect (90s, no recovery). Now a
submission arriving while a build is in flight gets a **fresh queue**, and the
abandoned build refuses to install its engines because every build checks its
generation before touching shared state. The same test now recovers in 0.143s.

Also: the device fallback took the *first enumerated* device, which on a machine
with a monitor attached is often the monitor's DisplayPort audio — measured here
binding something that never returned. It now prefers the system default, which
is what a person means by "my speakers".

| Gate | Result |
| --- | --- |
| Full suite | **437 passed, 0 failed** |
| `EndToEndPlaybackTests` (opt-in, alone) | passes, 0.32s |
| `AudioEngineWatchdogTests` (opt-in, alone) | passes, including the new recovery test |
| Release build + direct launch | succeeds, no dyld failure, 22 MB |
| `git diff --check` | clean |

One thing to know when launching a fresh build: the Debug and Release binaries
are ad-hoc signed, so TCC treats each rebuild as a new app and re-prompts for
microphone access. Until that prompt is answered the app sits waiting on the
input device — which looks exactly like the hang above but is just an unanswered
dialog.

### Status — workstream complete

Phases 1–11 are complete and every gate passes.
