# Fretwork iOS Interface Design (workstream 009, Phases 4–6)

- **Status:** selected — navigation **C (Sidebar Mirror)** + module landscape **M2 (bottom drawer, owner's variant)**; round 3 mocks the selection only
- **Owner:** Delon (product owner); design facilitation by Claude
- **Last updated:** 2026-09-28 (round 3)
- **Decision needed now:** sign off the round-3 mocks of C + M2, then a SwiftUI
  pass on the owner's iPhone.
- **Mock canvas:** https://claude.ai/artifact/EQiQvfzuDBaXvDvGsWFNrs
- **Parent:** `009-built-in-microphone-ios-app.md` (engineering plan, constraints
  C-01…C-24, decision log). This file owns the *design* of Phases 4–6; the parent
  owns sequencing, audio and verification.

## 1. Problem frame

**User and job.** A guitarist with an iPhone (or iPad) and no audio interface.
The **primary job is "what am I playing / am I in tune"** — open the app, play,
see the note. Working through the ten learning modules is the secondary job
(owner, 2026-09-28).

**Opportunity.** Every piece below the view layer already runs on iOS: theory,
detection, the audio controller (Phase 3, verified on iPhone), all ten module
screens, `ModuleLayout`, chips and the fretboard compile for iOS. What is missing
is a native shell, a phone-first Listen screen, settings, and module layouts that
work at 375–430 pt instead of the Mac's ~750 pt detail pane.

**Desired outcome.** A native iPhone/iPad app that feels like Fretwork (same
identity) and like iOS (same navigation idioms), usable one-handed-free with a
guitar in the hands, in portrait and landscape.

**In scope:** shell + navigation, Settings, Listen screen, the compact fretboard,
module layout adaptation, permission/interrupted/failed states, iPad regular
width.
**Out of scope:** new learning content, verified practice (007), playback gating
(009 Phase 7), App Store assets (Phase 8), light mode.

**Evidence:** `/tmp` evidence brief summarised into §2 and §9; Mac screens in
`Fretlight/Views/`; 009 C-rows; 006/008 docs.

## 2. Constraint register

Parent-doc constraints are cited by their 009 ID; design constraints here are
`D-xx`.

| ID | Constraint | Status | Strength | Source | Rationale / evidence |
| --- | --- | --- | --- | --- | --- |
| D-01 | Platform-best result wins over sharing; share a view only when easy and clean; no `#if os` splicing inside views. | Accepted | Hard | Owner 2026-09-28 | 009 decision log. iOS builds its own shell, Settings and Listen. |
| D-02 | **Listen is the primary job** and the launch screen. | Accepted | Hard | Owner 2026-09-28; 009 Phase 4 task 2 | Opening the app must land on a working tuner with zero taps. |
| D-03 | **Orientation follows the job:** portrait for tuning and note listening; landscape for the fretboard. Both orientations always work (no rotation lock required). | Accepted | Hard | Owner 2026-09-28 (supersedes "equally first-class"; resolves 009 Q-02) | 22 frets fit a landscape iPhone (~34 pt/fret) but not portrait (~7 frets); a tuner is a glance, and rotation lock is common. |
| D-16 | **Portrait Listen shows no fretboard** — tuner, note/chord readout, level, history only. | Accepted | Hard | Owner 2026-09-28 | Deliberately differs from the Mac, whose Listen screen always draws the board (`ListenScreen.swift:69`); allowed by D-01. |
| D-17 | **Rotating Listen to landscape reveals the full neck** with the live note lit at its playable positions, plus a compact tuner. | Accepted | Hard | Owner 2026-09-28 | The board is there on demand and never clutters tuning. |
| D-19 | **Sample Capture (the note-recording tool) is developer-only and never ships on iOS.** Its only purpose was recording the 138 notes into the library. | Accepted | Hard | Owner 2026-09-28 | Already true: Mac `#if DEBUG` (`FretlightApp.swift:64–79`), iOS exception set. Recorded so no phase reintroduces it. |
| D-20 | **Module landscape (M2): only the position arrows and the live note are always visible**; everything else (key/note, menus, play, explanation) lives in a drawer the player slides up, and taps or slides down to return to the board. | Accepted | Hard | Owner 2026-09-28 | Landscape is for the neck; moving along it is the one control needed while playing. |
| D-21 | **C launches into the last screen used** (Listen by default), with the list one "back" away. | Accepted | Soft | Owner 2026-09-28 (agreed) | Native state restoration, like Mail reopening the last mailbox; keeps D-02's zero-tap tuner. |
| D-18 | **Modules are designed landscape-first** (full neck in view) and remain fully usable in portrait (board scrolls, controls stack). No "rotate your phone" gate. | Accepted | Hard | Owner 2026-09-28 | Rotation lock must never block a lesson. |
| D-04 | Fretwork identity expressed with native iOS navigation, sheets and controls: dark backdrop `#090B0C`, glass cards, 12-note palette, accent `#5DCAA5`, flat translucent chips. | Accepted | Hard | Owner 2026-09-28; 009 C-13 | Same product on both platforms; iOS idioms for structure. Dark only (no light palette exists). |
| D-05 | Mock first (clickable HTML to choose), then a SwiftUI pass on the real iPhone, then build. | Accepted | Hard | Owner 2026-09-28 | "Mock everything and perfect it before building." |
| D-06 | All 22 frets reachable and legible on the smallest iPhone; horizontal board scrolling is the compact baseline. | Accepted | Hard | 009 C-08, C-09, decision 2026-09-16 | 22 frets at 375 pt ≈ 15 pt/fret — dots are 31 pt. Uniform scaling is ruled out. |
| D-07 | No device pickers, monitoring, rescan, device-path summary, Sparkle or capture tooling on iOS — absent, never disabled. | Accepted | Hard | 009 C-02, C-03, Deliberate removals | Removed rather than hidden. |
| D-08 | Audio-rate reads only in small leaf views; never in navigation chrome, lists or Settings. | Inferred | Hard | 009 C-10; CLAUDE.md | 30 Hz invalidation history on the Mac. Constrains any "live note in the chrome" idea to a leaf. |
| D-09 | Touch targets ≥ 44 pt; Dynamic Type, VoiceOver, Reduce Motion; colour never the only cue. | Inferred | Hard | 009 validation matrix; 006 finding 2 | The Mac dropped touch sizing on purpose; iOS needs it back. |
| D-10 | Permission-denied, interrupted and failed states are explicit surfaces with a recovery action (denied → Open Settings). | Accepted | Hard | 009 Phase 3 carry-forward, Phase 4 task 5 | Verified states exist in `IOSAudioStatus`. No multi-page onboarding unless testing proves a need. |
| D-11 | Modules keep their hierarchy — title, controls, stage, explanation — and adapt through shared layout primitives, never ten one-off fixes. | Inferred | Hard | 009 Phase 6 tasks 1–2 | `ModuleLayout` is already the shared skeleton. |
| D-12 | Fixed-shape modules (Chords, Pentatonic, Harmonizing) keep `StandardTuningNotice`. | Accepted | Hard | CLAUDE.md decision | Those frets detune rather than transpose. |
| D-13 | Workstream 008's live-note capsule contract holds wherever the live note appears on a module. | Accepted | Hard | 008 (landed) | LISTENING label, capsule tint, 180–220 ms fade, leaf-only reads. |
| D-14 | iPad uses its width (sidebar, full board visible) rather than a stretched phone UI. | Inferred | Soft | 009 validation matrix "Regular UI" | Physical iPad measurement is deferred; Simulator references cover layout. |
| D-15 | The readout resets to neutral on Stop. | Accepted | Soft | Phase 3 device finding | The smoke view kept the last level after Stop. |

## 3. Open questions and assumptions

| ID | Question or assumption | Why it matters | How to resolve | Owner |
| --- | --- | --- | --- | --- |
| Q-D1 | Does listening stay on while browsing modules (live note on modules), or only on Listen? | Decides whether B/D's persistent live note is a feature or a battery/privacy cost; mic indicator stays lit. | Owner preference + device test of the mic indicator while in a module. | Owner |
| Q-D2 | Module portrait fallback board: horizontal scroll strip vs a vertical neck. | Portrait is now the fallback for modules only (D-18), so the scroll strip is the default; a vertical neck is a later experiment. | Revisit only if the portrait fallback feels poor on device. | Owner |
| Q-D3 | Does the board auto-follow the live note, or only jump on request? | 009 Phase 5 task 4: auto-follow only if it doesn't fight touch. | Device test in the SwiftUI pass. | Owner + device |
| A-D1 | Assumed: iPhone is the primary device; iPad is a regular-width adaptation of the chosen direction, mocked after selection. | Keeps round 1 focused. | Owner can overrule. | Owner |
| A-D2 | Assumed: Chords is the representative module for mocks (menus, root chips, stage, notice, readout, strum). | Covers the hardest module shape. | Swap if the owner prefers another. | Claude |

## 4. Reference library

| Reference | Pattern | Informs | Adapt | Don't copy |
| --- | --- | --- | --- | --- |
| iOS Music / Podcasts "Now Playing" bar | Persistent mini state above the tab bar that expands to full | B's live-note pill; D-02 | A leaf-view mini readout that expands to Listen | Media transport controls |
| Apple Maps / Find My | Map as permanent stage with a detented bottom sheet for content | D (board stage) | Board as the stage; controls in a sheet | Search-first sheet |
| Apple Clock / Weather | Tab bar of peer tools, each full-screen | A | Two peers: Listen and Learn | Many tabs |
| iOS Settings / Files (iPad) | Sidebar ↔ list-push adaptive split view | C; D-14 | `NavigationSplitView` compact collapse | — |
| GuitarTuna / Fender Tune | Big note + needle, instant listening | Listen screen hierarchy | Glanceable tuner at arm's length | Ads, upsell chrome, skeuomorphic headstocks |
| Yousician | Horizontal scrolling neck in landscape | D-06 | Scroll strip with position indicator | Gamified clutter |

## 5. Solution array

Every direction shares the same **Listen content** (compact status + Notes/Chords
control, big note + cents gauge, level, history strip, board) and the same
**Settings** (native grouped form: Sensitivity; Tuning; Board orientation; Live
note on learning tabs; Board glow; Usage data). Directions differ in structure:
how you move between Listen, the ten modules and Settings, and where the board
lives.

### A — Two Tabs

- **Idea:** Listen and Learn are peers in a native tab bar; Settings is a gear
  opening a sheet.
- **Optimises:** instant, obvious switching; zero learning curve.
- **Structure:** `TabView` { Listen, Learn }. Learn = grid of ten module cards →
  push the module. iPad: sidebar-adaptable tab view → sidebar with Listen + the
  ten modules.
- **Interactions/states:** tab switch keeps each tab's position; module has
  back; denied/interrupted states render inside Listen.
- **Removes:** the always-visible module list; any home screen.
- **Reuses:** all module screens, chips, board; new: `ModuleCard`.
- **Risks:** Listen and a module are never visible together; the live note on a
  module relies on 008's header capsule.
- **Prototype:** tab switch, Learn grid → Chords, Settings sheet, landscape Listen.

### B — Listen Home + Library

- **Idea:** Listen *is* the app; the ten modules are a library sheet pulled up
  over it; a module opens full-screen with a live-note pill that expands back to
  Listen.
- **Optimises:** D-02 most strongly — the tuner is always one gesture away and
  the live note follows you.
- **Structure:** root = Listen. Bottom "Learn" handle → sheet (medium: module
  strip; large: full library). Module = full-screen cover with a live-note pill
  (leaf) at the top; tap pill or close → Listen.
- **Removes:** tab bar, navigation stack for top level.
- **Reuses:** 008 capsule as the pill; new: `LibrarySheet`, `LiveNotePill`.
- **Risks:** non-standard top-level navigation (discoverability); keeps the mic
  on while in modules (Q-D1); sheet + module cover nesting.
- **Prototype:** pull up library, open Chords, tap pill back to Listen.

### C — Sidebar Mirror

- **Idea:** the Mac's structure made native — a list of Listen + Learn (ten
  modules) that becomes a sidebar on iPad.
