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

_Append phase-by-phase evidence here._
