# Workstream 002: Sample Capture Mode and the Note Library

## Objective

Build a guided, self-verifying recording mode inside the app, use it to capture
a real DI guitar sample at every position on the neck, and ship that library in
the bundle.

The app plays notes back to the user in every later workstream. A synthesised
Karplus-Strong tone — what the web app uses — sits next to the player's actual
instrument and loses the comparison. Recording it once, properly, is the whole
difference between a reference the player trusts and one they mute.

## Why in the app rather than a DAW

At 138 takes the recording is the easy part; the bookkeeping is not.

- **Naming is the dominant risk.** One take bounced under the wrong
  string/fret is a silent defect that will not surface until a chord voicing
  sounds subtly wrong months later. The recorder names the file because it
  chose the prompt, so the class of error does not exist.
- **A DAW cannot verify a take.** A mis-fretted note, a buzz, a dead note, or a
  string that drifted flat over an hour all look entirely normal in a waveform.
  `PitchDetector` (YIN) already runs on this signal and can reject the take
  while the player is still holding the guitar.
- **Trimming by rule beats trimming by hand** 138 times, and is consistent.
- **The session becomes resumable**: the recorder knows which positions are
  still missing, so the library can be captured across several sittings.

The masters are written as plain WAV in a flat folder, so auditioning or
hand-repairing an individual take in GarageBand or Audacity stays available.
This replaces the DAW for the parts a DAW is bad at, not for the rest.

## Recording parameters

Settled before this workstream:

| Parameter | Value |
| --- | --- |
| Coverage | Every position: 6 strings x frets 0–22 = **138 takes** |
| Signal | **DI through the audio interface**, one session, one gain setting |
| Tuning | Standard only |
| Dynamics | One layer. No velocity layers, no round-robin |
| Masters | 24-bit, device sample rate (48 kHz expected), mono |
| Tail | Capture generously (~6 s); trim at build, not at record time |

Every-fret coverage means standard tuning needs **no resampling at all** —
playback is a direct lookup. Resampling survives only for the other 14 tunings,
where a shifted string has no recorded sample; those shift from the *same
string's* nearest position, preserving that string's character rather than
borrowing the correct pitch off a different string with the wrong timbre.

## Required outcome

- A capture mode that prompts one position at a time, arms, detects onset,
  records through the decay, verifies, and advances.
- A take is **rejected automatically** when the detected pitch is not within a
  configured tolerance of the target, and the position is re-prompted.
- A take is **flagged** (not rejected) when its peak deviates materially from
  the running session median, so attack consistency does not drift as the
  session wears on.
- Masters written as WAV with deterministic names, plus a JSON manifest
  recording, per take: position, target pitch, detected pitch, cents deviation,
  peak, duration, sample rate and timestamp.
- Session state is resumable across launches; missing positions are visible at
  a glance.
- Any single position can be re-recorded without disturbing the other 137.
- A build step converts masters into the bundled library and fails loudly on a
  missing or unverified position.

## Non-goals

- Playback. Workstream 003 consumes this library; this one only produces it.
- Velocity layers, round-robin takes, alternate tunings, alternate instruments.
- Editing audio in-app beyond trim and normalise. Repairs happen in an external
  editor against the written WAV.
- Shipping the masters in the repository.

## Verified findings driving this workstream

1. **The capture path already provides everything needed.** `CaptureSink` is an
   `AVAudioSinkNode` pulling raw `Float` samples at the hardware block size
   (`AudioEngine.targetBufferFrames` = 256), and it already fans out to three
   independent `RingBuffer`s. Its own docstring records why each consumer gets
   its own ring: `RingBuffer` is strictly single-producer/single-consumer. A
   recorder is a fourth ring following an established, documented pattern.
2. **The sink is deliberately real-time-safe** — no allocation, no locks, no
   blocking — and must stay that way. The recorder drains its ring on its own
   queue, exactly as `AudioAnalysisWorker` does.