- **Optimises:** consistency with the Mac; every destination visible in one list.
- **Structure:** `NavigationSplitView`. iPhone launches straight into Listen
  pushed on the list ("‹ Fretwork" back); list rows are static (no live data,
  D-08). iPad: sidebar + detail, like the Mac.
- **Removes:** tab bar, cards.
- **Reuses:** Mac information architecture; no new navigation components.
- **Risks:** on iPhone, "back" to reach a module is one extra tap each time;
  launching pushed-in is slightly unusual.
- **Prototype:** launch on Listen, back to list, open Chords, Settings from the
  list's toolbar.

### D — Board Stage (retired as navigation, 2026-09-28)

> Fails D-16: its premise is a board always on screen, including portrait
> Listen. Its landscape arrangement (board full width, controls in a side
> panel) is carried forward as module layout **M1** below.


- **Idea:** the fretboard is the permanent stage; Listen and each module are
  *modes* of that stage, chosen from a chip rail; controls live in a detented
  bottom sheet.
- **Optimises:** instrument feel; landscape; one board you never lose.
- **Structure:** top: mode rail (Listen · Notes · Intervals · …). Middle: board
  (scrolls horizontally in portrait, full in landscape). Bottom sheet: the
  current mode's controls/readout (Listen: tuner; module: its controls and
  explanation).
