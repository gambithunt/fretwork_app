# Workstream 003: Sampled Playback Engine

## Objective

Play the recorded note library through whichever device the user has chosen for
output, polyphonically, without disturbing the monitoring path the app already
gets right.

This replaces `src/lib/audio.ts` — Tone.js `PluckSynth` through EQ, compressor
and reverb. The synthesised source and most of that compensating chain go away;
what stays is the musical behaviour built on top: sequences with per-note
callbacks, strums, cancellation, and slight per-note variation.

## Required outcome

- Any position on the neck sounds its recorded sample on demand, in standard
  tuning, with no resampling.
- Non-standard tunings sound a resampled note taken from the **same string's**
  nearest recorded position.
- Polyphony sufficient for a six-string strum plus overlapping decays.
- A new note on a string cuts the note still ringing on that string, as a real
  guitar does.
- Sequence playback with a per-note callback for UI synchronisation, and
  reliable cancellation — a stopped sequence emits nothing further.
- Strum with a natural inter-string offset.
- Playback level is independent of the monitor level.
- Monitoring latency, buffer size and the direct/buffered path selection are
  measurably unchanged.

## Non-goals

- Any UI. Workstream 006 drives this; here it is a service with tests.
- Recording, library construction, or sample verification (workstream 002).
- Reverb/room design beyond what is needed to keep DI samples from sounding
  bone dry. Start minimal; the samples are real, so the chain that existed to
  rescue a synth is largely unnecessary.
- Microphone-verified practice (workstream 007).

## Verified findings driving this workstream

1. **`CLAUDE.md`'s Decisions table is stale on the central question here, and
   must be corrected as part of this workstream.** It says to feed monitored
   audio out with `AVAudioPlayerNode` + scheduled buffers in
   `AudioMonitorWorker`, and to avoid `AVAudioSourceNode`'s render callback
   because it "hit `kAudioUnitErr_InvalidElement` (-10877) consistently on real
   interfaces here". Both halves are now wrong:
   - `AudioMonitorWorker` no longer exists. `Fretlight/Audio/` contains
     `MonitorRenderer.swift`, which **is** an `AVAudioSourceNode`.
   - `AudioEngine.swift:29-37` records the correction directly: "That diagnosis
     looks to have been wrong: the same -10877 was later traced to the polling
     loop busy-spinning hard enough to starve Core Audio's real-time thread…
     With the spin gone, pulling works — and pulling is what removes the queue
     that the pushing design needed."

   So the render-callback approach is live in production and is the right shape
   for the sample player too. The row must be rewritten to say what was actually
   learned: the hazard is a busy-spinning consumer, not the source node.
2. **The monitor slider currently owns the shared mixer.** Both graph paths end
   with `mixer.outputVolume = monitorVolume` — `startDuplex` on the capture
   engine's `mainMixerNode`, `startSplit` on the playback engine's. Sample
   playback must not be governed by the monitor slider, so the monitor leg needs
   its own gain stage and the volume must move off the shared mixer. This is a
   small change to a load-bearing, carefully tuned graph and should be done
   deliberately, with the smoke test run either side of it.
3. **There are two graphs to attach to.** On the duplex path the output device
   is served by `captureEngine`'s main mixer; on the split path by
   `playbackEngine`'s. The player must attach to whichever engine is bound to
   the output device, and must survive `AudioEngine`'s restart/reconnect logic
   (`scheduleRestart`/`attemptRestart`) without leaking nodes across restarts.
4. **A makeup-gain pattern already exists.** `makeMonitorGainStage()` builds an
   `AVAudioUnitEQ` with its single band bypassed, used purely as a gain stage,
   because `AVAudioMixerNode.outputVolume` is clamped to 0...1. The sample
   player's own level control should reuse that pattern rather than invent one.
5. **Real-time discipline is documented and non-negotiable.**
   `MonitorRenderer`'s docstring states the rule plainly — the render block does
   not allocate, lock or block, and all sizing happens in `init`. Voice mixing
   follows the same rule: buffers are loaded and any resampling is done ahead of
   time, never inside the callback.
6. **The web's musical behaviour is worth porting exactly.** `audio.ts` uses a
   10-voice pool so a fast sequence cannot reuse a voice before its previous
   note has rung out, ±2.5 cents of random detune per note, a 25 ms inter-note
   offset for strums and 30 ms for `strum()`, and schedules one note at a time
   rather than committing a whole run to a timeline so it stays cancellable.
   Each of those is a considered choice; carry them over rather than rediscover.

## Execution contract

