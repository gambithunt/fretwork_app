# Changelog

All notable changes to Fretwork are recorded here, newest first.

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
