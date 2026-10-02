# Changelog

All notable changes to Fretwork are recorded here, newest first. The Mac app
and the iPhone/iPad app version independently; entries are labelled when they
apply to only one platform.

## 0.3.0 (iOS) — 2026-10-01

- iPad landscape Listen follows the Mac Listen: the note readout + cents gauge
  at the top, the neck at Mac proportions (the same ~43pt string spacing and
  scale-1 dots as the Mac and the hosted module screens — a fixed 260pt neck
  instead of stretching six strings across ~1000pt), and the input meter at
  the bottom. The landscape top bar drops the back chevron (Listen is a
  top-level sidebar destination) and the duplicate live-note capsule.
- One primary action on the iOS scaffold: every module's Play/Strum/Practise
  lives in the trailing corner of the bottom band, one size (44pt tall,
  min 132pt wide, `.body` semibold), rendered through the shared
  `IOSModulePrimaryAction` tinted-glass capsule (accent wash, accent text,
  contrast ~9.8:1) instead of a bright filled button. Stop lands in the same
  place via the in-place D-27 toggle. Applies to iPhone in both orientations
  and iPad portrait.
- Removed the iPad-only height-driven board scaling (`IOSBoardScale`): iPad
  landscape now hosts the Mac screens (scale 1), so nothing else needed it.

- The iPad sidebar's selection highlight now slides between rows with the
  app's gravity spring instead of jumping; Reduce Motion moves it instantly.
- iPad module buttons never wrap their label onto two lines ("Play
  progression"); the action group moves to a new row instead.
- Removed `UIRequiresFullScreen` again. It had been added back only so a
  screenshot harness could rotate the simulator, which cost iPad users Split
  View and Stage Manager.

## 0.2.1 (iOS) — 2026-10-01

- iPad landscape now hosts the shared Mac module screens unchanged, so a
  landscape module looks like its Mac screen — title/blurb/live-note header,
  inline controls, a Mac-proportioned board (scale 1, 12 frets with the Full
  neck toggle) and the readout below, with no drawer. The Mac screens already
  compile into the iOS target and already carry the live-note capsule,
  `StandardTuningNotice`, the retune hook and the in-place guided-run
  behaviour, so nothing was forked. iPhone (both orientations) and iPad
  portrait keep the iOS scaffold.
- The hosted screens show iOS wording for the "samples not ready" notice
  ("Notes will not sound until audio is ready." — iOS has no device picker),
  and the live-note capsule swaps LISTENING → PLAYING during the iOS playback
  gate (a new `AudioControlling.isSuppressingForPlayback` default keeps the
  Mac capsule pixel-identical).
- The snapshot harness now syncs its initial selection to
  `AppState.selectedScreen`, so the hosted screens' `prepareSamplePlayback`
  gate actually fires for a pre-set selection — without it the snapshot (and
  any restored selection) would silently never prepare playback.

## 0.2.0 (iOS) — 2026-10-01

- Added the one-time iOS unlock (StoreKit 2, non-consumable
  `org.fretwork.app.ios.unlock`). Listen and the Notes module stay free; the
  other nine modules show a lock and open a native sheet with the App Store
  Connect price (`Product.displayPrice`), one-time wording, and Restore
  Purchases. Verified entitlements are checked at launch and kept current for
  the app's lifetime; unverified transactions grant nothing. The Mac app is
  unchanged and stays free.
- Prepared the iOS app for App Store submission. The release bundle now ships a
  `PrivacyInfo.xcprivacy` declaring no tracking and no collected data (the only
  required-reason APIs are `UserDefaults` CA92.1 and system boot time 35F9.1),
  `Info.plist` answers the export-compliance question once
  (`ITSAppUsesNonExemptEncryption = false`), and the microphone usage string
  says plainly that audio is analysed on this device and never recorded or
  sent. The DEBUG-only harnesses (Phase 1 capture, Phase 3 smoke, speaker-bleed
  probe) are compiled out of Release, so a release archive carries no harness
  symbols and no launch-argument surface; a stray developer `README.md` no
  longer ships in the bundle. Removed the anonymous usage-data opt-in from the
  iOS app: opt-in analytics is still data collection under Apple's rules, and
  the App Store build declares none. Store copy, privacy policy and support
  page are drafted under `docs/app-store/`.

## 0.5.9 — 2026-10-02

- Rebuilt the learning modules' control row as one shared labelled-cell card
  (`ModuleControlCard` in `ModuleLayout.swift`) instead of ten near-identical
  hand-rolled rows. Each control now sits in a cell with a small caps caption
  (the ROOT caption style); every cell keeps its natural width, the row's
  leftover space is distributed between cells (justified), and a cell that
  doesn't fit moves whole to the next row. A chip group (degree chips, layer
  chips) is always one line inside its cell, never wrapped or squashed. The
  primary action (Play/Strum/Practise/…) and its Stop now form one
  fixed unit in the last cell at one size in every module, instead of changing
  size and position between modules. Triads' four stacked lines became one row;
  Note association's four ragged sections became two balanced rows; Notes'
  Play/Stop and Clear all were split apart (Clear is destructive and stays far
  right).