- **Removes:** screens-as-pages; module headers compete for less space.
- **Reuses:** board, chips, module models; new: `ModeRail`, `StageSheet`, and a
  module layout that splits "stage" from "controls" (bigger Phase 6 change).
- **Risks:** biggest departure from `ModuleLayout` (D-11 Partial); explanation
  prose is buried in a sheet; the Circle of fifths isn't a board.
- **Prototype:** switch Listen ↔ Chords on the rail, raise the sheet, landscape.

### Module landscape layouts (new in round 2)

Independent of navigation — whichever of A/B/C wins, a module in landscape uses
one of these:

- **M1 — Side panel:** the neck fills the left ~62% at full height (all 15–22
  frets visible); a right glass panel (~300 pt) holds the module's controls,
  with the explanation behind a disclosure. Everything visible at once.
- **M2 — Bottom drawer:** the neck spans the full width; the controls live in a
  short drawer under it (one row visible: root chips + primary action), which
  expands for menus and explanation. Maximises neck height; controls are a tap
  away.

Portrait fallback (both): header, controls stacked, board as a horizontal
scroll strip, explanation last — today's `ModuleLayout` order (D-11).

### Coverage matrix

| Constraint | A Two Tabs | B Listen Home | C Sidebar Mirror | D Board Stage | Notes |
| --- | --- | --- | --- | --- | --- |
| D-16 No board on portrait Listen | Meets | Meets | Meets | **Fails** | D retired as navigation |
| D-18 Module landscape room | Partial | Meets | Partial | — | A's tab bar and C's nav bar cost ~49/32 pt of 390; both hide chrome inside a module to recover it. B's full-screen module has none |
| D-02 Listen primary/launch | Meets | Meets (strongest) | Partial | Meets | C lands on Listen but the root is a list |
| D-03 Portrait = landscape | Meets | Meets | Meets | Meets (landscape strongest) | All mocked in both |
| D-04 Identity + native idioms | Meets | Partial | Meets | Partial | B/D invent top-level patterns |
| D-06 22 frets on iPhone | Meets | Meets | Meets | Meets | Same scroll board |
| D-07 Absent Mac controls | Meets | Meets | Meets | Meets | |
| D-08 Leaf-only audio reads | Meets | Partial | Meets | Meets | B's pill must be a leaf; feasible |
| D-09 Touch/a11y | Meets | Meets | Meets | Partial | D's rail chips are small in portrait |
| D-10 State surfaces | Meets | Meets | Meets | Meets | |
| D-11 Module hierarchy via shared primitives | Meets | Meets | Meets | Partial | D splits stage/controls |
| D-13 008 capsule | Meets | Meets | Meets | Meets | |
| D-14 iPad uses width | Meets | Partial | Meets | Meets | B's sheet on iPad needs rethinking |

