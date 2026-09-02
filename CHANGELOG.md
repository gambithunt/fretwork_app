# Changelog

All notable changes to Fretwork are recorded here, newest first.

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
