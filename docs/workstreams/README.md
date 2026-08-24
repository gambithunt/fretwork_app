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
| 001 | Theory foundations and the tuning model | — |
| 002 | Sample capture mode and the note library | — |
| 003 | Sampled playback engine | 001, 002 |
| 004 | General-purpose fretboard view | 001 |
| 005 | Multi-module app shell | 001 |
| 006 | Learning modules | 003, 004, 005 |
| 007 | Microphone-verified guided practice | 006 |

001, 002 and 004 can proceed in parallel. 002 can start immediately — it
depends on the audio layer, which already exists.

## Source of truth

The web repo is at `../fretwork`. Where a workstream says "port", the web
implementation and **its tests** are both to be ported; the tests are what will
catch the string-order inversion described in 001.