- Refined the control card's flow rule after the first build: cells no longer
  receive an equal share of leftover width — that made chip groups wrap inside
  a cell that was wider than the chips needed. Degree rows now render on one
  line via `ChipPicker(singleLine:)`, and layer toggles via a single-line
  `ModuleChipRowLayout`. Harmonizing is Mode · Labels on row 1 and the degree
  row with Play chord on row 2; Note association is Mode · Labels · Layers,
  then the degree row with Progression and the actions, wrapping the action
  group to a right-aligned third row only when narrow. Scales no longer wraps
  its options card in a second options card (a card-in-card on Mac and iPad).
  Re-shot all ten modules at the Mac min/wide widths and iPad Pro 13 landscape:
  none grew taller, and the other seven are unchanged.
- iPad landscape (which hosts these Mac screens unchanged) now styles the
  controls with Liquid Glass: the primary action is a tinted glass capsule with
  a faint accent wash and accent text/icon (contrast ≥ 4.5:1 on the dark
  backdrop), and every menu picker and secondary action is a plain glass
  capsule. The Mac keeps its existing button and picker look. One
  platform-conditional style in `ModuleLayout.swift`, so iPhone's scaffold
  screens stay pixel-identical.
- Added a `ModuleScreenSnapshotTests` harness that renders all ten screens at
  the Mac's minimum detail width and a wide window, and a
  `-IOSSnapshotSidebarClosed` launch argument so iPad landscape can be captured
  with the sidebar open and closed.
- Note association keeps Progression, Loop and the play buttons together as
  one full-width group on their own row (row 2, or row 3 when the chord
  chips wrap on a narrow window): the progression part at the leading edge,
  the play actions at the trailing edge, flexible space between — and when
  the row is too narrow for both on one line, the play part wraps below,
  still trailing, with nothing truncated.
- Note association's layer switches left the control card for the board's
  header row — the line that already holds Full neck. They are now a
  left-aligned SHOW caption and three compact chips, each carrying its
  layer's role colour as a dot (filled when on, hollow ring when off), the
  same colours the board and the old legend used; Full neck stays pinned
  right and the row stays 20pt tall. `FretRangeToggle` gained an optional
  leading slot (empty leading stays the bare button) so the eight other
  modules that use it are pixel-identical. The card's first row is now
  Mode · Labels · Chord (Chord wrapping whole to its own row when narrow),
  and the now-duplicate colour legend left the readout. Card height:
  352pt at 750 (−5), 265pt at 1300 (±0).
- Starting or stopping a run no longer changes the control card at all. The
  count-in no longer inserts a "Count in… N" line below the buttons (which
  pushed every cell below it down) — it now swaps the primary button's label
  in place, reserving the widest label's width so the button and its
  neighbours never move, and the button reads the count for accessibility.
  Pentatonic, Scales and Triads' tempo cell (tortoise · N bpm · hare · the
  run progress) is now always present instead of being inserted only while a
  run is active, so tempo can be set before starting; the progress shows
  "– / N" when idle at a reserved monospaced width. iPhone mirrors the same
  rule in its scaffold: the count-in lives in the band button and the tempo
  row is reserved rather than revealed. A new
  `ModuleControlCardStabilityTests` pins each module idle/count-in/mid-run
  and asserts the control card height is identical.
- The Mac app icon now matches the iPhone and iPad icon (six coloured string
  pills), drawn on the standard macOS rounded-square grid.

## 0.5.8 — 2026-10-01

- Fixed the Circle of Fifths spelling every flat-side key as sharps. The ring,
  the selected key title and the tonic-triad labels read their names from a
  `PitchClass`, whose default spelling is sharp, so the flat half displayed
  A♯/D♯/G♯/C♯ instead of B♭/E♭/A♭/D♭ and F major's IV showed as A♯. Added a
  key-aware `Key`/`Keys.circleOfFifths` in Theory, which spells each key from
  its own letter, so the ring now reads C G D A E B F♯/G♭ D♭ A♭ E♭ B♭ F and a
  flat key's scale and triad use flats. Sharp keys are unchanged.

