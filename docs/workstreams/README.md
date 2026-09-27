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
| ~~005~~ | ~~Multi-module app shell~~ — **complete**, see `completed/` | 001 |
| 006 | Learning modules — **implementation complete**, record remains in `active/` | 003, 004, 005 |
| 007 | Microphone-verified guided practice | 006 |
| 008 | Live-note chip feedback | 006 |
| 009 | Built-in-microphone iPhone and iPad app | 006 |

Workstreams 001–006 have landed. The theory layer, 15 tunings, 138-position DI
sample library, sampled playback, general fretboard, app shell and all ten
learning modules are present in the Mac app. Workstream 006's implementation
record reports completion, though its document has not yet been moved out of
`active/`.

007 and 008 are follow-on practice and feedback work. 009 can begin without
waiting for either one; if 007 lands first, 009 should reuse its app-playback
detection gate rather than building a second mechanism.

## Source of truth

The web repo is at `../fretwork`. Where a workstream says "port", the web
implementation and **its tests** are both to be ported; the tests are what will
catch the string-order inversion described in 001.