1. Work in phase order.
2. Gates after every phase:
   - `pkill -9 -f "Fretwork.app/Contents/MacOS\|Fretlight.app/Contents/MacOS"`
   - `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test`
   - `git diff --check`
3. Smoke-test per `CLAUDE.md` workflow 3 after **every** phase that touches the
   graph — phases 1, 2 and 4. Latency and buffer size are user-visible in the
   telemetry row; record them before and after.
4. Nothing in a render callback allocates, locks or blocks.
5. Preserve unrelated worktree changes.
6. Append evidence to the Implementation Record after each phase.

## Phase 0 — Baseline

### Tasks

1. Record `git status --short`, a clean test run, and a smoke-test baseline:
   reported buffer size, reported latency, direct/buffered path, and idle CPU
   on both the duplex and split paths.
2. These numbers are the regression bar for the rest of the workstream. A
   change to monitoring latency is a defect, not a trade-off.

### Exit criteria

- Baseline recorded for both graph paths. No code changed.

## Phase 1 — Separate monitor level from the shared mixer

### Files

- `Fretlight/Audio/AudioEngine.swift`

### Tasks

1. Move monitor volume off `mainMixerNode.outputVolume` onto the monitor leg's
   own gain stage, so the shared mixer becomes a neutral summing point that
   later gains a second input.
2. Keep the existing `+4 dB` makeup behaviour and the slider's mapping exactly
   as they are; this phase changes where the gain is applied, not how loud
   anything is.
3. Verify on both paths, including a device switch and a forced reconnect.

### Tests and audit

- Monitor mute and level behave identically to baseline.
- Smoke-test: latency, buffer size and CPU unchanged from Phase 0.

### Exit criteria

- No audible or measured change, and the mixer is free to take a second input.

## Phase 2 — Voice pool and render callback

### Files

- `Fretlight/Audio/SamplePlayer.swift` (new)
- `Fretlight/Audio/AudioEngine.swift`

### Tasks

1. Load the bundled library into memory as ready-to-play buffers at the graph's
   format. Do all format conversion and any tuning-driven resampling here, at
   load, never in the callback.
2. Implement a fixed voice pool (10, matching the web's `VOICE_COUNT` and for
   the same reason) mixed inside one `AVAudioSourceNode` render block.
3. Implement per-string voice stealing: a new note on a string releases the one
   still sounding on it, with a short fade so the cut is not a click.
4. Attach the node to whichever engine owns the output device, on both paths,
   and re-attach correctly across `attemptRestart`.
5. Give playback its own gain stage, independent of monitor level and of monitor
   mute.

### Tests and audit

- Offline/manual-rendering verification of the mixer: correct sample at correct
  position, voice stealing, no discontinuity at a steal.
- Voice exhaustion degrades by stealing the oldest voice, never by allocating.
- Smoke-test on both paths; CPU stable under sustained six-voice playback.

### Exit criteria

- A note plays at the right pitch through the chosen output device, on both
  graph paths, with monitoring unaffected.

## Phase 3 — Musical layer

### Files

- `Fretlight/Audio/SamplePlayer.swift`
- `Fretlight/Audio/NoteSequencer.swift` (new)

### Tasks

1. Port `playSequence`'s contract: a gap between notes, an optional strum at the
   end, a per-note callback, a completion callback, and one-note-at-a-time
   scheduling so a run stays cancellable.
2. Port `strum` with its inter-string offset.
3. Port the ±2.5 cents per-note detune, plus slight gain jitter — with one
   sample per position and no round-robin, this is what keeps repeats from
   sounding mechanical.
4. Cancellation must be total: after `stop`, no further audio and no further
   callbacks, including from work already in flight. Follow the generation-token
   pattern the web's `guided-session.ts` uses, which is already proven against
   exactly this class of bug.

### Tests and audit

- A stopped sequence emits no further callbacks under a deterministic clock.
- Sequence, strum and completion callbacks fire in the right order.
- Rapid start/stop cycles leak no voices and no tasks.

### Exit criteria

- Ported web audio tests pass against the Swift implementation.

## Phase 4 — Tuning support and non-standard positions

### Files

- `Fretlight/Audio/SamplePlayer.swift`

### Tasks

1. For a non-standard tuning, resolve each position to the same string's nearest
   recorded sample and resample by the pitch difference, at load.
2. Cache per-tuning tables so switching tuning does not re-derive on every note.
3. Record the audible limit here: how far a string can be shifted before it
   stops sounding like itself. Drop A takes the low string down 7 semitones and
   is the worst case in the set.

### Exit criteria

- All 15 tunings sound correct pitches; standard tuning provably takes the
  unresampled path.