## 6. Recommendation or selection test

**Selected (owner, 2026-09-28): C + M2** — C for native consistency with the Mac and a free iPad sidebar, accepting one extra tap between a module and Listen; M2 because landscape is for the neck (D-03). Per-module drawer contents: see §7 table (to fill in Phase 6).

**Round 2 leaning (superseded): B, with A close.** The orientation model favours B — its full-screen module gives the landscape neck the whole height, and portrait Listen as home is exactly the tuner-first job. A stays strong if the tab bar is hidden inside modules. Round-1 reasoning follows for history.

**Round 1: leaning A**, with B as the serious alternative. A meets every hard constraint
with native idioms and costs the least in Phase 6; B serves the primary job best
but invents navigation and keeps the mic open in modules. C is the safe Mac
mirror but makes the primary job a pushed screen. D is the boldest and the most
instrument-like, but it partially fails D-11 and makes Phase 6 a redesign rather
than an adaptation.

**What would change it:** if the owner wants the live note visible while
learning (Q-D1 = yes), B rises; if landscape playing turns out to dominate, D
rises.

**Selection test:** react to the four clickable portrait mocks + landscape Listen
on the phone-sized canvas; then the chosen one (or a named hybrid) gets a SwiftUI
pass on the iPhone.

**Owner decision:** _pending_.

## 7. Component and prototype plan