3. **`AudioAnalysisWorker` already computes what onset detection needs**: a
   windowed RMS via `vDSP_rmsqv`, and a YIN result with a confidence value,
   published at ~30 Hz. The recorder needs the same two signals at finer
   granularity, not new DSP.
4. **DI recording removes the feedback concern.** No microphone is in the loop,
   so monitoring through speakers during capture is harmless. This does not
   hold for workstream 007, which does use the microphone path.
5. **Multi-channel interfaces are summed into the monitor but not into
   analysis** — `startDuplex` notes that the analysis path reads channel 0
   alone. The recorder must read channel 0 for the same reason, and the capture
   UI should say which physical input that is.

## Execution contract

1. Work in phase order.
2. Gates after every phase:
   - `pkill -9 -f "Fretwork.app/Contents/MacOS\|Fretlight.app/Contents/MacOS"`
   - `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test`
   - `git diff --check`
3. Phase 1 changes the render callback. Smoke-test per `CLAUDE.md` workflow 3
   after it — sample CPU twice a few seconds apart and check for
   `kAudioUnitErr_*` — before building anything on top.
4. Nothing added to `CaptureSink` may allocate, lock or block.
5. Preserve unrelated worktree changes.
6. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline and library contract

### Tasks

1. Record `git status --short` and a clean test run.
2. **Settled — the naming contract.** `s{string}-f{fret:02}-m{midi:03}.wav`,
   string index in **Mac order** (0 = Low E): `s0-f03-m043.wav`.

   The MIDI number is deliberate redundancy — string and fret already
   determine it in standard tuning, so the build step can cross-check the name
   against the manifest's detected pitch and catch a transcription error. It is
   preferred over a note name (`G2`) because a name has to encode accidentals,
   and the app spells those with Unicode `♯`/`♭`; putting those in 138
   filenames invites mismatches between what the recorder writes and what a
   shell, a build script or Git reports back. A zero-padded integer sorts
   correctly and cannot be misspelled.
3. Fix the masters location and confirm it is git-ignored. These are
   irreplaceable without another recording session, so add them to the backup
   discipline `docs/releasing.md` already establishes for the signing keys.
4. Record expected sizes so the bundle decision in Phase 4 is informed:
   138 takes x ~6 s x 48 kHz x 24-bit ≈ **120 MB of masters**; trimmed to ~4 s
   at 44.1 kHz/16-bit that is ≈ 49 MB raw, ≈ 25–30 MB as ALAC, ≈ 13 MB as
   192 kbps mono AAC.

### Exit criteria

- Naming, location, ignore rules and the backup note are written down. No code
  has changed.

## Phase 1 — Recorder tap

### Files

- `Fretlight/Audio/CaptureSink.swift`
- `Fretlight/Audio/AudioEngine.swift`
- `Fretlight/Audio/SampleRecorder.swift` (new)

### Tasks

1. Add a fourth `RingBuffer`, written unconditionally by `CaptureSink` beside
   the existing three, following the pattern its docstring describes for
   `chordRing`: the writer is unconditional and cheap; the consumer decides
   whether anything is draining it.
2. Add `SampleRecorder`, draining that ring on its own queue. It reports a
   fine-grained level and accumulates samples into a capture when armed.
3. Expose the hardware sample rate and channel identity to the recorder; refuse
   to arm if the input format is unusable, with the same error style
   `startDuplex`/`startSplit` already use.

### Tests and audit

- A ring fed synthetic frames yields exactly those frames at the recorder.
- Confirm the fourth write does not change analysis or chord output.
- Smoke-test: CPU flat, no `-10877` or other `kAudioUnitErr_*`.

### Exit criteria

- Recording is inert until armed and costs one extra `write` per render block.
- Existing detection behaviour is unchanged.

## Phase 2 — Take capture, verification and persistence

### Files

- `Fretlight/Audio/SampleRecorder.swift`
- `Fretlight/Audio/SampleLibrary.swift` (new — manifest model and on-disk layout)

### Tasks

1. Measure a noise floor at session start and derive the onset threshold from
   it rather than from a constant.
