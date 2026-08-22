# Changelog

All notable changes to Fretwork are recorded here, newest first.

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