## 0.5.7 — 2026-10-01

- Added a noise-floor-relative gate, a pitch-stability gate for new notes, and
  a sustain hold to note detection, and relaxed the YIN cutoff at low
  frequencies. Pitched room noise (TV, voices, mains hum) that previously
  confirmed as phantom notes is now rejected unless it clears the running noise
  floor plus a sensitivity-folded margin and holds a steady pitch, a confirmed
  note is held while the same pitch continues at lower confidence instead of
  blinking out as it decays, and weak low strings (e.g. an unplugged electric
  low E) now produce a candidate, where the fixed YIN cutoff produced none.

## 0.5.6 — 2026-09-23

- Released Fretwork with Apple Developer ID signing, hardened runtime, and
  notarization so the direct Mac download is trusted by Gatekeeper.

## 0.5.4 — 2026-09-02

- Fixed production updates by publishing Sparkle delta archives and purging
  every generated archive from the download edge cache after a release. This
  keeps the appcast signature and the file a client downloads in sync.

## 0.5.3 — 2026-09-02

- Added optional, anonymous usage telemetry. It is off by default and sends at
  most one activity pulse per day when enabled in Settings. It records only
  the app version and a coarse country code inferred at the network edge —
  never audio, detected notes/chords, practice history, audio-device details,
  identity, IP address, precise location, or a persistent installation ID.
- Learning tabs can now show the live detected note and softly highlight
  matching fretboard dots. Both remain optional, and the controls and module
  layouts now use the same stable spacing across the app.

## 0.5.2 — 2026-08-29

- A note placed or played on a module's fretboard no longer lurches. The dot's
  playback pulse resized its *frame*, while `.position` — which centres the dot
  on its fret — sits outside the dot view in a different animation scope. The
  grow ran inside the caller's `withAnimation` so the two moved together, but
  the release is a bare write from a detached task, so the position snapped to
  the small frame's origin while the drawn size was still shrinking: the dot
  jumped 4.5pt down-right in a single frame and crept back over the next 260ms.
  The pulse is a `scaleEffect` now, which scales about the centre and changes
  no layout, so nothing can displace the dot whatever animates it. Measured
  before and after by tracking the dot's own pixels: the centroid now holds to
  within 0.03px across the whole pulse. The arrival and pulse springs are also
  critically damped, replacing curves that overshot and rang for 1.73s.
- Launching with an audio interface no longer flashes a "Reconnecting to audio
  device…" bar that pushes the whole Listen screen down and back. The graph
  build sets its own settle window — the guard that tells our own start-up
  churn apart from a device renegotiating — and it was measured from the moment
  the build *began* rather than from the moment the graph went live. The buffer
  size the build itself sets provokes a Core Audio configuration change, and on
  any device that takes longer than 1.5s to bind that notification arrived with
  the window already expired, so the app restarted the graph, which provoked
  the same notification again. Measured with a 2s simulated bind: three full
  restart cycles before the circuit breaker stopped it, with the bar appearing
  and vanishing on each pass. A built-in device binds in ~170ms and never hit
  it; a USB interface does.
- A slow first start now says "Starting…" rather than "Reconnecting" — there is
  nothing to reconnect to yet — and says it in the header's status pill instead
  of a bar that moves the screen. The pill reserves the width of its longest
  word, so it changes without shifting the controls beside it.
- The telemetry row on Listen no longer shifts sideways a few frames after
  launch. Audio starts 100ms after the window appears, and until it reported
  the row rendered its zero-valued defaults as a confident "0 frames · 0.0 ms
  · Buffered"; the real values are wider, and because the row is centred,
  filling them in slid every reading across. The row now shows "—" until the
  device has actually reported, and every readout reserves the width of the
  widest value it can hold.

## 0.5.0 — 2026-08-27

- Every learning module now shares Listen's own material rather than sitting
  as plain text on the background the way the ported web layouts did: a
  translucent glass card, flat and translucent rather than a beveled 3D
  gradient, with a highlight that slides between chips on selection instead
  of an instant colour swap. One shared component (`ChipPicker`/
  `PitchClassPicker`) replaces eleven near-identical "root button"
  implementations that had drifted apart across the modules.