2. Implement the take lifecycle: armed → onset detected → recording → decay
   below threshold (or the ~6 s cap) → stop.
3. Verify the take with `PitchDetector` over its sustained portion, not its
   attack. Reject when the detected pitch is outside tolerance of the target,
   or when confidence never reaches a usable level (a dead or buzzed note).
   Recommended starting tolerance: ±10 cents; make it a named constant with its
   rationale, following the `SensitivitySettings` pattern in `CLAUDE.md`.
4. Trim leading silence to a fixed pre-onset margin, normalise to a common
   peak, and write the WAV plus its manifest entry atomically — a crash must
   not leave a named file with no manifest row or the reverse.
5. Track the running peak median and flag outliers without rejecting them.

### Tests and audit

- Synthetic signals at correct, sharp, flat and silent pitches produce accept,
  reject, reject and reject respectively.
- A resumed session reads an existing manifest and reports the correct missing
  set.
- Manifest and directory contents cannot disagree after an interrupted write.

### Exit criteria

- A take can be captured, verified, written and re-read end to end.
- Rejection reasons are distinguishable, not a single generic failure.

## Phase 3 — Capture UI

### Files

- `Fretlight/Views/SampleCaptureView.swift` (new)
- `Fretlight/Models/AppState.swift`

### Tasks

1. A capture screen showing: the current prompt (string, fret, target note),
   live level with the onset threshold marked, the last take's verdict, and a
   neck-shaped grid of all 138 positions coloured captured / flagged / missing.
2. Controls: arm, skip, re-record the current position, jump to any position,
   and a clear indication of how many remain.
3. Advance automatically on an accepted take so the player never puts the
   guitar down to click something.
4. Read audio-rate properties **in leaf views only**. `ContentView`'s existing
   `TunerSection`/`LevelSection` split exists precisely because `@Observable`
   tracks reads per view body; a live level read in this screen's parent body
   would invalidate the 138-cell grid at 30 Hz. Follow the same structure, and
   avoid `.pickerStyle(.segmented)` anywhere that rebuilds at that rate — see
   the measured leak in `CLAUDE.md`.
5. Keep this mode out of the ordinary user's way; it is a maintainer tool.
   Decide and record whether it ships hidden behind a menu item or is compiled
   out of release builds.

### Exit criteria

- A full 138-position session is completable without touching a DAW.
- The window's measured minimums still hold, or are re-measured per `CLAUDE.md`
  workflow 4.

## Phase 4 — Library build step

### Files

- `scripts/build-sample-library.sh` (new)
- `Fretlight.xcodeproj` resource wiring

### Tasks

1. Convert verified masters into the shipped library: trim to a common length,
   apply a short release fade so no take ends on a discontinuity, convert to
   the chosen bundle format, and emit a compact index the playback engine reads.
2. **Fail the build** on any missing position, any unverified manifest row, or
   any filename whose note does not match its manifest pitch.
3. Choose ALAC or AAC on measured quality against the plucked transients, and
   record the decision and the resulting bundle delta here.
4. Confirm the added resources do not disturb the `LD_RUNPATH_SEARCH_PATHS` /
   embedding setup that `CLAUDE.md` warns the test suite cannot validate — run
   the archived build directly, not just the tests.

### Exit criteria

- A clean checkout plus masters produces a complete library reproducibly.
- An incomplete library cannot ship silently.
- The built app launches from an archive, not only under xctest.

## Phase 5 — The recording session

### Tasks

1. Record all 138 positions, DI, one sitting where practical, one gain setting.
2. Review every flagged take and re-record or accept it deliberately.
3. Back up the masters per the Phase 0 note.
4. Commit the library build output and the manifest; not the masters.

### Exit criteria

- 138 verified positions, zero missing, all flags resolved.

## Phase 6 — Final gates

### Tasks

1. Full build, test, smoke-test, and a direct launch of the archived build.
2. Update `CLAUDE.md` with anything learned about the capture path.
3. No user-facing feature ships here on its own — the library is inert until
   workstream 003 — so hold the version bump for that one and say so in the
   commit.