- Smoke-test clean after the load-time work.

## Phase 5 — Final gates

### Tasks

1. Full build, test, smoke-test on both graph paths, and a direct launch of the
   archived build.
2. **Correct `CLAUDE.md`**: rewrite the `AVAudioSourceNode` row per finding 1,
   remove the reference to the deleted `AudioMonitorWorker`, and add a row for
   the monitor-versus-playback gain separation.
3. This ships a real user-facing capability. Bump `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`, add a `CHANGELOG.md` entry written from the root
   cause, and tag per `CLAUDE.md`'s Versioning section — but only once
   workstream 006 gives the user a way to trigger playback. If 003 lands alone,
   hold the bump and say so in the commit.

## Implementation Record

### Phase 0 — Baseline

Worktree clean at the start (`git status --short` empty; workstream 002
committed as `8416545`). Full suite green.

Measured by driving the real `AudioEngine` against real hardware from a
throwaway diagnostic in the test target, rather than by reading the telemetry
row off a screenshot. `xcodebuild` does not surface a test's stdout and the
`.xcresult` carries no console log, so the diagnostic writes its report to the
path in `TEST_RUNNER_FRETWORK_BASELINE_REPORT` — the same forwarding
convention `DetectionBoardSnapshotTests` already uses. Anything not prefixed
`TEST_RUNNER_` never reaches the test process.

| Path | Device(s) | Buffer | Latency median | min | max |
| --- | --- | --- | --- | --- | --- |
| duplex / direct | GP-200 Audio | 256 frames | 2.92 ms | 0.82 | 5.89 |
| split / buffered | CalDigit in → CalDigit out (separate IDs) | 256 frames | 3.38 ms | 1.77 | 7.02 |

The split figure is a genuine split-path measurement: macOS gives the
CalDigit's input and output separate `AudioDeviceID`s, so `startSplit` runs
even though one physical box is at both ends.

Note on what this number is: `latencyMilliseconds` is capture-to-detection —
the figure the telemetry row shows — not the monitoring path's own delay. It
is the user-visible regression bar, which is what Phase 0 asks for.

Idle CPU, Debug build, sampled three times over 21 s: 39.8% (launch), then
13.9%, then 12.7%. Falling and then flat, not climbing. No `-10877` or other
`kAudioUnitErr_*` in the log. Measured with the window occluded behind the
terminal, so later comparisons must be taken the same way to be like-for-like
(see `CLAUDE.md` on occlusion throttling). Re-measured later over six samples
to confirm it was not a lucky run: 13.8 / 13.6 / 11.9 / 14.1 / 10.7 / 13.5.

### Phase 1 — Separate monitor level from the shared mixer

The slider now rides the monitor leg's own gain stage (`monitorGainDB`), and
`mainMixerNode.outputVolume` is pinned at unity on both paths, free to take
sample playback as a second input.

**Two placements were tried and rejected first, both on evidence.**

1. *A dedicated `AVAudioMixerNode` on the monitor leg*, carrying the slider on
   its `outputVolume`. The obvious design, and it worked — but idle CPU went
   from a steady ~13% to ~30%, sampled six times each way on the same machine,
   same devices, same occlusion state, and confirmed by stashing the change and
   re-measuring the baseline rather than trusting the first run. An
   `AVAudioMixerNode` is a full converting mixer, not a fader; the GP-200
   presents six input channels, so two mixers in series do that conversion
   twice. **This is exactly the failure `CLAUDE.md` warns about in the
   segmented-picker row** — the control was fine, the cost was in how often and
   how much work it made something else do.
2. *`AVAudioMixing.volume` on the leg's last node* — the per-input-bus level on
   the destination mixer, which would have been free. `AVAudioUnitEQ` does not
   conform to `AVAudioMixing`. Probed empirically: `AVAudioSourceNode`,
   `AVAudioPlayerNode`, `AVAudioInputNode` and `AVAudioMixerNode` conform;
   `AVAudioUnitEQ` and `AVAudioUnitDelay` do not, connected or otherwise.
   Because the level was applied through `as? AVAudioMixing`, this failed
   **silently**: it compiled, it ran, monitoring still worked, and the slider
   simply did nothing. Nothing in a build log or a diff showed it.
   `MonitorLevelTests` was written to catch exactly that and did.

So the slider folds into the `globalGain` the stage already had:
`makeup + 20·log10(volume)`, clamped at -96 dB. The one behavioural difference
from before is that **mute is now -96 dB rather than a true zero** — roughly
-98 dBFS against a monitor signal peaking at -6, inaudible through any real
output, but attenuation rather than a disconnect. Recorded here because it is
visible on a meter even though it is not audible.