- Every module's note/key picker now sits in its own fixed-size card, held to
  the same position whatever module you're on, with a second card below it
  for everything else that module's controls hold — instead of one card
  whose height (and the picker's position within it) swung around depending
  on how much else that module happened to have underneath.
- Every note marker is now a flat, translucent fill with a soft glow instead
  of a hard white edge — a radial gradient plus a top-left glint was tried
  first and is gone again, since a light source standing in for a specular
  highlight is exactly the "3D" look the chips also had to lose. Applied
  everywhere a dot is drawn, so Listen's detection board changed too.
- Fixed a dot's arrival on the neck actually looking like a pop rather than a
  grow — the third pass at this, and the first one backed by a controlled
  measurement rather than a theory. A screen recording seemed to show real
  dropped frames, and the previous entry here blamed per-dot `.shadow()`
  rasterisation cost and added `.drawingGroup()` to fix it; re-examining that
  recording properly (correlating every timing gap against actual pixel
  activity, since idle periods between taps and cursor movement both produce
  the same kind of gap) found no dropped frames in it at all. The real cause,
  found instead by capturing a dot's actual entrance frame-by-frame from an
  offscreen host: `Animation.bouncy`'s scale (0.6 to 1) had travelled almost
  the whole way to full size within 2–3 frames, with the rest of its 0.5s
  duration spent on a wobble too small to see — technically smooth, but
  reading as pop-then-flicker rather than grow. The fix is a longer,
  dedicated spring for just this transition (0.85s, decoupled from the
  chip-highlight spring the two used to share), verified the same way —
  recapturing the same frame sequence and confirming the size now visibly
  progresses across five or six frames instead of two. `.drawingGroup()`
  stays, since flattening dozens of shadowed dots into one composited layer
  is still sound practice — it just was not the bug. Dots also no longer
  slide in from an adjacent string; they materialise in place and bounce to
  size, which reads as one clean event even when many appear together.
- A direct tap on the fretboard (`FretboardBoardView`'s own `onHit`/
  `onLongPress`) now explicitly wraps the resulting mutation in
  `withAnimation`, rather than relying only on the board's ambient
  `.animation(_:value:)` to pick up a change made from inside a gesture's
  `onEnded` closure. This is a real, defensible fix — a Button action and a
  gesture's `onEnded` do not carry the same implicit transaction — but a
  substantial, controlled investigation this session (comparing a bare
  board, a densely populated one, and a close reconstruction of the full
  module screen, all captured frame-by-frame from an offscreen host) could
  not reproduce the reported "pops instead of grows" behaviour as
  consistently or as severely as an earlier, less careful pass at the same
  comparison had suggested. Recorded here rather than claimed as solved:
  the entrance animation measures as working correctly in every controlled
  test this session could construct: if it still reads as wrong in the
  running app, the cause is something this offscreen-capture approach
  cannot see — real gesture-recognition latency, real display compositing,
  or something else outside what a headless render can reproduce.
- Tapping a fretboard dot or cell now always sounds it, in the two modules
  (Intervals, Octaves) where that tap moves a shape but previously stayed
  silent. The root/key menu above every board deliberately stays silent on
  a tap — only touching the instrument itself makes a sound.
- Triads, Chords and Octaves' "move this shape along the neck" controls now
  sit directly above the board rather than flanking its two ends, so the
  board — the widest thing on any of these screens — keeps the full width
  those two 32pt columns used to cost it.
- Every module can now widen its board to the full 22-fret neck for
  reference, without changing the shape it's teaching or, for Notes, breaking
  the honesty of tapping to place a note past its usual ceiling.
- Fixed a small window-size jump the very first time the app left the Listen
  screen for a module screen. The window's automatic resizability was
  re-deriving an "ideal" size from whatever screen was on screen, and Listen's
  ideal size and a module screen's aren't the same number; the window now
  treats its declared minimum as the one fixed baseline instead.

## 0.4.0 — 2026-08-27

- Fretwork is now a multi-screen app. The listening screen you already had is
  unchanged and still where the app opens; alongside it are **ten learning
  modules**, ported from the web app so the two teach the same course in the
  same order.
- **Notes on the fretboard** — tap anywhere to drop a note, or light up every
  position of a note at once. The board names what you have placed and finds the
  chord in it.
- **Intervals** — a root and one related note, anchored anywhere on the neck.
  The same fifth is a different physical move on each string, and the board
  shows every root you could anchor on.
- **Octaves** — the movable two-string shape, plus a recall round that hides the
  octave and asks you to find it. A wrong answer plays the note you actually
  picked, so you can hear that it is not an octave.
- **Triads** — every compact shape and inversion, double stops, and diatonic
  paths that walk a key along one set of three strings without your hand
  leaving them.
- **Major, minor & power chords** — movable shapes traced back to their root,
  3rd and 5th, with muted strings marked rather than quietly omitted.
- **Pentatonic scales** — the five boxes, singly, in pairs, or as a three-box
  path, with guided practice: a four-beat count-in, one note per beat, and the
  fretting finger for the note you are on.
- **Scales** — one-octave major and natural minor, labelled by note or by
  degree, played ascending or up and down.
- **Harmonizing the scale** — pick a degree and see the chord that falls out of
  it, next to the three stacked scale tones that produced it.
- **Note association** — the whole key on one neck, each note coloured by what
  it is doing over the chord playing right now. Play a progression and the
  colours move while the notes stay still.
- **Circle of fifths** — the twelve keys and their relative minors, with the
  selected key's tonic triad on a board beside it.
- Every board and every played note now follows one **tuning**, chosen once and
  applied everywhere. The tuning setting has existed in the saved document since
  0.1 but was never read back until now.
- Settings — devices, monitor, sensitivity, tuning and board orientation — moved
  out of the listening screen's header into the toolbar, reachable from any
  screen. The window is 430pt narrower as a result.
- Board orientation is now remembered between launches instead of resetting.
- Fixed the app becoming unresponsive to every audio control when a device stops
  answering. Building the audio graph now happens off the control path, so you
  can still pick a different device while a bad one is hanging, and the app says
  the device is not responding rather than going quiet with no explanation.

## 0.3.0 — 2026-08-26

- The app now plays real recorded guitar. Every position on the neck — six
  strings, frets 0 to 22 — was captured DI from one instrument in one session
  and ships in the app, so a reference note sounds like a guitar rather than
  like a synthesiser approximating one. In standard tuning nothing is
  resampled: each position plays its own recording.
- The other fourteen tunings shift the nearest recording from the *same*
  string rather than borrowing the right pitch off a different one, which keeps
  each string's character. Even Drop A, the furthest stretch in the set, plays
  77% of the neck from untouched recordings.
- Notes can be played polyphonically, with a new note on a string releasing
  whatever was ringing on it, as a real guitar does.
- Monitor level and playback level are now independent controls, so turning
  your own signal down no longer turns the app's playback down with it. Monitor
  mute is now an attenuation to -96 dB rather than a hard disconnect;
  inaudible, but it is not a true zero if you are watching a meter.
- Fixed clicks and timing jitter in the recorded library. The recorder's onset
  detector fires late on a soft attack, which left a third of the takes
  trimmed into their own transient and a spread of up to 15 ms in where a note
  began. Onsets are re-measured when the library is built, so notes now start
  in time with each other, and a short attack fade removes the step out of
  silence that every take began on.

## 0.2.0 — 2026-08-22

- Added in-app updates via Sparkle 2.9.6, with a "Check for Updates…" item in
  the app menu and a daily background check. Updates are authenticated by an
  EdDSA signature on the downloaded archive rather than by Apple notarization,
  which is what makes self-distribution outside the App Store workable.
- Fixed the app failing to launch at all once a framework was embedded. The
  project never set `LD_RUNPATH_SEARCH_PATHS`, so `Sparkle.framework` was
  copied into the bundle but had no runpath to be found through, and dyld
  aborted at startup. The test suite did not catch this — xctest injects its
  own framework search path, so only a direct launch showed it.
- Custom `Info.plist` keys now come from `Config/Info.plist`, merged with the
  generated one, since Sparkle needs keys the `INFOPLIST_KEY_*` settings
  cannot express.

## 0.1.0 — 2026-08-22

First release prepared for distribution outside Xcode.

- Release builds are now actually optimized. The project-level build
  configurations were empty, so `SWIFT_OPTIMIZATION_LEVEL` and
  `SWIFT_COMPILATION_MODE` were unset and every Release build compiled at
  `-Onone`, one file at a time — shipping an unoptimized YIN detector to
  users. Release now builds `-O` whole-module, Debug is pinned to `-Onone`
  single-file explicitly rather than by accident.
- Added `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, which the project
  had never defined. Both are required before an updater can compare one
  build against another.
- Renamed the bundle identifier from `com.fretlight.app` to
  `org.fretwork.app`, matching the product name while there are no installed
  copies whose saved settings and microphone grant it would strand.
- Added an app category and copyright to the generated `Info.plist`, plus
  `LICENSE` (MIT) and this changelog.
