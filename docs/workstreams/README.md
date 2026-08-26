# Workstreams

Porting the Fretwork web app's learning content into the macOS app, and then
closing the loop that neither app can close alone: the web app teaches but
cannot hear you; this app hears you but teaches nothing.

Docs follow the format used in the web repo (`fretwork/docs/workstreams/`):
objective, required outcome, non-goals, execution contract, then phases with
files, tasks and exit criteria. Append evidence to the Implementation Record at
the end of each doc as you go.

## Order

These are dependency-ordered. 002 sits early on purpose: the recording session
is human time that cannot be parallelised, and everything downstream is better
built against real audio than against a placeholder tone.

| # | Workstream | Depends on |
| --- | --- | --- |
| ~~001~~ | ~~Theory foundations and the tuning model~~ — **complete**, see `completed/` | — |
| ~~002~~ | ~~Sample capture mode and the note library~~ — **complete**, see `completed/` | — |
| ~~003~~ | ~~Sampled playback engine~~ — **complete**, see `completed/` | 001, 002 |
| ~~004~~ | ~~General-purpose fretboard view~~ — **complete**, see `completed/` | 001 |
| 005 | Multi-module app shell | 001 |
| 006 | Learning modules | 003, 004, 005 |
| 007 | Microphone-verified guided practice | 006 |

001, 002 and 004 are complete. The theory layer, the 15 tunings and the
persisted practice-state document all landed in 001; 002's recording session
is done, so all 138 positions exist as real DI audio and ship in the bundle at
`Fretlight/Resources/NoteSamples/`. That was the one piece of human time that
could not be parallelised, and it unblocks 003.

005 is clear to start. 003 is complete: the note library plays back
polyphonically in all fifteen tunings, monitor and playback levels are
independent, and the sequencer, strum and cancellation are ported from the web
app — but nothing in the UI reaches it yet, which is 006's job.

## Source of truth

The web repo is at `../fretwork`. Where a workstream says "port", the web
implementation and **its tests** are both to be ported; the tests are what will
catch the string-order inversion described in 001.