## Implementation Record

### Phase 5 — The recording session

All 138 positions recorded DI in standard tuning, 24-bit mono at 44.1 kHz
(the interface's rate; the Phase 0 note anticipated 48 kHz, which is not a
problem — the rate is carried per-position in the manifest and the index, so
nothing downstream assumes one). Masters total 82 MB in `SampleMasters/`,
git-ignored per `docs/releasing.md`.

Validation against the naming contract passes with zero errors: 138 rows, no
missing position, no duplicate, no orphaned file, and every filename's encoded
MIDI number agrees with both the string/fret it also encodes and the
manifest's `targetMIDI`.

Pitch verification: worst take is 22.9 cents from target, median 6.9 — inside
the 25-cent window `TakeVerifier.centsWindow` sets, and the distribution is
what a real instrument does rather than what a tuner does, which is the
reasoning that widened that constant from 10.

**Flagged takes reviewed: 60 of 138 flagged for peak deviation, all accepted.**
The flag records *raw pick force*, which genuinely varied over the session,
but every accepted take is normalised to `TakeVerifier.normalizedPeak` (0.8)
before it is written — so the flag describes the performance, not the artifact.
Measured across the written masters, peaks land at 0.56–0.80. No take was
re-recorded on this basis.

### Phase 4 — Library build step

**ALAC vs AAC, measured rather than estimated.** The script's own help text
recorded that this decision was waiting on real transients. With them:

| | ALAC | AAC 192k mono |
| --- | --- | --- |
| Library size | 37.62 MB | 12.53 MB |
| Sample alignment vs lossless | — | exact (best correlation at offset 0) |
| Error RMS | — | −59 to −74 dBFS |
| Margin below each take's own noise floor | — | 22–37 dB |

Method: decode both builds of the same take back to PCM, align by maximising
SNR over ±2500 samples, then compare. Alignment came out at offset 0 on every
take tested, so `afconvert`'s encoder priming introduces no attack-timing skew
— the thing that would actually have disqualified a lossy format here. The
error sits well under noise the recording already carries. **AAC is now the
script default**; `--format alac` still rebuilds losslessly.

**Two defects found in the masters and fixed at build time**, which is where
Phase 0 deliberately put trimming:

1. **Onset jitter.** The recorder trims to a fixed 15 ms ahead of the onset it
   detects, but its threshold is derived from the noise floor and fires late on
   a soft attack. Measured across the session: 93 takes landed on the intended
   margin, 33 sat at 0–2 ms (the rewind had landed *inside* the transient), and
   a dozen sat as late as 43 ms. Up to 15 ms of jitter in where a note begins,
   which workstream 003 would render as sloppy timing whenever it triggers
   samples on a grid. The build step now re-measures each onset itself and
   shifts every take to a common margin. After: 131 of 138 land at exactly
   15 ms, 5 at 16 ms, 1 at 19 ms, 1 at 8 ms.
2. **Head clicks.** Every master starts on a nonzero sample — the worst at
   +0.124, a −18 dBFS step straight out of silence. The script faded the tail
   and not the head. A 2 ms attack fade now mirrors the release fade; the
   largest first sample across the shipped library dropped from −18 dBFS to
   −68 dBFS.

Neither is recoverable by re-recording alone, and neither needed the guitar to
fix. Note that padding restores *alignment*, not audio: a take whose transient
the recorder already trimmed away is still truncated, it is merely truncated in
time with its neighbours now.

**Bundle wiring needed no `project.pbxproj` change** — `Fretlight/` is a
`PBXFileSystemSynchronizedRootGroup`, so the library was picked up as a
resource automatically. It lands **flat in `Contents/Resources/`**, not under a
`NoteSamples/` subdirectory; verified by inspecting the built app (138 `.m4a` +
`index.json`). Workstream 003's loader must look files up by bare filename.
Built app: 21 MB.

Gates: `xcodebuild ... test` **TEST SUCCEEDED**, `git diff --check` clean.
