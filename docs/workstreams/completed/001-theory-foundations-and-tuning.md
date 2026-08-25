# Workstream 001: Theory Foundations and the Tuning Model

## Objective

Port the web app's music-theory layer into Swift, and remove the standard-tuning
assumption that is currently hardcoded throughout `Pitch/`.

This workstream ships no UI. It exists so that every later module derives its
notes, intervals, scales, chords and fret positions from one verified place,
the way `src/lib/theory.ts` serves that role on the web.

## Required outcome

- A `Theory/` layer providing: pitch classes and note naming, interval
  definitions, scale formulas and spelling, triads, the 16-entry chord formula
  catalogue, diatonic harmony, the circle of fifths, progressions, and
  position-finding helpers (`findAll`, `firstPosition`, `compactVoicing`).
- Canonical shape data ported: five pentatonic patterns with fretting fingers,
  one-octave major/natural-minor shapes, CAGED and movable chord voicings,
  triad voicings, double-stops, triad paths, interval and octave anchors.
- A `Tuning` value type carrying all 15 web tunings, threaded through every
  place that currently assumes standard tuning.
- Chord discovery (notes on a board → chord name and inversion) available as a
  pure function, distinct from the audio-driven `ChordDetector`.
- A versioned, `Codable` practice-state document replacing the ad-hoc
  `UserDefaults` keys, with validation and per-module reset.
- One note-naming convention across the whole app.
- Ported tests pass, including the web suite's shape and spelling assertions.

## Non-goals

- Any SwiftUI. No views, no navigation, no module screens.
- Audio playback, sample handling, or changes to the capture graph.
- Changing detection behaviour. `PitchDetector`, `ChordDetector` and
  `ChordAnalysisWorker` keep their current results; only the tuning they
  resolve *against* becomes configurable.
- Porting `fretboard-export.ts` or the share dialog.

## Verified findings driving this workstream

1. **String order is inverted between the two apps, in the data.** Web
   `STANDARD_TUNING[0]` is high e and `[5]` is low E (`fretwork/AGENTS.md`
   states this explicitly as a gotcha). Mac `GuitarTuning.openMIDINotes` is
   `[40, 45, 50, 55, 59, 64]` — string 0 is Low E. Every ported fret array is
   affected: chord shapes (`[0, 1, 0, 2, 3, null]` for the C shape), every
   pentatonic pattern, every triad voicing. A reversed array is still a
   plausible-looking shape, so this will not announce itself.

   **Display orientation is a separate concern and is already handled.**
   `BoardGeometry.y(string:)` now draws Low E at the bottom by default,
   matching the web's `stringY`. That changes nothing here: `GuitarTuning`'s
   indices are unaffected, so ported fret arrays still need reversing on the
   way in. Do not treat the display fix as covering this finding.
2. **Note naming diverges.** `NoteMapper.pitchClassNames` uses `"C♯"` (U+266F);
   the web uses `"C#"`, plus a flat table and `spellScale`'s letter-per-degree
   spelling for theory-correct names like E♯ in F♯ major. `NoteMapper`'s
   docstring notes the table is shared with `ChordDetector` and
   `ChordShapeResolver` "so the three don't drift" — that sharing must survive.
3. **Tuning is hardcoded in three places.** `GuitarTuning.openMIDINotes` is a
   `static let`; `GuitarTuning.positions(forMIDI:fretCount:)` reads it directly;
   `FretPositionResolver.resolve` calls that helper; `ChordShapeResolver`'s
   shape library is standard-tuning fret arrays.
4. **The web app does not fully honour its own tuning picker.** Chord voicings
   and pentatonic patterns are standard-tuning shapes transposed by pitch class,
   regardless of selected tuning. Port the honest behaviour: shapes that are
   genuinely tuning-derived (intervals, octaves, `findAll`) follow the tuning;
   curated standard-tuning shapes are marked as such rather than silently wrong.
5. **Persistence today is six loose keys.** `sensitivity`,
   `selectedInputDeviceUID`, `selectedOutputDeviceUID` and a legacy numeric ID
   path, read and written inline in `AppState`. There is no schema, no version,
   and no validation.

## Execution contract

1. Work in phase order. Do not begin a later phase while the current phase's
   build or test gate fails.
2. Gates after every phase:
   - `pkill -9 -f "Fretwork.app/Contents/MacOS\|Fretlight.app/Contents/MacOS"`
   - `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test`
   - `git diff --check`
3. Port the web tests alongside the code. A ported table without its ported
   test is not done — the tests are the only defence against finding 1.
4. Keep theory data in `Theory/`. Modules must not reimplement interval
   arithmetic, exactly as `fretwork/AGENTS.md` requires of its modules.
5. `Pitch/` stays free of Core Audio and of SwiftUI, as it is today.
6. Preserve unrelated worktree changes.
7. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline and naming decision

