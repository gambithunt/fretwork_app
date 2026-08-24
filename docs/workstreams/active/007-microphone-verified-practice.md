# Workstream 007: Microphone-Verified Guided Practice

## Objective

Close the loop the web app cannot close: stop showing the player a note and
hoping, and instead wait until they actually play it.

The web repo's own guided-practice workstream states the boundary explicitly —
"Microphone input, pitch detection, scoring, and wait-for-correct-note behavior
are not included." Every one of those is already working in this app. This
workstream is the reason the port is worth doing at all.

## Required outcome

- A guided session can advance on **detection** rather than on a timer: show the
  target, wait, advance when the player plays it.
- Both modes available: timed (as ported in workstream 006) and wait-for-correct,
  chosen per session.
- Correctness accounts for what the detector can and cannot know: pitch is
  reliable, exact fretboard position is inferred. A player who plays the right
  pitch at a different position must not be told they are wrong.
- Chord practice verified against `ChordDetector`.
- Intonation feedback from the existing cents reading, so a note that is right
  but flat is distinguishable from a wrong note.
- Per-session results: attempts, hesitation, and which positions repeatedly go
  wrong.
- Detection is not fooled by the app's own playback.

## Non-goals

- Grading, scores, streaks, gamification or long-term progress tracking beyond a
  single session's results.
- Detecting *which* finger was used, or anything a camera would be needed for.
- Changing the detector's algorithms. This consumes existing detection output.

## Verified findings driving this workstream

1. **The detector reports pitch, not position.** `FretPositionResolver`'s
   docstring is explicit: "Pitch alone can't say which of these was actually
   played — 79% of the notes in range have more than one, and some have five,"
   and its estimate is deliberately causal, so "a sudden jump to a new position
   is guessed from stale information and takes a note or two to recover." That
   case is named as "the gap a camera watching the hand would fill." Verification
   must therefore be **pitch-based**, using the resolver's position only as a
   hint — never as the pass/fail criterion. Failing a player for a position the
   app inferred wrongly would be the worst possible defect here.
2. **Feedback through speakers is a real hazard.** Unlike workstream 002's DI
   recording, this path uses whatever input the user has selected, and the app
   now plays samples out of the output device. If those are speakers and a
   microphone, the app will hear its own demonstration note and can credit the
   player for it. Gating the analysis workers across playback windows is the
   cheap correct fix — the app knows exactly when it is playing. Headphone use
   should be recommended, not required.
3. **There is already a hold and a median filter in the detection path.**
   `AudioAnalysisWorker` keeps a five-deep MIDI history, takes its median, and
   holds the display for 180 ms through "the naturally aperiodic final cycles of
   a decaying guitar note." Verification must be built on that stabilised value,
   not on raw per-frame results, or a legitimate note will register as several.
4. **Repick detection already exists.** `AppState.detectRepick(level:note:)`
   distinguishes a re-struck note from a sustained one — necessary for counting
   two of the same note in a row as two events, which any scale run needs.
5. **Sensitivity is one user-facing dial mapped to two detector thresholds**
   (`SensitivitySettings`). Verified practice must not expose new raw detector
   knobs; if practice needs different strictness, it maps onto the same dial or
   gets its own single documented dial, per the pattern `CLAUDE.md` prescribes.
6. **Chord detection has a confidence floor and a complexity margin**
   (`ChordDetector.minimumConfidence` = 0.55, `complexityMargin` = 0.1) and nine
   qualities. Chord verification must accept the shape the player actually
   fingered, including a valid alternative voicing of the same chord.

## Execution contract

1. Work in phase order.
2. Gates after every phase: kill stale processes, `xcodebuild … test`,
   `git diff --check`.
3. Smoke-test after any phase touching the analysis path or playback gating.
4. Verification logic lives in `Pitch/` or a new pure layer — testable without
   Core Audio, like every other detection-adjacent decision in this codebase.
5. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline and the correctness contract

### Tasks

1. Record `git status --short`, a clean test run and smoke-test numbers.
2. Write the correctness contract down before implementing it:
   - What counts as playing the target note (pitch match, tolerance in cents,
     how long it must hold).
   - What happens when the right pitch is played at the wrong position.
   - What counts as a wrong note versus no note yet.
   - How long the session waits before offering a hint.
3. Decide the intonation tolerance separately from the correctness tolerance — a
   note can be correct and still be told it is flat.

### Exit criteria

- The contract is written and reviewed. No code changed.

## Phase 1 — Playback gating

### Files

- `Fretlight/Audio/AudioEngine.swift`
- `Fretlight/Audio/AudioAnalysisWorker.swift`, `ChordAnalysisWorker.swift`

### Tasks

1. Gate the analysis and chord workers across playback windows, with a short
   tail past the end of playback to cover speaker decay.
2. Gating must not disturb the monitor path, the direct-monitoring selection, or
   the restart logic.
3. Make the gate observable so the UI can say "listening" versus "playing"
   honestly rather than appearing to ignore the player.

### Tests and audit

- Synthetic playback during a gate produces no detection events.
- Smoke-test: latency, buffer size and CPU unchanged.

### Exit criteria

- The app cannot detect its own output.

## Phase 2 — Note verification

### Files

- `Fretlight/Pitch/PracticeVerifier.swift` (new)

### Tasks

1. Consume the stabilised detection output — median-filtered MIDI plus the hold
   window — and decide target-met, wrong-note, or nothing-yet.
2. Accept the right pitch at any position. Report the resolver's position as
   information only.
3. Use `detectRepick` so a repeated target note counts twice.
4. Report intonation from the smoothed cents value, separately from correctness.

### Tests and audit

- Deterministic tests over recorded or synthetic detection sequences: correct
  note, correct note at another position, wrong note, silence, sustained note
  mistaken for two, two genuine repicks.

### Exit criteria

- Verification is fully testable without any Core Audio.

## Phase 3 — Wait-for-correct sessions

### Files

- guided-session engine from workstream 006

### Tasks

1. Add an advance-on-detection mode alongside advance-on-timer, sharing one
   session state machine and one cancellation model.
2. Handle the player who stops: a session waiting indefinitely must remain
   cancellable and must not hold audio or timers.
3. Offer a hint after the configured wait, and allow skipping a step.

### Exit criteria

- Both modes run through the same engine; stopping emits nothing further.

## Phase 4 — Chord verification

### Tasks

1. Verify strummed chords against `ChordDetector`, accepting any valid voicing
   of the target chord.
2. Respect the existing confidence floor rather than lowering it for practice.
3. Distinguish "wrong chord" from "not confident yet" in the UI — a strum that
   the detector cannot resolve is not a mistake by the player.

### Exit criteria

- Chord practice advances on a correctly fingered chord in more than one voicing.

## Phase 5 — Session results

### Tasks

1. Report per-session attempts, hesitation and repeatedly-missed positions.
2. Keep results transient unless a deliberate decision is made to persist them,
   in which case they go in the practice-state document under their own version.

### Exit criteria

- Results are accurate against a scripted session and disappear on reset.

## Phase 6 — Final gates

### Tasks

1. Full build, test, smoke-test, direct launch of the archived build.
2. Verify the whole loop against a real guitar on both the direct and buffered
   monitoring paths, and with speakers as well as headphones.
3. Update `CLAUDE.md` with what was learned about verification tolerances.
4. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, write the
   `CHANGELOG.md` entry, and tag per `CLAUDE.md`'s Versioning section. This is
   the capability neither app had before; say so plainly in the changelog.

## Implementation Record

_Append phase-by-phase evidence here._