- **Reuse:** `NotePalette`, `GlassCard`, `ChipPicker`/`ToggleChip`/
  `PitchClassPicker`, `FretboardBoardView`/`FretboardDot`, `TunerPanel`,
  `InputLevelPanel`, `HistoryStrip`, `ModuleLayout`, 008 live-note capsule,
  `StandardTuningNotice`.
- **New (explore in isolation first):** compact `ScrollingFretboard` (position
  indicator, jump-to-note), iOS `ListenScreen`, iOS `SettingsSheet`, and per
  direction: `ModuleCard` (A), `LibrarySheet` + `LiveNotePill` (B), `ModeRail` +
  `StageSheet` (D).
- **Round 1 surface:** HTML design canvas (link above) — iPhone 390×844 portrait
  and 844×390 landscape, clickable.
- **Round 2 surface:** SwiftUI prototype of the chosen direction on the owner's
  iPhone, fed by the real audio controller.
- **Mocked:** all data in round 1 (sample notes, fixed Chords state).
- **Production boundary:** nothing merges to the app until the owner signs off
  round 2.

## 8. Validation plan

| Task | Reviewer | State | Success | Failure |
| --- | --- | --- | --- | --- |
| Open app, play a note | Owner | first launch, granted | Note visible with zero taps | Any tap needed before listening |
| Find and open Chords, back to Listen | Owner | normal | ≤ 2 taps each way, obvious | Hunting, dead ends |
| Change tuning | Owner | normal | Found in Settings in one step | Buried or ambiguous |
| Read fret 17 in portrait | Owner | Listen, note at fret 17 | Reachable, legible, touchable | Microscopic or unreachable |
| Mic denied | Owner | denied | Clear message + Open Settings | Blank tuner |
| Phone call mid-listen | Owner | interrupted | Clear "paused" state, auto-resume | Stale readout |
| Landscape Listen + module | Owner | rotated | First-class, not stretched portrait | Clipped or wasted space |
| Smallest iPhone, largest Dynamic Type | Simulator | SE class | No clipping/overlap | Clipped controls |
| VoiceOver through Listen and a module | Simulator/owner | — | Every action reachable, sensible order | Unlabelled icons |

## 9. Parking lot

- Circle of fifths on iPhone portrait (ring 320 pt + board) — needs its own
  compact arrangement in Phase 6.
- History strip: keep on iPhone or collapse behind a disclosure?
- Guided-practice readouts (Pentatonic/Scales) at compact width.
- 007's "listening vs playing" indicator will need a home in whichever shell wins.

## 10. Decision log

| Date | Decision | Evidence / rationale | Constraints affected | Revisit when |
| --- | --- | --- | --- | --- |
| 2026-09-28 | Mock in HTML, then SwiftUI on device, then build. | Owner answer. | D-05 | — |
| 2026-09-28 | Mac identity, native iOS idioms. | Owner answer. | D-04 | — |
| 2026-09-28 | Portrait and landscape equally first-class. | Owner answer; resolves 009 Q-02. | D-03 | — |
| 2026-09-28 | Listen/tuner is the primary job. | Owner answer. | D-02 | — |
| 2026-09-28 | Portrait for tuning/listening, landscape for the fretboard; portrait Listen has no board; rotating Listen reveals the neck; modules prefer landscape but work in portrait. | Owner answers after round 1. | D-03, D-16, D-17, D-18 | After the SwiftUI device pass |
| 2026-09-28 | Retire D as navigation; keep its landscape stage as module layout M1. | D fails D-16. | D-16 | — |
| 2026-09-28 | Select navigation C and module layout M2; M2 shows only position arrows + live note, the rest in a slide-up drawer. | Owner choice after round 2. | D-20, D-21 | After the SwiftUI device pass |
| 2026-09-28 | Sample Capture is developer-only, never on iOS. | Owner. | D-19 | — |

## 11. Change log

| Date | Constraint delta | Sections rewritten | Directions added/changed/retired | New decision needed |
| --- | --- | --- | --- | --- |
| 2026-09-28 | Created from the evidence brief and four owner answers. | All | A, B, C, D added | Choose a direction after reacting to the mocks; Q-D1, Q-D2. |
| 2026-09-28 | D-03 rewritten (orientation follows the job); D-16/17/18 added. | Header, §2, §3 Q-D2, §5 (D retired, M1/M2 added, matrix), §6 | D retired; M1, M2 added | Pick A/B/C and M1/M2 from round 2. |