### Tasks

1. Record `git status --short` and a clean test run.
2. Decide the single note-naming convention and write it down here before any
   porting. The recommendation is: store pitch classes as `Int` 0–11
   everywhere; render names through one formatter that can produce sharp, flat
   or theory-spelled output. Display keeps `♯`/`♭` typography; no stored string
   carries an accidental.
3. Confirm the fret ceiling per context: the detection board is 22 frets, web
   shared boards are 12, pentatonic and chord boards 15, triads 22. Fret count
   is a parameter, never a constant baked into a shape table.

### Exit criteria

- The naming decision is recorded and no code has changed yet.

## Phase 1 — Pitch-class core and note naming

### Files

- `Fretlight/Theory/PitchClass.swift`, `NoteName.swift` (new)
- `Fretlight/Pitch/NoteMapper.swift`
- `FretlightTests/` — ported from `fretwork/src/lib/theory.test.ts`

### Tasks

1. Introduce the pitch-class type, sharp/flat tables, `enharmonicAlias`, and
   `spellScale`'s letter-per-degree algorithm.
2. Reroute `NoteMapper.pitchClassNames` through the new formatter without
   changing what `ChordDetector` and `ChordShapeResolver` observe. These three
   share one table today; they must share one formatter tomorrow.
3. Port the scale, interval, triad and chord-formula catalogues, including the
   web's reference copy (`feel`, `uses`, `exercise`, chord `description`) — the
   modules render that text and it is not worth rewriting.

### Exit criteria

- Detection output is byte-identical to before for every existing test.
- `spellScale` reproduces the web's spellings, E♯ in F♯ major included.

## Phase 2 — The tuning model

### Files

- `Fretlight/Theory/Tuning.swift` (new)
- `Fretlight/Pitch/GuitarTuning.swift`
- `Fretlight/Pitch/FretPositionResolver.swift`
- `Fretlight/Pitch/ChordShapeResolver.swift`

### Tasks

1. Add a `Tuning` value type: id, display name, and open MIDI notes in Mac
   string order (index 0 = Low E). Port all 15 web tunings, reversing each
   `lowToHigh` array — the web's `defineTuning` reverses on input, so the raw
   literals in `tunings.ts` are already low-to-high and map directly.
2. Replace `GuitarTuning`'s statics with tuning-parameterised functions,
   keeping a standard-tuning default so nothing existing breaks at the call
   site.
3. Thread the tuning into `FretPositionResolver.resolve`. Note its docstring's
   claim that positions for one pitch are never closer than 4 frets apart "(2 in
   DADGAD, the tightest of the common tunings)" — that bound is already stated
   per-tuning, so the resolver's heuristics hold, but re-verify it across all 15.
4. Mark `ChordShapeLibrary` explicitly as standard-tuning-only, and make it
   return no shape rather than a wrong one under another tuning.

### Exit criteria

- Every tuning resolves positions correctly for a spot-checked set of pitches.
- Detection under standard tuning is unchanged.
- No `static let` open-string table remains reachable from production code.

## Phase 3 — Canonical shape data

### Files

- `Fretlight/Theory/ScaleShapes.swift`, `ChordVoicings.swift`,
  `TriadVoicings.swift`, `TriadPaths.swift`, `IntervalShapes.swift`,
  `OctaveShapes.swift` (new)
- ported tests for each

### Tasks

1. Port the five pentatonic patterns with their `aMinorBase` and per-note
   fretting fingers, the one-octave scale shapes, CAGED and movable chord
   shapes, triad voicings, double-stops and triad paths.
2. **Reverse every fret array's string order on the way in** (finding 1), and
   assert the reversal in the ported tests rather than trusting the transcription.
3. Port interval and octave anchor resolution, including the nearest-anchor
   distance metric (`|Δfret| + |Δstring| * 2`).
4. Keep the transposition logic generative as the web has it — these are
   patterns plus a shift, not 12 copies per root.

### Exit criteria

- Every ported shape matches its web counterpart under a test that maps
  explicitly between the two string orders.
- Shapes stay inside their declared fret ceiling for all 12 roots.

## Phase 3c — Diatonic harmony and position helpers

### Context

Phase 1 explicitly deferred these, and neither half of Phase 3 claimed them, so
as written this workstream leaves them with no home. `TriadPaths` already
depends on the gap: the Swift port takes a single triad explicitly, where the
web's `getTriadPath` walks all seven diatonic chords of a key. That is a
correct partial port, not a finished one, and it must not be mistaken for done.

### Files

- `Fretlight/Theory/Harmony.swift`, `Fretlight/Theory/Positions.swift` (new)
- `Fretlight/Theory/TriadPaths.swift`
- ported tests

### Tasks