Also pinned while measuring: `mainMixerNode` applies an equal-power pan law to
a mono input, so a monitor level renders at 1/√2 of the number on the slider.
That predates this change, but it is why a rendered level does not equal the
slider, and `testTheMainMixerPansMonoInputDownThreeDB` now says so.

| | Phase 0 | Phase 1 |
| --- | --- | --- |
| duplex latency median | 2.92 ms | 2.41 ms |
| split latency median | 3.38 ms | 3.82 ms |
| buffer, both paths | 256 frames | 256 frames |
| path selection | duplex / split as expected | unchanged |
| idle CPU | 10.7–14.1% | 8.7–13.5% |

Latency moves in both directions run to run, so these are within noise rather
than an improvement or a regression. Suite green, `git diff --check` clean, no
`kAudioUnitErr_*` in the smoke-test log.

### Phase 2 — Voice pool and render callback

`NoteSampleLibrary` decodes the bundled library; `SamplePlayer` mixes a
ten-voice pool inside one `AVAudioSourceNode`; `AudioEngine` attaches a player
to whichever engine owns the output device on both graph paths.

**Playback rate rather than load-time resampling.** The workstream anticipated
resampling per tuning at load and caching the result. That would be 85 MB per
tuning across fifteen tunings. Each voice instead carries a fractional read
position advanced by a rate, and one linear interpolation per frame covers all
three things that need it: a 44.1 kHz library on a graph running at another
rate, a non-standard tuning's pitch shift, and Phase 3's per-note detune. This
does not breach "no resampling in the callback" — that rule is about
allocation, locks and blocking, and an interpolation is a multiply-add. What
Phase 4 will cache is the *resolution table* (position → take + ratio), not a
second copy of the audio.

**The player's level is free; the monitor's was not.** `AVAudioSourceNode`
conforms to `AVAudioMixing`, so playback level is a per-input-bus volume on the
shared mixer — the exact mechanism Phase 1 could not use, because the monitor
leg ends in an effect rather than a source node.

**Memory.** The decoded library is 22,271,479 frames — **85 MB** as float32,
which is what a 138-take sampler costs. Loading it is gated behind
`prepareSamplePlayback()` so a user who never triggers a note pays nothing,
matching how chord detection and sample recording are gated.

The first implementation decoded every take into its own array and copied into
the shared block afterwards, holding two full copies at once: measured at
**+175 MB of RSS** against the app's 119 MB baseline. Decoding straight into
the shared block brought that to **+91 MB** (119 → 210 MB). The index's
`frameCount` sizes the block but is never trusted as a write length — each read
is clamped to the space reserved for it — so a stale index is an error rather
than an overrun. That is the `PitchDetector` scratch-buffer bug from
`CLAUDE.md` avoided in the other direction.

Load takes 3.3 s cold, 0.4 s warm.

**Verified by offline rendering**, per the `CLAUDE.md` row about the detection
board — reading the diff is not evidence for a mixer either:

- all 138 positions present, each sounding the MIDI note its string and fret
  imply (this is the string-order inversion guard)
- a played note renders the recorded take sample-for-sample
- an idle player emits exact silence; an unrecorded position is refused
- six strings sound together; a second note on a string releases the first
- a steal leaves no step in the output (largest sample-to-sample jump stays
  under half the signal peak, where a hard cut would step by the amplitude)
- voice exhaustion steals the oldest and never exceeds the pool
- `stopAll` releases every voice and renders to silence
- a rate multiplier of 2 runs through the take in half the frames

**On real hardware**, both graph paths: a six-string strum plus a twelve-note
run, zero errors, latency unchanged from Phase 0/1 (duplex 2.89 ms, split
3.77 ms). CPU during playback 10–17% with one 49% spike at library load.

### Phase 3 — Musical layer

`NoteSequencer` ports `playSequence`, `strum` and the per-note variation from
`src/lib/audio.ts`, with the web contract kept intact: the gap default of
0.55 s, 25 ms between notes in a sequence's closing strum against 30 ms in a
standalone one, the 150 ms pause before that strum, and `onHit` reporting -1 as
the index for a strummed note rather than its place in the run.

Cancellation uses the generation-token pattern from the web's
`guided-session.ts`: `stop` and every new run bump a counter, and work already
in flight does nothing if the counter has moved. Starting a run cancels the one
before it, so two sequences cannot interleave.