1. Port `MAJOR_HARMONY`, `MINOR_HARMONY`, `ROMAN_MAJOR`, `ROMAN_MINOR`, the
   `DiatonicChord` type and `diatonicChords`.
2. Port `CIRCLE_OF_FIFTHS`, `PROGRESSIONS`, `getProgression` and
   `resolveProgression`.
3. Port `keyScalePcs` and `keyPentaPcs`.
4. Port `compactVoicing`, tuning-parameterised rather than assuming standard.
   (`findAll` and `firstPosition` move forward into Phase 3b, which cannot
   build interval or octave anchors without them.)
5. Complete `TriadPaths` with the diatonic walk, keeping the single-triad
   entry point if it still earns its place.

### Exit criteria

- `TriadPaths` reproduces the web's step ordering for a spot-checked key and
  string set.
- Nothing in `theory.ts` remains unported except what a later workstream
  explicitly owns.

## Phase 4 — Chord discovery

### Files

- `Fretlight/Theory/ChordDiscovery.swift` (new)
- ported tests from `fretwork/src/lib/chord-discovery.test.ts`

### Tasks

1. Port board-notes-to-chord-name recognition, with the web's status vocabulary
   (`empty`, `insufficient`, `partial`, `match`, `unknown`), inversion naming
   and alternative matches.
2. Keep it entirely separate from `ChordDetector`. That one answers "what is
   being strummed" from audio chroma; this answers "what have you placed on the
   board" from exact positions. They share formulas, not code paths.

### Exit criteria

- Web test cases reproduce, inversion labels included.

## Phase 5 — Versioned practice state

### Files

- `Fretlight/Models/PracticeState.swift` (new)
- `Fretlight/Models/AppState.swift`

### Tasks

1. Define a `Codable`, versioned document covering per-module settings and the
   global tuning choice, mirroring `PersistedPracticeStateV1`.
2. Migrate the existing loose keys (`sensitivity`, the two device UIDs, and the
   legacy numeric device ID) into it without stranding a current user's saved
   device selections or microphone-relevant settings.
3. Invalid, partial, corrupt or future-version documents must never break
   launch — fall back to defaults per the web's contract.
4. Provide per-module reset.
5. Persist only user-controlled state. Never persist detection output, levels,
   timers, animation or playback state.

### Exit criteria

- A corrupt document, an unknown version and a missing document all launch
  cleanly on defaults.
- Existing device and sensitivity selections survive the upgrade.
- Round-trip tests cover every module's settings.

## Phase 6 — Final gates

### Tasks

1. Full build and test run.
2. Smoke-test per `CLAUDE.md` workflow 3 — this workstream touches
   `FretPositionResolver`, which is on the audio-driven path, so confirm CPU is
   flat and no `kAudioUnitErr_*` appears.
3. Update `CLAUDE.md`'s Decisions/Gotchas with anything learned, particularly
   the string-order inversion.
4. This is foundation work with no user-visible feature, so no version bump.
   Note that in the commit rather than bumping.

## Implementation Record

### 2026-08-25 — Complete

Phases 0–6 done. Full suite green; smoke-tested per Workflows 3 with no Core
Audio errors and CPU in the ~13% band recorded for a healthy fresh launch.

**Shipped:** the `Fretlight/Theory/` layer — pitch classes and naming,
intervals, scales with theory-correct spelling, chord formulas, all 15 tunings
threaded through `GuitarTuning`/`FretPositionResolver`/`ChordShapeResolver`,
canonical pentatonic and one-octave shapes, CAGED and movable chord voicings,
triad voicings, double-stops, triad paths, interval and octave anchors,
diatonic harmony, progressions, the circle of fifths, chord discovery, and a
versioned `PracticeState` document replacing the loose `UserDefaults` keys.

**Two live bugs found and fixed on the way:**

- Restored `sensitivity` was never applied. Property observers do not fire for
  a value assigned in the type's own `init`, so the slider showed the saved
  value while the detector ran at its 0.5 default all session. Now in Gotchas.
- The stale-process `pkill` documented in Workflows matched nothing — `pkill
  -f` takes an extended regex, so its `\|` was a literal pipe. Now in Gotchas.

**Recurring defect worth naming:** twice a generator of fixed fret offsets
accepted a `Tuning` it could not honour (`ChordShapeLibrary`, then
`ScaleShapes.pentatonicPosition`). Both now refuse one. See the Decisions row.

**Deferred:** per-module reset (Phase 5). `PracticeState.Modules` is
deliberately empty until workstream 006 adds the first module, so there is
nothing to reset yet; build the mechanism against a real consumer.

**Not bumped:** the theory layer is unreachable from the UI, but the
sensitivity fix is user-visible — see the note in the handover about whether
this warrants a PATCH release on its own.