**The clock is injectable, and that is the point.** A sequencer tested against
a real clock can only be tested by waiting and then looking, which cannot
distinguish "cancelled" from "not fired yet" — the exact bug this pattern
exists to prevent. `ManualClock` runs the schedule by hand, so
`testAStoppedSequenceEmitsNothingFurther` first asserts that work *is* still
queued, then advances ten seconds and asserts nothing came out of it.

Writing that clock surfaced a Swift trap worth recording: **closures have no
identity**. The first version found the next due item and then located it in the
pending array by comparing `$0.work as AnyObject === next.work as AnyObject`.
Boxing a closure with `as AnyObject` produces a *new* box every time, so the
match never succeeded, every scheduled item was silently skipped, and the
result was a clock that ran nothing. It failed in a revealing pattern — every
"expected something to fire" test failed while every cancellation test passed,
because a clock that fires nothing looks exactly like perfect cancellation.
Items are identified by a serial number now.

Per-note variation is ±2.5 cents of detune and up to 6% of level reduction.
Gain jitter only ever reduces, never boosts: the takes are normalised to 0.8
and pushing one above nominal is the one direction that can clip.

`AudioEngine.makeSequencer()` returns a sequencer wired to the engine. A
factory rather than a stored property, because building one captures `self` in
a closure and a stored property cannot do that during initialisation — the
two-phase-init trap `CLAUDE.md` records against `AudioDeviceWatcher`.

### Phase 4 — Tuning support and non-standard positions

`TuningSampleMap` resolves any position in any tuning to a recorded take plus a
frequency ratio, with one table per tuning built on first use and cached.

**The cached table is the mapping, not resampled audio.** The workstream said
"resample by the pitch difference, at load" and "cache per-tuning tables"; taken
literally that is 85 MB of audio per tuning, 1.2 GB across fifteen. Each entry
caches the source fret and a ratio instead, and Phase 2's per-voice rate does
the shift. The detune from Phase 3 multiplies into the same ratio, so a detuned
note in Drop A is one number, not two lookups.

**"Nearest position on the same string" is a clamp.** A string tuned down *n*
semitones plays everything from its *n*th fret upward from a real take; only the
frets below have nowhere to come from, and they stretch fret 0. This is why the
shift is taken from the same string rather than from whichever string holds the
right pitch: that would be the right note with the wrong instrument, since
gauge, winding and pickup position are most of what makes a low E sound like a
low E instead of the A string played high.

**Standard tuning provably takes the unresampled path** — every one of its 138
positions resolves to its own take at a ratio of exactly 1, asserted rather than
assumed. That is the whole return on recording every fret.

The audible limit this phase asks to record, measured across all fifteen:

| Tuning | Worst shift | Positions shifted |
| --- | --- | --- |
| Drop A | −7 st | 32 / 138 (77% real takes) |
| Drop B | −5 st | 20 / 138 |
| Standard C | −4 st | 24 / 138 |
| Drop C | −4 st | 14 / 138 |
| Open C | ±4 st | 9 / 138 |
| Modal C6 | −4 st | 7 / 138 |
| Open A | −3 st | 6 / 138 |
| Standard D, Open D/G/E, DADGAD, Double Drop D, Drop D | ≤2 st | 2–12 / 138 |
| **Standard** | **0** | **0 / 138 — every position is its own take** |

Drop A is the worst case in the set, as the workstream predicted: its open low
string is the recorded low E stretched down a fifth (ratio 0.6674). Even there,
77% of the neck is untouched audio, and the shifted positions are all in the
first few frets of a detuned string. `testDropAIsTheWorstCaseAndIsSevenSemitones`
fails if a tuning is ever added that stretches further, so this note cannot go
stale silently.

Tests assert **sounded pitch**, not fret numbers, for the reason `CLAUDE.md`
gives about porting fret arrays: a wrong table is still six plausible fret
numbers that compile and render exactly like a right one.

**The hardware smoke test for this phase is outstanding.** Partway through it
the machine's audio stack wedged: the diagnostic reported no telemetry at all
(n=0 samples) and `prepareSamplePlayback` never completed, both explained by the
control queue blocking inside a Core Audio call. It is not a regression from
this phase — the same diagnostic fails identically at the Phase 3 commit, which
measured clean an hour earlier, and the built app sits at 0.0% CPU where it
previously ran at ~13%. `usbaudiod` was at 7.3% with nothing playing. The likely
cause is the interface's HAL state after several dozen rapid engine
start/stop cycles from these diagnostics. Clearing it needs the interface
replugged or `coreaudiod` restarted, neither of which is a code change. **Phase
4's exit criterion "smoke-test clean after the load-time work" is therefore not
yet met**, and Phase 5's gates must re-run all of it on a healthy machine.
