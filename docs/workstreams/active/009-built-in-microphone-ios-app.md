# Workstream 009: Built-In-Microphone iPhone and iPad App

## Status

**Phase 0 complete (2026-09-18).** Its one recorded exception — the pre-existing
Mac test compile failure — was repaired in `3e0a461` before Phase 2.
**Phase 1 complete on iPhone (2026-09-28).** Capture, primitive selection,
latency, CPU/thermal, permission states and the acoustic/amplified-electric
guitar sweep all pass on the iPhone 14 Pro Max. The iPad Pro 13-inch (M5)
measurement is deferred by the owner and is the only open Phase 1 item.
**Phase 1 Simulator-first slice implemented (2026-09-19).** The Simulator slice validated the synthetic detection
pipeline, the manual harness UI and telemetry, permission/inert-launch/fake-
injection behavior, and realtime-aware callback wiring — all without microphone
hardware.

**Phase 6 landscape complete (2026-09-30), merged in `bf1dd5b`:** all ten modules on the shared M2 scaffold per D-26..D-28, independently reviewed, owner-verified on device. **Phase 6 complete (2026-09-30):** portrait built from the same scaffold (D-18 revised) and guided runs that leave the screen still (D-27 revised); independently reviewed; owner-verified on device.

**Phases 4–5 complete on iPhone (2026-09-29), merged in `3473449`.** Built from the device-tested C + M2 prototype per `009-ios-interface-design.md` (D-01..D-25): list→push shell on iPhone (sidebar on iPad), native Settings, portrait tuner-only Listen, landscape full-neck Listen with one glass chrome row, Chords in the M2 landscape layout, denied/paused/failed/stopped surfaces with recovery, accessibility pass. Independent review caught a deny→grant recovery dead-end and a silently mute Strum (both fixed); a landscape back-navigation layout jump was reproduced and fixed by screenshot. iOS 71/0, Mac 479/0. Owner verified on device. Phase 6 (nine modules) awaits the owner's per-module control table.

**Phase 3 complete on iPhone (2026-09-28).** Production iOS audio controller, bundled samples and all on-device lifecycle checks pass; see Phase 3 result.

**Phase 2 complete (2026-09-27).** The platform-neutral audio seam landed:
`AppState` depends on `any AudioControlling`, no longer imports CoreAudio or
names `AudioDeviceID`, and the shared sources now compile into the iOS target
through a synchronized root plus a per-target exception set. The Mac suite is
478/0; the iOS suite is 30/0.

The minimal `Fretwork-iOS` app target, `Fretwork-iOSTests` target and their shared
schemes exist, build and test on the Simulator; the Mac app builds and launches
unchanged; and every production and test file is classified. Phase 0 added no
existing production source to the iOS target and moved no files. Phase 1 added
explicit `PBXFileReference`/`PBXBuildFile` membership for exactly **seven shared
files** (listed below); Phase 2 then added the full `Fretlight/`
synchronized-root membership and its per-target exception set. The `Fretwork`
module rename and the iOS `NSMicrophoneUsageDescription` that the shared seam
depends on both landed during Phase 0. The recorded exception was the pre-existing
Mac test compile failure (0/453), repaired separately in `3e0a461` before Phase 2.
Full evidence, inventories, commands and risks are in the Phase 0, Phase 1 and
Phase 2 sections and the Implementation Record.

Partially measured on physical hardware: the **iPhone 14 Pro Max (iOS 27.0,
24A435)** capture spike ran, the sink was selected and the tap path deleted,
and the latency, CPU and thermal metrics are now measured on that iPhone. The
permission-state matrix passed on that iPhone. The iPad Pro 13-inch (M5) is
**deferred by the owner for now**.

**C-19/Q-06 resolved 2026-09-18 — option (A) accepted.** The owner confirmed
option A ("ok lets go") after discussing the exact recommended wording, so
C-19 is **Accepted** and Q-06 resolves to **A**. Mac-only files, user-visible
behavior, UI, audio routing/monitoring, configuration, assets, signing, release
tooling and platform-owned source are immutable for Workstream 009. Minimal,
behavior-preserving changes to genuinely shared source and the common
`Fretlight.xcodeproj` are allowed only when required for iOS/iPadOS, each with
explicit classification and Mac regression verification. Option (B) — every file
or project compiled or used by the Mac target immutable, forcing a separate or
copied source architecture — is not adopted, and its consequence does not apply.

Provisioning is sequenced in two stages. Development-level automatic
signing/provisioning, device trust and Developer Mode are prerequisites for the
Phase 1 physical installs; if the configured Development Team cannot provision a
device, Apple Developer Program enrollment blocks Phase 1. Neither physical
hardware nor development provisioning is confirmed ready. The App Store Connect
record and distribution signing remain owner actions deferred to Phase 8. Phase
0 is Simulator-only and needs no provisioning. The pre-existing Mac test compile
failure is a recorded exception until repaired as its own non-iOS change, after
which both suites must be green; see Blockers.

Last updated: 2026-10-01 (Phase 7 complete on iPhone: playback gate measured and shipped, real-guitar sessions recorded, Q-03 decided; iPad measurement deferred; Phase 8 next).

## Objective

Ship Fretwork as a native iPhone and iPad app by reusing the existing Swift,
SwiftUI, music-theory, detection, learning-module and practice-state code while
replacing the Mac's hardware-routing layer with a deliberately simple iOS audio
session.

The ordinary player places an iPhone or iPad nearby and plays. The app listens
through the device's microphone, identifies notes and chords, and runs the same
learning modules as the Mac app. It does not assume that the player owns or
connects an audio interface.

## Required outcome

- One App Store-ready iOS app for iPhone and iPad, targeting iOS/iPadOS 26.0
  and above, intended for public App Store release (C-20, C-22).
- The built-in microphone is the primary capture path. Audio routing is managed
  by iOS; there are no input/output device pickers or rescan controls.
- Live microphone monitoring is absent. Captured microphone audio is analysed,
  never routed back through the device speaker.
- Lesson-note and chord samples still play through the current system output.
- The app cannot detect or credit its own sample playback.
- Existing pitch, chord, position-resolution, tuning, theory, sample-library,
  module and persistence behavior is shared with macOS rather than forked.
- iPad keeps the spacious split-view character of the Mac app. iPhone gets a
  compact navigation and layout designed for its width rather than a scaled-down
  desktop window.
- The Mac app, its independent device routing, direct monitoring and Sparkle
  release path continue to work unchanged from a user's perspective.
- Microphone denial, interruption, route change, backgrounding and recovery are
  visible and recoverable states rather than silent failure.
- The iOS app is verified with a real guitar on physical iPhone and iPad
  hardware. Simulator-only verification is insufficient.

## Non-goals

- User-selectable input or output devices on iOS.
- Recreating the Mac's separate input/output engines, device UIDs, hardware
  buffer control, drift correction, direct-monitoring candidate or rescan UI.
- Live playback of microphone input through the iPhone or iPad speaker.
- Promising first-class USB-interface, Bluetooth-microphone or multichannel
  support. A system-selected external route may work, but this workstream does
  not add UI or special cases for it.
- Background listening, lock-screen practice, recording, sharing or exporting
  captured audio.
- A Catalyst wrapper or a pixel-for-pixel copy of the Mac window.
- Accounts, cloud sync, subscriptions or changes to the learning curriculum.
- Rewriting the DSP in another language or adopting a cross-platform UI
  framework.

## Product and technical constraints

| ID | Constraint | Status | Strength | Source | Rationale / evidence |
| --- | --- | --- | --- | --- | --- |
| C-01 | The built-in iPhone/iPad microphone is the primary input. | Accepted | Hard | User | Most intended players will not connect an interface. |
| C-02 | Do not expose iOS input/output device selection. | Accepted | Hard | User scope | iOS manages the route, and interface-oriented UI would optimize for the minority case. |
| C-03 | Do not live-monitor microphone input on iOS. | Inferred | Hard | Acoustic constraint | Speaker playback would be recaptured as echo or feedback and would contaminate detection. |
| C-04 | Keep lesson/sample playback. | Inferred | Hard | Existing product | Audible examples are part of the learning modules and the bundled sample library already exists. |
| C-05 | Gate detection across app-owned playback and a measured decay tail. | Inferred | Hard | Acoustic constraint; gate design proposed by open workstream 007 | The nearby microphone can hear the app's speaker and must not credit it as the player. Workstream 007 is still open and its decay tail is **not** measured, so 009 must measure gate duration and speaker decay on representative iOS hardware in Phase 7 rather than inherit a constant or cite 007 as a completed finding. |
| C-06 | Preserve a single shared theory, DSP and module implementation. | Inferred | Hard | Repository architecture | Forked product logic would drift and double the test burden. |
| C-07 | Preserve the Mac app's current audio and release behavior. | Inferred | Hard | Existing users | The port must not simplify macOS by deleting features it needs. |
| C-08 | iPhone layouts must reflow; they may not rely on the Mac's 950 x 800 minimum. | Inferred | Hard | Current measured window floor | Shrinking the desktop layout would make the board, labels and controls illegible. |
| C-09 | The 22-fret board remains legible and touchable on iPhone. | Inferred | Hard | Core interaction | Fitting the full board to portrait width would violate useful text and touch sizes. |
| C-10 | Audio-rate observation remains isolated to leaf views. | Inferred | Hard | Measured Mac regression history | A platform port must not reintroduce whole-screen invalidation at roughly 30 updates per second. |
| C-11 | Hardware audio is excluded from the default unit-test suite on both platforms; the iOS test host must never activate real audio by default. | Inferred | Hard | `CLAUDE.md` test guidance; repository readiness audit (2026-09-18) | Headless tests cannot answer microphone prompts, parallel test hosts contend for audio hardware, and an iOS test host that builds a real `AVAudioSession` can fail or hang with nobody to answer. Inject fakes; gate any hardware test behind an explicit environment variable. This policy is **inferred** from existing repository guidance and the readiness audit; the user did not explicitly accept it. |
| C-12 | The app initially runs only while foreground-active. | Proposed | Soft | Scope control | Background capture adds entitlement, lifecycle, privacy and battery work without serving the primary practice flow. |
| C-13 | iOS uses the same dark visual language, pitch colors and component vocabulary as macOS. | Inferred | Soft | Existing product | Platform-native structure should not turn into a separate brand. |
| C-14 | Acoustic guitar and an amplified electric guitar are the supported real-world sources; unplugged solid-body electric is not promised. | Proposed | Soft | Microphone physics | The device microphone needs meaningful acoustic energy, and the UI should not imply otherwise. |
| C-15 | Keep iOS and macOS in this repository and this Xcode project, with separate native app/test targets and schemes. | Accepted | Hard | User | Shared product code needs one source of truth, while platform shells need independent build boundaries. |
| C-16 | Migrate files incrementally; do not begin with a repository-wide folder move. | Accepted | Hard | User | A large mechanical diff would hide architectural mistakes and make Mac regressions harder to isolate. |
| C-17 | Keep each platform's bundle settings, assets, entitlements, versioning and release workflow independent. | Accepted | Hard | User | A shared repository must not couple shipping or signing decisions. |
| C-18 | Do not extract a local Swift package at the start of the port. Reconsider it only after the shared boundary compiles cleanly for both apps. | Accepted | Soft | User | Packaging mixed platform code prematurely would add ceremony before the real seam is known. |
| C-19 | Scope protection for the Mac app: Mac-only files, user-visible behavior, UI, audio routing/monitoring, configuration, assets, signing, release tooling and platform-owned source are immutable for Workstream 009. Minimal, behavior-preserving changes to genuinely shared source and the common `Fretlight.xcodeproj` are allowed only when required for iOS/iPadOS, with explicit classification and Mac regression verification. | Accepted | Hard | User (2026-09-18, confirmed option A) | The user's instruction is "don't edit anything to do with the Mac app when developing the iOS and iPad apps." The owner confirmed option **(A)** ("ok lets go") after discussing the exact recommended wording. Shared edits must be minimal and behavior-preserving, classified explicitly as shared, and separately verified against the Mac app. Option (B) — every file or project compiled or used by the Mac target immutable, forcing a separate or copied source architecture — was not adopted, so C-06 and C-15 remain satisfied. |
| C-20 | Minimum deployment target is iOS/iPadOS 26.0 for both iPhone and iPad. | Accepted | Hard | User (2026-09-18) | Owner decision. iOS 26 is the supported baseline; it bounds available SwiftUI/Observation APIs, Simulator versions and test-device coverage. See the Apple compatibility lists in References. |
| C-21 | The iOS bundle identifier is `org.fretwork.app.ios`, backed by ownership of `fretwork.org`. | Accepted | Hard | User (2026-09-18) | Owner decision. The reverse-DNS prefix is controlled by the owner, and App Store Connect treats a bundle ID as immutable after the first build upload, so it is fixed now rather than before Phase 8. See the App Store Connect reference in References. |
| C-22 | The release goal is a public App Store listing for both iPhone and iPad. | Accepted | Hard | User (2026-09-18) | Owner decision. TestFlight/internal-only is not the target. Apple Developer Program enrollment is still pending (see Blockers), which defers distribution signing but not architecture or Simulator work; if the configured Development Team cannot provision, enrollment blocks Phase 1. |
| C-23 | Provisioning is split by stage: development-level automatic signing/provisioning, device trust and Developer Mode are prerequisites for installing on physical devices in Phase 1; App Store Connect setup and distribution signing are deferred to Phase 8. Pending enrollment must not block architecture or Simulator work. | Inferred | Hard | Apple platform requirements; user enrollment status (2026-09-18) | Target scaffolding, the shared audio seam and Simulator validation do not require a provisioning profile. If the configured Development Team cannot provision a physical device, Apple Developer Program enrollment blocks Phase 1 rather than Phase 8. The App Store Connect app record and distribution signing remain Phase 8 owner actions. The sequencing is a technical consequence of the accepted public-release goal, not a separately accepted user constraint. |
| C-24 | Use the available iPhone 14 Pro Max and iPad Pro 13-inch (M5) as the physical devices for Phase 1 capture testing and Phase 7 real-guitar validation. | Accepted | Hard | User (2026-09-18) | These are the owner-nominated devices. Record their installed OS versions, Developer Mode/device-trust state and measurement conditions when testing begins. The large iPad does not cover compact-iPad layout behavior, so retain Simulator coverage for the iPad mini/iPad reference sizes. |

## Verified findings driving this workstream

1. **The portable center already exists.** `Pitch/` and `Theory/` are pure
   Swift/Foundation/Accelerate code. The module rules are model-first and
   tested independently of rendered views. Those implementations should be
   compiled into both products, not copied into an iOS tree.
2. **The current hard platform dependency is concentrated but reaches into
   `AppState`.** `AudioEngine`, `AudioDevice`, `AudioDeviceWatcher` and the Mac
   settings UI use Core Audio HAL types. `AppState` directly stores
   `AudioDeviceID`, enumerates devices and owns a concrete `AudioEngine`, so
   adding an iOS target before introducing a platform-neutral seam will spread
   `#if os(...)` through the main state owner.
3. **The Mac engine solves problems this iOS product does not have.** It binds
   arbitrary devices, chooses duplex versus split graphs, controls device
   buffer sizes and corrects drift between clocks. None belongs in the iOS
   implementation when the system-managed microphone is the capture source.
4. **Not every AVAudioEngine capture technique behaves the same on every
   platform.** The Mac uses `AVAudioSinkNode` because `installTap` returned
   unexpectedly large chunks in measured Mac testing. Do not assume the same
   result on iOS. Measure sink-node and tap behavior on physical devices before
   choosing; detector latency and buffer cadence, not API symmetry, decide.
5. **The UI is SwiftUI but not presently responsive.** `FretworkApp` declares
   a 950 x 800 window floor, `AppShell` uses a persistent
   `NavigationSplitView`, settings are a fixed-width popover, and several
   screens assume wide horizontal rows. iPad can retain much of the hierarchy;
   iPhone cannot.
6. **The board must not be uniformly miniaturized.** A 22-fret, six-string
   board with readable labels cannot fit usefully across a portrait iPhone.
   Horizontal scrolling is the default compact-width direction; a deliberate
   jump-to-live-position action may be added after prototype testing, but
   automatic scrolling must not fight the player's touch.
7. **Sample playback and microphone capture coexist.** The iOS audio session
   must permit both, but the graph must have no microphone-to-output connection.
   Analysis is muted logically while Fretwork plays a sample and resumes after
   a decay tail that 009 must measure on real device speakers in Phase 7. The
   gate design in the still-open workstream 007 is a reference, not a measured
   constant (C-05).
8. **The current test investment is an advantage.** Pure theory, DSP, board,
   persistence and module tests should run against shared code on both
   platforms where practical. Mac-only device and window tests remain Mac-only;
   iOS adds its own shell, permission and responsive-layout coverage.
9. **Repository readiness (audit, 2026-09-18).** The Mac app target builds, but
   the default test suite compile-fails before running (0/453 tests) because
   `FretlightTests/FretboardBoardViewTests.swift:17-18` passes `.standard` /
   `.dropD` where the parameter type is `Tuning`, which has no such members; the
   intended spellings are `Tunings.standard` / `Tunings.dropD`. This is
   pre-existing and unrelated to 009. Record it as a Phase 0 baseline blocker and
   repair it in a separate, non-iOS change before the shared-code implementation
   baseline (Phase 2); do not edit that test as part of the iOS diff.
10. **Enrollment and hardware state (2026-09-18).** A local Development Team is
    configured, but Apple Developer Program enrollment, a provisioning profile
    and a device workflow are unconfirmed. The nominated physical devices are an
    **iPhone 14 Pro Max** and an **iPad Pro 13-inch (M5)** (C-24); their installed
    OS versions, Developer Mode and trust state remain unconfirmed. None of this
    blocks Phase 0, which is Simulator-only. Phase 1 physical installs do require development-level
    automatic signing/provisioning, a trusted device and Developer Mode; if the
    configured team cannot provision, Program enrollment blocks Phase 1. The
    App Store Connect record and distribution signing stay deferred to Phase 8
    (C-23).
11. **Platform and identity are decided.** Minimum iOS/iPadOS 26.0, bundle ID
    `org.fretwork.app.ios` (backed by ownership of `fretwork.org`), and a public
    App Store release for both iPhone and iPad. The public subtitle remains open
    (Q-05).

## Selected direction: shared core, native platform shells

Keep one Xcode project with distinct macOS and iOS app targets. Compile the
portable product code into both. Put platform lifecycle, audio-session setup,
navigation chrome and platform-only settings behind explicit boundaries.

The intended dependency direction is:

```text
                    Shared product code
          theory · DSP · modules · state documents
               fretboard · reusable SwiftUI leaves
                         /             \
                        /               \
             macOS shell                 iOS shell
       HAL devices · monitoring     AVAudioSession · permissions
       Sparkle · window commands    compact navigation · lifecycle
```

Prefer a small protocol or event surface between `AppState` and platform audio
controllers over scattered platform conditionals. Platform-specific entry
points, controllers and views may use `#if os(...)`; theory, module rules and
detectors may not.

### Repository and target structure

Use the existing repository and `Fretlight.xcodeproj`. Keep the current
`Fretlight` macOS target intact, then add:

- `Fretwork-iOS`, a native universal iPhone/iPad application target whose
  installed product name is `Fretwork`, deploying to iOS/iPadOS 26.0 and above
  (C-20) with bundle identifier `org.fretwork.app.ios` (C-21);
- `Fretwork-iOSTests`, containing iOS shell, lifecycle and responsive-layout
  coverage, with a test host that activates no real audio by default (C-11);
- a distinct shared scheme for each application target.

Do not turn the existing Mac target into one multiplatform target. Shared files
belong to both target memberships; platform files belong to exactly one. The
intended eventual source shape is:

```text
Fretlight/
  Shared/
    Theory/
    Pitch/
    Models/
    Fretboard/
    LearningModules/
  macOS/
    Audio/
    Views/
    FretworkMacApp.swift
  iOS/
    Audio/
    Views/
    FretworkIOSApp.swift
  Resources/
    Shared/
    macOS/
    iOS/

FretlightTests/
FretworkIOSTests/

Config/
  Shared.xcconfig
  macOS.xcconfig
  iOS.xcconfig
  FretworkMac.entitlements
  FretworkIOS.entitlements
```

This is a destination, not a Phase 0 file-moving task. Start by assigning the
existing files to a platform classification and creating only the new iOS
files. Move an existing file when a phase has proved that file's boundary, and
keep moves separate from behavioral edits where practical so Git history and
review remain useful.

The two products use independent deployment targets, version/build numbers,
signing, assets and release dates. Shared repository and source ownership do not
imply one release train. The iOS bundle identifier is fixed at
`org.fretwork.app.ios` (C-21), backed by ownership of `fretwork.org`; the public
subtitle remains open (Q-05). Do not copy Mac signing, entitlements or Sparkle
settings into the iOS target as a shortcut.

This same-project/shared-core direction is now confirmed by C-19/Q-06 option
(A). Any shared or common-project edit must be minimal, behavior-preserving,
classified as shared and separately verified against the Mac app; Mac-only
files, behavior, UI, audio routing/monitoring, configuration, assets, signing,
release tooling and platform-owned source stay immutable. The separate or copied
source tree that option (B) would have required does not apply.

### Shared audio surface

`AppState` should depend on the smallest platform-neutral audio-controller
surface that its behavior requires: lifecycle, sensitivity, note/chord/level
events, status and errors, sample preparation/playback and detection gating.
Provide three implementations:

- the existing HAL-aware Mac engine behind a macOS adapter;
- an `AVAudioSession`-backed iOS controller with no live-monitor path;
- a deterministic fake for unit tests and SwiftUI previews.

Derive the actual protocol from current call sites in Phase 2. Do not adopt a
speculative broad abstraction, and do not leak `AudioDeviceID` or iOS session
types through it.

### Package boundary

Do not make a `FretworkCore` Swift package a prerequisite for the port.
`AppState`, resource loading and some models currently mix product and platform
responsibilities, so an early package would encode guesses as module rules.
After Phase 6, reassess whether `Theory`, `Pitch`, module-rule models, board
geometry and shared state documents form a clean package. Extract them only if
the result enforces an already-proven boundary and simplifies target membership.

### Alternatives considered

**Catalyst:** rejected. It would preserve desktop assumptions and still require
audio and compact-layout work, while producing an interface that feels like a
Mac window on a phone-sized product surface.

**A separate iOS repository or copied source tree:** rejected. Detection,
theory and ten learning modules would immediately acquire two sources of truth.

**One universal target full of conditional compilation:** rejected as the
primary structure. Small platform guards are fine at entry points, but
conditional branches throughout `AppState`, every settings row and the audio
engine would make both platforms harder to reason about and test.

**An immediate `FretworkCore` package extraction:** deferred. It may become the
right long-term boundary, but doing it before the platform seam is proven would
mix the port with a repository-wide module and resource migration.

## Open questions

| ID | Question | Why it matters | Owner | Resolution |
| --- | --- | --- | --- | --- |
| Q-01 | What is the minimum supported iOS/iPadOS version? | Controls Observation/SwiftUI API availability and test-device coverage. | User | **Resolved 2026-09-18:** iOS/iPadOS 26.0 and above (C-20). |
| Q-02 | Is portrait iPhone a first-class practice orientation or merely supported? | Determines how much board and control redesign is necessary. | User | Prototype the smallest supported iPhone in portrait and landscape in Phase 4; both must function, but human review chooses the preferred presentation. |
| Q-03 | Should unplugged solid-body electric guitar receive explicit UI guidance? | Avoids promising reliable detection from a source the microphone may barely hear. | User | **Resolved 2026-10-01 — no guidance now.** Unplugged electric in a quiet room was reliable for the owner (all strings detected, 6 cents median), lower three strings needing firmer picking. Failure is not common, so the Phase 7 rule says no UI. Its notes (−56 dB) sit at the level of TV-room phantoms (−54 dB), so revisit together with the room-noise finding if noisy-room use is reported. |
| Q-04 | Should iOS practice state sync with the Mac? | Would introduce an iCloud/container migration beyond a local port. | User | Default to local-only for this workstream; promote to a later workstream if requested. |
| Q-05 | What public App Store subtitle should be used? | Needed for the App Store listing, not for the architecture spike or any implementation phase. | User | Subtitle remains deferred; owner decides before Phase 8 archive/submission work. The bundle identifier is a separate question, already resolved (C-21). |
| Q-06 | May iOS development make minimal, behavior-preserving edits to genuinely shared source and the common `Fretlight.xcodeproj`, or is every file compiled or used by the Mac target immutable? | Decides whether the selected C-15 shared project is viable, and whether Phase 0 may mutate the common project at all. Option B forces separate or copied sources and conflicts with C-06. | User | **Resolved 2026-09-18 — option (A)** (C-19). Mac-only files, behavior, UI, audio routing/monitoring, configuration, assets, signing, release tooling and platform-owned source are immutable; minimal, behavior-preserving shared-source and common-project edits are allowed only when required for iOS/iPadOS, with explicit classification and Mac regression verification. Option (B) is rejected. |
| Q-07 | Which exact iPhone and iPad, with Developer Mode, will be connected for the Phase 1 physical spike, and when? | Phase 1 needs real-device capture, latency and decay measurements. | User | **Partially resolved 2026-09-18:** use the available iPhone 14 Pro Max and iPad Pro 13-inch (M5) (C-24). Record each installed OS version and confirm connection, trust and Developer Mode when Phase 1 begins. Phase 0 uses the Simulator only. |

## Blockers and owner actions

| Item | Type | Blocks | Owner | Status / next action |
| --- | --- | --- | --- | --- |
| Default Mac test suite compile-fails before running (0/453): `FretlightTests/FretboardBoardViewTests.swift:17-18` passes `.standard` / `.dropD` where `Tuning` has no such members (`Tunings.standard` / `Tunings.dropD` are intended). | Pre-existing blocker | The green Mac implementation baseline before Phase 2; not Phase 0 scaffolding. | Maintainer | Repair as a separate, non-iOS change before shared-code implementation. Do not fold into the iOS diff and do not edit the test in Phase 0. |
| Development-level automatic signing/provisioning, device trust and Developer Mode unconfirmed. | Owner action | Physical installs in Phase 1. If the configured Development Team cannot provision, Apple Developer Program enrollment blocks Phase 1. | User | Confirm the configured team can provision a physical device, trust it and enable Developer Mode before Phase 1; otherwise begin Program enrollment before Phase 1. |
| App Store Connect app record and distribution signing unconfirmed. | Deferred owner action | TestFlight and App Store upload (Phase 8). | User | Defer; must not block Phases 0–7 or architecture and Simulator work. |
| iPhone 14 Pro Max and iPad Pro 13-inch (M5) nominated, but installed OS versions, connection/trust and Developer Mode are unconfirmed. | Owner action | Physical capture spike (Phase 1) and real-guitar validation (Phase 7). | User | Connect both devices when Phase 1 starts; record OS versions and confirm trust and Developer Mode in the Implementation Record. |
| Public App Store subtitle undecided (Q-05). | Deferred decision | App Store listing only. | User | Decide before Phase 8 archive/submission work. |

## Execution contract

1. Work in phase order. Phase 1 is a measured spike; do not build the complete
   iOS engine before its capture primitive is selected.
2. Keep the Mac target buildable after every phase. The pre-existing Mac test
   compile failure recorded in Blockers is a **recorded exception** until it is
   repaired as its own non-iOS change; after that repair, both platforms'
   suites must be green after every phase. Phases 0 and 1 do not and cannot
   claim a green Mac suite before the repair.
3. Do not overwrite the existing Mac `AudioEngine` with a lowest-common-
   denominator implementation. Extract a shared interface and keep its proven
   HAL behavior behind the Mac adapter.
4. Do not connect the iOS microphone graph to an output mixer. Sample playback
   gets an output path; captured live input does not.
5. No default automated test may request microphone permission or touch real
   audio hardware. Inject a fake platform audio controller at the state seam.
6. Use physical iPhone/iPad measurements for capture cadence, detection latency,
   decay-tail duration and CPU. The Simulator is only a layout/build surface.
7. After every phase: build both applicable targets, run their unit tests and
   run `git diff --check`. After audio or high-frequency UI changes, perform
   the relevant physical-device smoke test too.
8. Preserve Swift 6 strict concurrency. Do not silence sendability failures
   with blanket `@unchecked Sendable` without a documented ownership proof.
9. Append commands, devices, measurements, failures and decisions to the
   Implementation Record. Another agent must not have to reconstruct them from
   chat history.
10. Keep target configuration explicit. An iOS target must never inherit
    Sparkle, Mac entitlements, HAL frameworks or Mac release scripts merely
    because both products live in one project.
11. Do not front-load the desired folder structure. Move source only when the
    active phase has proved whether it is shared or platform-owned.
12. The iOS test host must never activate real audio by default. Construct the
    iOS audio controller behind injected session/lifecycle seams and use a fake
    in tests; only an explicitly environment-gated physical-device test may
    touch `AVAudioSession` or the microphone.
13. Under C-19/Q-06 option (A), Mac-only source, behavior, UI, audio
    routing/monitoring, configuration, assets, signing, release tooling and
    platform-owned source are immutable. Keep any genuinely shared-source or
    common-project edit minimal and behavior-preserving, classify it explicitly
    as shared, and verify it separately against the Mac app before landing.
    Never reduce Mac capability to simplify iOS.
14. Do not wait on enrollment for architecture, target scaffolding, Simulator
    builds or unit tests; those proceed without a provisioning profile.
    Development-level automatic signing/provisioning, device trust and Developer
    Mode are required before Phase 1 installs on physical devices — if the
    configured team cannot provision, Program enrollment blocks Phase 1. The
    App Store Connect record and distribution signing stay deferred to Phase 8
    (C-23).
15. Do not claim a green Mac baseline until the pre-existing test compile
    failure recorded in Blockers is repaired as its own change.

## Phase 0 — Baseline, target contract and source inventory

**Prerequisite:** none outstanding. C-19/Q-06 is resolved (option A), so the
mutating tasks (task 4 onward) proceed under the boundary recorded in C-19. No
physical device or provisioning profile is needed for Phase 0.

**Status: complete (2026-09-18),** with one recorded exception: the pre-existing
Mac test compile failure (0/453) remains and must be repaired separately before
Phase 2. Phase 0 built and tested the scaffolding on the Simulator only, added
no existing production source to the iOS target and moved no files.

> **Phase 1 update (2026-09-19):** Phase 0's "iOS compiles only its isolated
> `FretworkIOS/` synchronized root" was accurate at Phase 0 completion. Phase 1
> subsequently added explicit `PBXFileReference`/`PBXBuildFile` membership for
> seven shared files (see Phase 1 inventory), without adding the full
> `Fretlight/` synchronized group or the 29-entry exception set. The
> `PBXFileSystemSynchronizedBuildFileExceptionSet` approach remains deferred
> to Phase 2.

### Tasks

1. **Done.** Working tree recorded and all pre-existing changes preserved; see
   the git-status snapshot below.
2. **Done.** The Mac app builds (`** BUILD SUCCEEDED **`) and launches clean.
   The default Mac suite still compile-fails before running (0/453) at
   `FretlightTests/FretboardBoardViewTests.swift:17-18`. Recorded as an
   exception; the test file was not edited. Repair is a separate non-iOS change
   before Phase 2.
3. **Done.** Settings recorded, not re-decided: iOS/iPadOS 26.0 (C-20), bundle
   ID `org.fretwork.app.ios` (C-21), app target `Fretwork-iOS`, test target
   `Fretwork-iOSTests`, scheme `Fretwork-iOS`, installed product name
   `Fretwork`. Subtitle Q-05 stays open.
4. **Done.** The minimal `Fretwork-iOS` / `Fretwork-iOSTests` targets and their
   shared schemes were added to `Fretlight.xcodeproj`. The iOS target compiles
   only its own `FretworkIOS/` synchronized root; there is no production
   navigation, no source move, and no existing production source in its
   membership. The Mac build was verified afterwards.
5. **Done.** The iOS targets have their own configuration, assets and generated
   `Info.plist`; the iOS product contains no Sparkle, no `SU*` keys, no Mac
   entitlements, no HAL frameworks and no audio activation. During Phase 0 the
   iOS module was renamed to `Fretwork` (removing the explicit
   `PRODUCT_MODULE_NAME`, so it defaults from `PRODUCT_NAME`) and
   `NSMicrophoneUsageDescription` was added to the iOS Debug/Release configs —
   both verified with `-showBuildSettings` and `PlistBuddy`.
6. **Done.** Every production Swift file classified: 68 shared, 10 macOS-only
   plus the Mac `Assets.xcassets` catalog, 18 requiring extraction; 96 Swift
   files total. Full inventory below.
7. **Done.** Test classification: 35 immediately portable, 3 portable after
   shared extraction, 14 macOS-only, plus the new iOS scaffold tests. Full
   inventory below.

### Exit criteria

- **Met.** The platform boundary, deployment target (26.0) and bundle identifier
  are explicit and recorded.
- **Met.** The minimal iOS target and test target build without Mac-only
  dependencies; the iOS test host activates no real audio (2/2 tests read pure
  values only).
- **Met.** No existing production code has moved; the iOS target has no existing
  production-source membership.
- **Met with recorded exception.** The Mac build is recorded and reproducible.
  The pre-existing test compile failure (0/453) is documented rather than
  hidden; its separate repair gates Phase 2.
- **Met.** Phase 0 needs no physical device and no provisioning profile. Its
  common-project entries are minimal and behavior-preserving, and the Mac build
  and launch are verified after them (C-19).

### Phase 0 source ownership inventory (complete)

96 Swift files under `Fretlight/` plus `Fretlight/Assets.xcassets/`. Count check:
68 shared + 10 macOS-only + 18 requires-extraction = 96. Classification is
backed by the iOS type-check evidence recorded below, not by reading alone.

**A. Shared — 68 files (iOS type-check clean today, under module `Fretwork`)**

- `Fretlight/Audio/` (13): `AudioAnalysisWorker.swift`, `CaptureSink.swift`,
  `ChordAnalysisWorker.swift`, `GuidedSession.swift`, `NoteSampleLibrary.swift`,
  `NoteSequencer.swift`, `RingBuffer.swift`, `SampleLibrary.swift`,
  `SamplePlayer.swift`, `SampleRecorder.swift` ¹, `SensitivitySettings.swift`,
  `TakeVerifier.swift`, `TuningSampleMap.swift`.
- `Fretlight/Models/` (20): `ChordDisplayState.swift`, `ChordHistoryEntry.swift`,
  `ChordsModuleModel.swift`, `CircleModuleModel.swift`, `GuidedPresentation.swift`,
  `HarmonizingModuleModel.swift`, `IntervalsModuleModel.swift`,
  `LearningModule.swift`, `NoteAssociationModuleModel.swift`,
  `NoteHistoryEntry.swift`, `NotesModuleModel.swift`, `OctavesModuleModel.swift`,
  `PentatonicModuleModel.swift`, `PitchDisplayState.swift`, `PracticeState.swift`,
  `PracticeStateStore.swift`, `RecallChallenge.swift`, `ScalesModuleModel.swift`,
  `TriadsModuleModel.swift`, `UsageTelemetry.swift`.
- `Fretlight/Pitch/` (6): `ChordDetector.swift`, `ChordShapeResolver.swift`,
  `FretPositionResolver.swift`, `GuitarTuning.swift`, `NoteMapper.swift`,
  `PitchDetector.swift`.
- `Fretlight/Theory/` (15): `ChordDiscovery.swift`, `Chords.swift`,
  `ChordVoicings.swift`, `Harmony.swift`, `Intervals.swift`, `IntervalShapes.swift`,
  `OctaveShapes.swift`, `PitchClass.swift`, `Positions.swift`, `Progressions.swift`,
  `Scales.swift`, `ScaleShapes.swift`, `TriadPaths.swift`, `TriadVoicings.swift`,
  `Tuning.swift`.
- `Fretlight/Views/` (14): `Fretboard/BoardCanvas.swift`,
  `Fretboard/BoardGeometry.swift`, `Fretboard/DotMotionModifier.swift`,
  `Fretboard/FretboardAccessibility.swift`, `Fretboard/FretboardBoardView.swift`,
  `Fretboard/FretboardDot.swift`, `Fretboard/FretboardHitTest.swift`,
  `Fretboard/FretboardNavigation.swift`, `Fretboard/FretboardOverlay.swift`,
  `HistoryStrip.swift`, `InputLevelPanel.swift`, `Modules/GlassControls.swift`,
  `NotePalette.swift`, `RulerSlider.swift`.

¹ `Fretlight/Audio/SampleRecorder.swift` is entirely `#if DEBUG`; its body is
empty in Release, but it must stay in the iOS target because
`Fretlight/Audio/SampleLibrary.swift:97,164` names `SampleRecorder.Take` inside
its own `#if DEBUG` block.

**B. macOS-only — 10 Swift files + `Fretlight/Assets.xcassets/` (never shared)**

- `Fretlight/FretlightApp.swift` — Sparkle `@main`, `.commands`, sample-capture
  `Window`.
- `Fretlight/Audio/AudioDevice.swift` — Core Audio HAL.
- `Fretlight/Audio/AudioDeviceWatcher.swift` — Core Audio HAL.
- `Fretlight/Audio/AudioEngine.swift` — AUHAL device binding, duplex/split
  graphs, drift.
- `Fretlight/Audio/MonitorRenderer.swift` — Mac direct-monitoring render path.
- `Fretlight/Models/SampleCaptureModel.swift` — DEBUG capture tool.
- `Fretlight/Views/CheckForUpdatesView.swift` — Sparkle UI.
- `Fretlight/Views/DevicePickerView.swift` — Core Audio device picker.
- `Fretlight/Views/SampleCaptureHost.swift` — DEBUG capture window.
- `Fretlight/Views/SampleCaptureView.swift` — DEBUG capture UI.
- `Fretlight/Assets.xcassets/` — must never join the iOS target: its icon set is
  `idiom: mac` only, and its compiled output is also named `Assets.car`, which
  would collide with the iOS catalog in one target.

**C. Requires extraction — 18 files (Mac-compiled today; shared after Phase 2)**

- `Fretlight/Models/AppState.swift` — imports `CoreAudio:3`, stores
  `AudioDeviceID:14-15`, owns `AudioEngine:213`, enumerates HAL at `:543-615`,
  declares `DetectionMode:5-8`.
- `Fretlight/Views/AppShell.swift`, `Fretlight/Views/GlobalSettingsView.swift`,
  `Fretlight/Views/ListenScreen.swift`, `Fretlight/Views/PitchReadoutView.swift`,
  `Fretlight/Views/FretboardView.swift`,
  `Fretlight/Views/Fretboard/DetectionBoardAdapter.swift`,
  `Fretlight/Views/Modules/ModuleLayout.swift`,
  `Fretlight/Views/Modules/ChordsModuleScreen.swift`,
  `Fretlight/Views/Modules/CircleModuleScreen.swift`,
  `Fretlight/Views/Modules/HarmonizingModuleScreen.swift`,
  `Fretlight/Views/Modules/IntervalsModuleScreen.swift`,
  `Fretlight/Views/Modules/NoteAssociationModuleScreen.swift`,
  `Fretlight/Views/Modules/NotesModuleScreen.swift`,
  `Fretlight/Views/Modules/OctavesModuleScreen.swift`,
  `Fretlight/Views/Modules/PentatonicModuleScreen.swift`,
  `Fretlight/Views/Modules/ScalesModuleScreen.swift`,
  `Fretlight/Views/Modules/TriadsModuleScreen.swift`.

Two extraction blockers were confirmed by the compiler, not by reading:

- `DetectionMode` is declared **inside `Fretlight/Models/AppState.swift:5-8`**, so
  `Fretlight/Views/Fretboard/DetectionBoardAdapter.swift:20`,
  `Fretlight/Views/FretboardView.swift:12` and
  `Fretlight/Views/PitchReadoutView.swift:10` cannot compile for iOS until it is
  extracted into its own shared file.
- Four module-qualified references — `Fretwork.Triads` / `Fretwork.Intervals` at
  `Fretlight/Models/PracticeState.swift:394,488` (a file otherwise classified
  shared) and `Fretlight/Models/TriadsModuleModel.swift:29,62` — require the iOS
  app module to be named **`Fretwork`**, not `FretworkIOS`.

**D. iOS-only / new**

- `FretworkIOS/FretworkIOSApp.swift` — `@main` iOS `App`.
- `FretworkIOS/IOSScaffoldView.swift` — Phase 0 placeholder + `IOSScaffoldPhase`.
- `FretworkIOS/Assets.xcassets/Contents.json`.
- `FretworkIOS/Assets.xcassets/AppIcon.appiconset/Contents.json`.
- `FretworkIOS/Assets.xcassets/AccentColor.colorset/Contents.json`.

**Proven iOS type-check evidence.** The 68 shared files (all `Fretlight/**`
except categories B and C) were type-checked against the installed iOS
Simulator SDK:

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)   # iPhoneSimulator27.0.sdk
swiftc -typecheck -module-name Fretwork -sdk "$SDK" \
  -target arm64-apple-ios26.0-simulator -swift-version 6 \
  -strict-concurrency=complete <68 shared files>
```

Result: exit 0, zero errors, zero warnings — both with and without `-D DEBUG`.
Re-running the identical command **without** `-module-name Fretwork` fails only
with `cannot find 'Fretwork' in scope` at `PracticeState.swift:394,488` (and the
same class of reference at `TriadsModuleModel.swift:29,62`). That is the
module-naming gate, not a code-portability problem: the shared set is portable
to iOS exactly when the iOS module is named `Fretwork`. That rename landed
during Phase 0 (`-showBuildSettings` now reports
`PRODUCT_MODULE_NAME = Fretwork`), so the precondition for Phase 2 shared
membership is met.

### Phase 0 test ownership inventory (complete)

52 macOS test files (453 test functions) + 1 iOS test file (2 test functions).
Count check: 35 immediately portable + 3 portable-after-extraction + 14
macOS-only = 52.

**A. Immediately portable — 35 files**

- `FretlightTests/`: `BoardGeometryTests.swift`, `ChordDetectorTests.swift`,
  `ChordDiscoveryTests.swift`, `ChordShapeResolverTests.swift`,
  `ChordsModuleTests.swift`, `ChordVoicingTests.swift`, `CircleModuleTests.swift`,
  `FretboardAccessibilityTests.swift`, `FretboardHitTestTests.swift`,
  `FretboardNavigationTests.swift`, `FretboardOverlayTests.swift`,
  `FretPositionResolverTests.swift`, `GuidedSessionTests.swift`,
  `HarmonizingModuleTests.swift`, `HarmonyTests.swift`, `IntervalsModuleTests.swift`,
  `LearningModuleTests.swift`, `NoteAssociationModuleTests.swift`,
  `NoteMapperTests.swift`, `NotePaletteTests.swift`, `NoteSequencerTests.swift`,
  `NotesModuleTests.swift`, `OctavesModuleTests.swift`, `PentatonicModuleTests.swift`,
  `PitchDetectorTests.swift`, `PracticeStateTests.swift`, `SampleLibraryTests.swift`,
  `ScaleShapeTests.swift`, `ScalesModuleTests.swift`, `TakeVerifierTests.swift`,
  `TheoryTests.swift`, `TriadsModuleTests.swift`, `TuningSampleMapTests.swift`,
  `TuningTests.swift`, `UsageTelemetryTests.swift`.

Note: `LearningModuleTests` and `NotePaletteTests` gate a live web-repo
comparison behind `FRETWORK_WEB_REPO` (mirrored literals otherwise); they stay
skipped headlessly on both platforms.

**B. Portable but blocked on shared extraction — 3 files**

- `FretlightTests/DetectionBoardAdapterTests.swift` — needs `DetectionMode`
  extracted out of `AppState.swift:5-8`.
- `FretlightTests/ChordHistoryTests.swift` — calls
  `AppState.appending(_:to:limit:)` (declared `AppState.swift:661`).
- `FretlightTests/NoteHistoryTests.swift` — calls
  `AppState.appending(_:positions:to:limit:)` (declared `AppState.swift:831`).

**C. macOS-only — 14 files**

- `FretlightTests/AppShellNavigationTests.swift` — `AppState` + `AudioEngine` +
  navigation.
- `FretlightTests/AudioEngineWatchdogTests.swift` — env-gated hardware
  (`TEST_RUNNER_FRETWORK_AUDIO_DEVICE_TESTS=1`).
- `FretlightTests/DefaultDeviceTests.swift` — Core Audio.
- `FretlightTests/DetectionBoardSnapshotTests.swift` — `NSHostingView:41`,
  `cacheDisplay`.
- `FretlightTests/EndToEndPlaybackTests.swift` — env-gated hardware.
- `FretlightTests/FretboardBoardViewTests.swift` — `NSHostingView:25`; also the
  known typo blocker (`:17-18`).
- `FretlightTests/GlobalSettingsTests.swift` — `AppState` device persistence.
- `FretlightTests/MonitorLevelTests.swift` — Mac monitor mixer semantics
  (`AVAudioUnitEQ`).
- `FretlightTests/SampleCaptureModelTests.swift` — `NSHostingView:267` + capture
  tool.
- `FretlightTests/SamplePlaybackWiringTests.swift` — `AppState` + `AudioEngine`.
- `FretlightTests/SamplePlayerTests.swift` — Mac graph manual-rendering harness.
- `FretlightTests/SampleRecorderTests.swift` — DEBUG capture.
- `FretlightTests/WindowSizeTests.swift` — `NSHostingView` window-floor
  measurement.
- `FretlightTests/PluckPipelineDiagnostic.swift` — capture diagnostic.

**D. New iOS coverage — 1 file (2 tests)**

- `FretworkIOSTests/FretworkIOSScaffoldTests.swift` — `testScaffoldModuleIsLinked`
  asserts `IOSScaffoldPhase.identifier == "workstream-009-phase-0"`, and
  `testHostedAppMinimumOSIs26` reads `MinimumOSVersion` from `Bundle.main` and
  asserts `"26.0"`, proving the built iOS bundle targets iOS 26 rather than
  trusting a literal. No rendering and no `AVAudioSession`, satisfying C-11 for
  Phase 0.

**E. Test-suite blockers**

1. `FretlightTests/FretboardBoardViewTests.swift:17-18` — Mac suite 0/453.
   **Repair separately, not in this diff.**
2. ~~`PRODUCT_MODULE_NAME = FretworkIOS`~~ — **resolved during Phase 0:** the
   module now resolves to `Fretwork`, satisfying the four `Fretwork.`-qualified
   shared references. Kept here for history.
3. ~~Missing `NSMicrophoneUsageDescription`~~ — **resolved during Phase 0:** the
   iOS `Info.plist` now carries the key; it remains a hard requirement for the
   Phase 1 physical microphone spike.
4. No shared-file membership / exception set exists yet
   (`grep -c PBXFileSystemSynchronizedBuildFileExceptionSet project.pbxproj` = 0).

### Phase 0 architectural choice (recorded)

The iOS target used **only its isolated `FretworkIOS/` filesystem-synchronized
root** at Phase 0 completion. Its `fileSystemSynchronizedGroups` listed only
`B100000000000000000000A9 /* FretworkIOS */` (`project.pbxproj:188-190`). No
existing production source (`Fretlight/**`) was a member of the iOS target, no
production file moved, and
`grep -c PBXFileSystemSynchronizedBuildFileExceptionSet project.pbxproj` = 0.

Phase 1 (2026-09-19) added explicit `PBXFileReference`/`PBXBuildFile` entries
for seven shared files (see Phase 1 inventory); the full `Fretlight/`
synchronized group plus 29-entry exception set remains deferred to Phase 2.

The shared-root membership plus the 29-entry iOS exception set that the `/tmp`
prototype validated is **deliberately not applied in Phase 0**. It is deferred
to Phase 2, together with the actual shared seam:

1. Phase 0's exit criteria are already met by the isolated scaffold, so pulling
   all 68 shared files into the iOS target now would enlarge the diff without a
   Phase 0 requirement. C-19 asks for minimal, behavior-preserving changes.
2. Admitting `Fretlight/**` to iOS only becomes meaningful once the shared audio
   seam exists (Phase 2), because the extraction set includes `AppState` and the
   module screens. Until then, the exception set would add 29 exclusions to
   compile a set the app does not yet use.

The module-name precondition is already satisfied: `PRODUCT_MODULE_NAME` now
resolves to `Fretwork` (evidence above), so Phase 2 can add
`A00000000000000000000004 /* Fretlight */` and the target-filtered exception
set directly.

Kept for Phase 2: add `A00000000000000000000004 /* Fretlight */` to the iOS
target's synchronized groups, attach a
`PBXFileSystemSynchronizedBuildFileExceptionSet` filtered by
`target = B100000000000000000000A1`, and exclude exactly the 10 macOS-only files,
the 18 requires-extraction files and `Assets.xcassets` (29 entries). Exception
entries are paths relative to the group and are filtered per target, so the Mac
target's membership stays byte-for-byte identical. `SampleRecorder.swift` stays
**in** (DEBUG-only body); the Mac `Assets.xcassets` stays **out** (avoid a second
`Assets.car`); `FretlightApp.swift` must always be excluded (duplicate `@main`).
Note that the eventual `Fretlight/iOS/` destination cannot be a nested sync root
inside `Fretlight/`, which is why new iOS files live in the top-level
`FretworkIOS/` group today.

### Phase 0 files created / edited

Created by the Phase 0 session (kept; reviewed, not recreated):

- `FretworkIOS/FretworkIOSApp.swift`
- `FretworkIOS/IOSScaffoldView.swift`
- `FretworkIOS/Assets.xcassets/Contents.json`
- `FretworkIOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `FretworkIOS/Assets.xcassets/AccentColor.colorset/Contents.json`
- `FretworkIOSTests/FretworkIOSScaffoldTests.swift`
- `Fretlight.xcodeproj/xcshareddata/xcschemes/Fretlight.xcscheme`
- `Fretlight.xcodeproj/xcshareddata/xcschemes/Fretwork-iOS.xcscheme`

Edited:

- `Fretlight.xcodeproj/project.pbxproj` — added targets `Fretwork-iOS`
  (`B100000000000000000000A1`) and `Fretwork-iOSTests`
  (`B100000000000000000000B1`), product refs `B…A2` / `B…B2`, the two
  synchronized root groups `B…A9` / `B…B8`, the build phases, and the iOS
  Debug/Release configurations (`B…A7`/`B…A8`, `B…B6`/`B…B7`) plus the iOS
  `Fretwork` module name and `NSMicrophoneUsageDescription`. Current diff for
  this file: **237 insertions, 5 deletions**, including the pre-existing user
  edits below.

Explicitly **not** touched: any `Fretlight/**` production source,
`Config/Info.plist`, `scripts/**`, `.github/workflows/**`, `Frameworks/**`, and
`FretlightTests/**` (especially `FretboardBoardViewTests.swift:17-18`).

### Phase 0 git-status snapshot (2026-09-18, at Phase 0 completion)

```
 M Fretlight.xcodeproj/project.pbxproj
 M docs/workstreams/README.md
?? Fretlight.xcodeproj/xcshareddata/
?? FretworkIOS/
?? FretworkIOSTests/
?? docs/workstreams/active/008-live-note-chip-feedback.md
?? docs/workstreams/active/009-built-in-microphone-ios-app.md
```

Pre-existing user changes, present before the WS9 target scaffolding and
preserved untouched (do not fold into the iOS diff):

- `Fretlight.xcodeproj/project.pbxproj` — Mac product ref renamed
  `Fretlight.app` → `Fretwork.app`; `DEVELOPMENT_TEAM = 2752L3B5JB` (was `""`)
  on the Mac Debug/Release configs.
- `docs/workstreams/README.md` — 006/008/009 table edit.

Phase 0-owned additions: the `Fretwork-iOS`/`Fretwork-iOSTests` sections of
`project.pbxproj`, `Fretlight.xcodeproj/xcshareddata/**`, `FretworkIOS/**`,
`FretworkIOSTests/**`, and this workstream document.

The Mac test typo in `FretlightTests/FretboardBoardViewTests.swift:17-18` is
**committed and tracked**, not a working-tree change; it is listed here because it
is the recorded exception.

### Phase 0 verification commands and results (2026-09-18)

Toolchain: Xcode 27.0 (27A266a), SDK `iphonesimulator27.0`; only installed iOS
runtime is 26.5. Simulator used for the iOS build/test: **iPhone 17 Pro**
(`2D89BEAB-E0BF-4982-9F96-17B4E8199F64`), booted by the test run with `OS=26.5`.
**iPad Pro 13-inch (M5)** (`57C59EFB-CBE5-49E7-B1DB-9A573ADFF9DF`) was also
booted but not exercised in Phase 0.

| Command | Result |
| --- | --- |
| `xcodebuild -project Fretlight.xcodeproj -list` | Targets `Fretlight`, `FretlightTests`, `Fretwork-iOS`, `Fretwork-iOSTests`; schemes `Fretlight`, `Fretwork-iOS`. |
| `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **`. |
| `xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test` | `** TEST FAILED **` — compile error only, **0/453 run**, `FretboardBoardViewTests.swift:17:58` (`Tuning` has no member `standard`) and `:18:58` (`dropD`). Recorded exception. |
| `xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build` | `** BUILD SUCCEEDED **`. |
| `xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test` | `** TEST SUCCEEDED **`, 2 tests, 0 failures. |
| `swiftc -typecheck -module-name Fretwork ... <68 shared files>` | exit 0, clean with and without `-D DEBUG`. |
| `git diff --check` | clean (exit 0). |

Product inspection — iOS
`.../Build/Products/Debug-iphonesimulator/Fretwork.app`:

- `find "$APP" -iname '*sparkle*'` → empty.
- `otool -L "$APP/Fretwork.debug.dylib" | grep -i sparkle` → empty (exit 1).
- `*.m4a` count = **0**; no `index.json`. The bundled note library is **not** in
  the iOS product yet, because shared membership is deferred to Phase 2.
- `Assets.car` present — the iOS catalog only.
- `PlistBuddy`: `CFBundleIdentifier = org.fretwork.app.ios`,
  `MinimumOSVersion = 26.0`,
  `NSMicrophoneUsageDescription = "Fretwork listens to your guitar input to
  identify notes."`; `SUFeedURL` does **not** exist.
- No Mac entitlements, no HAL/`AVFoundation` explicit build files, no Embedded
  Frameworks phase (the iOS Frameworks phase is empty), and no audio activation:
  the scaffold imports SwiftUI only and the tests assert pure values.

Product inspection — Mac
`.../Build/Products/Debug/Fretwork.app` (unchanged):

- `Sparkle.framework` present.
- 138 `.m4a` files + `index.json` present.
- `Assets.car` present.
- `CFBundleIdentifier = org.fretwork.app`;
  `NSMicrophoneUsageDescription = "Fretwork listens to your guitar input to
  identify notes."`

Launch smoke (Mac): launched
`.../Debug/Fretwork.app/Contents/MacOS/Fretwork` in the background (pid 8112);
`ps` at 3s showed 2.3% CPU and at 7s 2.7% CPU (flat, not climbing); stdout/stderr
contained no `-10877`, `kAudioUnitErr_*` or Core Audio errors; process killed
with `pkill -9`. No runtime regression observed.

Deliberate choices and omissions, not defects:

- **The iOS `DEVELOPMENT_TEAM` is intentionally omitted.** iOS configs set
  `CODE_SIGN_STYLE = Automatic` with no team, so Simulator builds sign ad-hoc and
  pass without a provisioning profile. Adding a team and enabling physical
  installs is a Phase 1 provisioning action (C-23), not Phase 0 work; do not copy
  the Mac team into iOS as a shortcut.
- **The iOS app icon is the placeholder.** `AppIcon.appiconset/Contents.json`
  has one universal 1024×1024 entry with no image file, so the built app uses the
  default placeholder. Final icons are Phase 8 (Q-05/C-22 work).
- **`NSMicrophoneUsageDescription` is present.** The concurrent Phase 0 fix
  landed during the Phase 0 session: the iOS `Info.plist` now contains
  `"Fretwork listens to your guitar input to identify notes."` (verified with
  `PlistBuddy`). The scaffold still requests no microphone permission at
  runtime, so C-11 is unaffected.

### Phase 0 risks carried forward

1. **Duplicate `@main`.** `Fretlight/FretlightApp.swift:4` and
   `FretworkIOS/FretworkIOSApp.swift:16` both declare `@main`. If `Fretlight` is
   added to the iOS target without excluding `FretlightApp.swift`, the iOS link
   fails. The Phase 2 exception set must always include it.
2. **Synchronized-group inclusion.** `project.pbxproj:58` is a
   `PBXFileSystemSynchronizedRootGroup` whose membership is per target. Adding
   it to iOS without the exception set compiles all 96 files into iOS: the
   CoreAudio/HAL/Sparkle files fail, and exclusion is all-or-nothing per file, so
   any missed transitive dependency (e.g. `DetectionMode`) fails the build. The
   validated mitigation is one shared root plus a target-filtered
   `PBXFileSystemSynchronizedBuildFileExceptionSet` (29 entries), which leaves
   the Mac membership untouched — proven in the `/tmp/fw-phase0` copy.
3. **Resource / `Assets.car` collision.** Two catalogs in one target both emit
   `Assets.car` → "Multiple commands produce". The Mac catalog is `idiom: mac`
   only and must be excluded from iOS; the iOS catalog stays. Also,
   `Fretlight/` resources land **flat** in `Contents/Resources/` (the note
   library is looked up with no `subdirectory:` in
   `Fretlight/Audio/NoteSampleLibrary.swift:93,126`); the 13 MB `NoteSamples`
   directory will copy into iOS when Phase 2 shared membership lands, which is
   required, not waste.
4. **Module naming — resolved in Phase 0.** The iOS module was renamed from
   `FretworkIOS` to `Fretwork` on 2026-09-18 (the explicit `PRODUCT_MODULE_NAME`
   was removed, so it defaults from `PRODUCT_NAME`); `-showBuildSettings`
   confirms `PRODUCT_MODULE_NAME = Fretwork`, and
   `FretworkIOSTests/FretworkIOSScaffoldTests.swift:2` is
   `@testable import Fretwork`. This satisfies the four `Fretwork.`-qualified
   shared references (`PracticeState.swift:394,488`,
   `TriadsModuleModel.swift:29,62`). The two targets never link together, so
   sharing the Mac module name is safe. Do not reintroduce a per-target
   `PRODUCT_MODULE_NAME`.
5. **Microphone usage string — added in Phase 0.** The iOS `Info.plist` now
   carries `NSMicrophoneUsageDescription = "Fretwork listens to your guitar
   input to identify notes."` (setting `INFOPLIST_KEY_NSMicrophoneUsageDescription`
   in the iOS Debug/Release configs; `PlistBuddy` confirms it in the built
   product). It is still required before the Phase 1 physical microphone spike,
   and it must stay an `INFOPLIST_KEY_*` setting — do not copy the Mac
   `INFOPLIST_FILE = Config/Info.plist` (which carries Sparkle `SU*` keys) into
   iOS.
6. **Sparkle leakage.** Sparkle is vendored and embedded only by the Mac
   target's Frameworks/Embed Frameworks phases. The iOS target has an empty
   Frameworks phase and its own generated `Info.plist`, so it never gets Sparkle
   or `SU*` keys — provided nobody copies `INFOPLIST_FILE = Config/Info.plist`
   or the Mac phases into iOS. Keep the two targets' build phases separate.
7. **Simulator flake.** The only installed runtime is iOS 26.5 with SDK 27.0. A
   one-off `FBSOpenApplicationServiceErrorDomain … Application failed preflight
   checks (Busy)` appeared after a rebuild while a prior launch was settling; it
   is a simulator flake — retry before treating it as a defect. Use `OS=26.5`
   explicitly. iPhone SE (2nd gen) is the smallest *reference* but is not
   installed.

## Phase 1 — Simulator-first audio spike (implemented; iPhone capture, latency, CPU/thermal and permissions verified; iPad deferred)

**Prerequisites:** Phase 0 complete. The Simulator-first slice (synthetic
pipeline + harness UI + manual capture stubs) was built and verified on
Simulator. The physical test devices — iPhone 14 Pro Max and iPad Pro 13-inch
(M5) (C-24) — still require their OS versions recorded, Developer Mode/device-
trust confirmation, and working development-level automatic signing/provisioning.
If the configured Development Team cannot provision a physical device, Apple
Developer Program enrollment blocks the physical-device spike; Simulator work is
unaffected (C-23).

### Simulator-first slice: what was built

A minimal iOS-only analysis harness (`FretworkIOS/Phase1/`) exercising the real
shared `AudioAnalysisWorker` + `PitchDetector` path without microphone hardware
or `AppState`. The harness provides:

- **`Phase1AnalysisPipeline`** — owns `RingBuffer`, `SensitivitySettings`,
  `AudioAnalysisWorker`; exposes `PitchDisplayState` and telemetry. `write()`
  is realtime-safe: a lock-free SPSC `FrameEventRing` carries frame-count
  events from the callback, drained under the telemetry lock in the worker's
  update path. No `NSLock` or allocation in the realtime thread.
- **`Phase1SyntheticFeeder`** — deterministic sine generator (default 440 Hz A4)
  that writes mono PCM into the analysis pipeline without `AVAudioSession` or
  hardware. Runs as a detached `Task` with adjustable tone, amplitude, frame
  count and cadence.
- **`Phase1MicrophoneHarness`** — temporary `AVAudioSession`/`AVAudioEngine`
  spike using `AVAudioSinkNode`. Validates Float32 non-interleaved format;
  clamps negative sample times. `self.engine` / `self.pipeline` are set before
  any fallible setup so `cleanup()` can detach an attached sink if
  `engine.start()` throws. `try Task.checkCancellation()` after
  `ensurePermissionGranted()` prevents Stop-during-prompt from later
  activating audio. The `installTap` path was deleted after physical-device
  measurement selected the sink (see Tasks completed).
- **`Phase1HarnessModel`** — `@MainActor @Observable` state machine with
  `.idle` / `.starting` / `.running(mode)` / `.permissionDenied` / `.failed`
  states. Creates a **fresh `Phase1AnalysisPipeline` on every explicit Start**
  (no stale ring state carried between runs). Tracks a `generation` counter;
  the start task captures the current generation and checks it on completion,
  making stale completions (from Stop-called-during-Start) into no-ops.
  Resets `telemetry` on each Start. `pipeline.onUpdate` is guarded by
  `generation` so a stopped old worker cannot overwrite a new run's state.
- **`Phase1HarnessView`** — SwiftUI list showing mode picker (disabled when
  running or starting), Start/Stop buttons, status, telemetry (note, frequency,
  level, update count, callback frame histogram), and a "no mic-to-speaker"
  graph-rule reminder. Stops capture on `.background` scene phase; does not
  stop on `.inactive` (which transiently fires during permission alerts).
  Default launch is entirely inert: no audio session, no permission request,
  no engine start, no pipeline allocated. Capture begins only from the
  explicit Start button.

### Seven shared files added to iOS target membership

Rather than adding the full `Fretlight/` synchronized group (which requires the
29-entry exception set deferred to Phase 2), Phase 1 added explicit
`PBXFileReference` + `PBXBuildFile` entries for exactly these seven files in the
iOS target's Sources build phase:

1. `Fretlight/Audio/AudioAnalysisWorker.swift` — shared analysis loop
2. `Fretlight/Audio/RingBuffer.swift` — lock-free SPSC storage
3. `Fretlight/Audio/SensitivitySettings.swift` — user-facing sensitivity dial
4. `Fretlight/Pitch/PitchDetector.swift` — YIN pitch detector
5. `Fretlight/Pitch/NoteMapper.swift` — frequency→MappedNote
6. `Fretlight/Models/PitchDisplayState.swift` — observable pitch state
7. `Fretlight/Theory/PitchClass.swift` — chromatic pitch class

This set was verified to type-check cleanly for `arm64-apple-ios26.0-simulator`
with module name `Fretwork` and Swift 6 strict concurrency. All seven files are
unmodified from their Mac-target originals.

### New iOS-only Phase 1 files

All under `FretworkIOS/Phase1/`:

- `Phase1AnalysisPipeline.swift` — analysis pipeline + `FrameEventRing`
- `Phase1SyntheticFeeder.swift` — synthetic sine generator
- `Phase1MicrophoneHarness.swift` — manual microphone capture spike
- `Phase1HarnessModel.swift` — `@Observable` state machine
- `Phase1HarnessView.swift` — harness UI

### Tasks completed (Simulator slice)

1. **Done.** Synthetic-feeder pipeline test proves the real `AudioAnalysisWorker`
   + `PitchDetector` runs inside the iOS app module (440 Hz → A4/MIDI 69).
2. **Done.** Harness UI renders on Simulator; default launch is inert (no audio
   session, no permission request, no engine).
3. **Done.** Start/Stop idempotence, permission-denied state, and injected fake
   source isolation are unit-tested with no real audio.
4. **Done.** The `AVAudioSinkNode` capture primitive is wired in
   `Phase1MicrophoneHarness` and selected from physical-device measurement; the
   `installTap` path has been deleted.
5. **Done.** `AVAudioSession` category `.playAndRecord`/mode `.measurement` is
   configured; the graph rule (no microphone-to-speaker connection) is
   documented and enforced in the harness design.
6. **Done.** `AVAudioApplication` permission API (`iOS 17+`) is used for
   status and request; format validation (Float32, non-interleaved, >0
   channels) guards against unexpected input configurations.
7. **Done.** Realtime safety: `write()` uses lock-free SPSC for frame events;
   dictionary mutation and `NSLock` live only in the worker's background
   callback path, never in the audio I/O thread.
8. **Done.** Stop-during-Start produces `.idle`, not `.running`:
   `generation`-gated completion with `Task.checkCancellation()` after
   permission await. Deterministically tested with continuation handshake.
9. **Done.** Background scene phase stops capture; `.inactive` phase
   (permission alerts, control center) does not.

### Tasks remaining (physical-device spike)

These require physical iPhone/iPad hardware and are **not** met by Simulator:

- [ ] Connect iPhone 14 Pro Max and iPad Pro 13-inch (M5); record OS versions
      and confirm Developer Mode/device trust / development provisioning.
      **Partial:** iPhone 14 Pro Max (iPhone15,3, "Phoebe") recorded at **iOS
      27.0 (24A435)**, Developer Mode enabled, wired; **iPad deferred by the
      owner for now.**
- [x] Compare `installTap` vs `AVAudioSinkNode` callback cadence and frame counts
      on physical hardware. **Done for iPhone 14 Pro Max, iOS 27.0, 48 kHz:**
      tap delivered its requested 1024-frame chunks as **4800-frame (~100 ms)
      callbacks at ~10/s**; sink delivered **1120-frame (~23 ms) callbacks at
      ~44/s**. Both detected the same open-string pitches (guitar in Drop D, low
      string ~73 Hz). `latencyMs` read 0 in both because the iOS path did not
      yet populate `PitchDisplayState.latencyMilliseconds`; that gap is fixed
      and end-to-end latency is now measured in the metrics record below. Root
      cause of the
      oversized tap/output coupling is the Swift 6 `@MainActor`-inherited
      realtime closure (commit `e858416`); both blocks are now built in
      `nonisolated` factories.
- [x] Record CPU and thermal behavior on physical hardware. **Done for iPhone
      14 Pro Max, iOS 27.0** (metrics record below): CPU flat across ~1.2-min
      segments (26.9, 25.7, 26.4, 29.0, 28.5%; no uptime ramp) and thermal
      `nominal` throughout. **iPad deferred by the owner for now.**
- [x] Test permission granted, denied and undetermined states on real device.
      **Done on iPhone 14 Pro Max (2026-09-27), owner-run:** granted listens;
      denied (toggled off in Settings) shows "Microphone permission denied"
      with no hang; undetermined (fresh install) prompts, and both Don't Allow
      and Allow then behave as their states above.
- [x] Play acoustic guitar and amplified electric guitar at realistic distances;
      note useful sensitivity range and false triggers.
      **Done on iPhone 14 Pro Max (2026-09-28), owner-played:** acoustic and
      amplified electric in one ~86 s run at normal playing distance, default
      sensitivity. Detected A2 109.5, B2 123.0, C♯3 138.6, D♯3 155.0, E3 164.5 Hz
      — every reading within a few cents, **no octave errors and no false
      triggers**; silence between phrases read "—". 30 of 37 sounding samples
      had confidence ≥ 0.9 (the rest were decays or the label lag below). Input
      level peak 0.030, median 0.011. Latency median 31 ms, CPU ~34%, thermal
      nominal. **Observation for Phase 7 (shared, not iOS-specific):** the note
      *label* follows a 3-of-5 median rule in `AudioAnalysisWorker` while the
      frequency is instantaneous, so on a leap (e.g. B2→E3) the label trails the
      pitch by ~100–150 ms; 7 samples caught that window. The Mac shares it.
- [x] Select one capture primitive and document why; delete the losing path.
      **Done:** `AVAudioSinkNode` selected; `installTap`, `Phase1CaptureMode
      .microphoneTap`, `CaptureKind.tap` and `makeTapBlock` deleted. The sink
      returns the hardware block size (~1120 frames at 48 kHz) against the
      tap's fixed ~100 ms chunks, so detection sees each buffer ~4x sooner.
- [ ] Verify sample playback is at least configuration-compatible with capture.

### Exit criteria

- **Met.** `Fretwork-iOS` builds and tests on Simulator (13 tests, 0 failures).
- **Met.** The seven shared files are the only existing production source added
  to iOS; the full synchronized-root / exception-set approach is deferred.
- **Met.** Default iOS app launch and default tests do not request microphone
  permission or activate real audio (`@testable import Fretwork` + injected
  fakes).
- **Met.** A synthetic test feeds the real `AudioAnalysisWorker` and observes
  the expected A4 note.
- **Met.** Manual Simulator harness Start/Stop is idempotent and shows
  permission/error/telemetry states.
- **Met.** The harness graph has no microphone-to-speaker connection.
- **Pending.** The available physical iPad (deferred by the owner for now) and
  the permission-state matrix remain outstanding; the iPhone 14 Pro Max
  detected played notes through its microphone at the sink cadence above with
  no audible feedback, and its latency/CPU/thermal metrics are recorded below.

### Phase 1 risks carried forward

1. **Explicit PBXFileReference fragility.** The seven `PBXFileReference` entries
   pointing into the `Fretlight/` synchronized root work but are fragile: file
   renames or moves in the shared source tree could silently break the iOS
   build. The planned Phase 2 `PBXFileSystemSynchronizedBuildFileExceptionSet`
   replaces these with shared-root membership, which is self-healing to renames
   within the synchronized group.
2. **Phase 1 is not complete without physical devices.** Simulator validation
   is a build/unit-test gate, not a substitute for tap-vs-sink measurement or
   real-guitar detection.
3. **Tap vs sink is resolved.** `AVAudioSinkNode` is the selected capture
   primitive; the `installTap` path was deleted after iPhone 14 Pro Max
   measurement (4800-frame/100 ms tap chunks at ~10/s versus 1120-frame/23 ms
   sink chunks at ~44/s).

## Phase 2 — Platform-neutral audio seam

**Status: complete (2026-09-27).** Commits `754da0b`, `f274b5f`, `826f320`,
`ccb9b6b`, `c210f6d`, `4899ebf`. Prerequisite C-19/Q-06 option (A) applies, and
the pre-existing test compile failure was repaired in `3e0a461` before the phase
began. Full evidence is in the Phase 2 Implementation Record.

### Files landed

- `Fretlight/Models/DetectionMode.swift` — extracted from `AppState.swift` (pure
  move) so the adapter, board and readout views compile without the Mac state.
- `Fretlight/Models/AudioController.swift` — the `AudioControlling` protocol and
  `AudioControllerEvent` enum, Foundation-only.
- `Fretlight/Audio/MacAudioController.swift` — the macOS adapter: device
  enumeration/selection/persistence, monitoring, direct-path suggestion and the
  DEBUG recorder, plus 1:1 delegation of the untouched `AudioEngine`.
- `Fretlight/AppState+Mac.swift` — the macOS `AppState()` default and the
  `macAudio` cast.
- `Fretlight/Models/AppState.swift` — rewritten to depend on
  `any AudioControlling`.
- `FretlightTests/FakeAudioController.swift`, `AppStateSharedSurfaceTests.swift`,
  `AppStateStartGatingTests.swift`, `MacAudioControllerTests.swift`.
- `Fretlight.xcodeproj/project.pbxproj` — the iOS synchronized-root membership
  and exception set.

### Tasks (complete)

1. ✅ **Defined the smallest surface `AppState` needs** — lifecycle, sensitivity,
   note/chord updates, playback readiness, sample playback, detection gating and
   error/recovery events (`AudioController.swift`). CoreAudio types are absent by
   construction.
2. ✅ **Injected the surface** — `AppState.init(audio:store:)`;
   `AppState+Mac` supplies `MacAudioController` in production and
   `FakeAudioController` in tests.
3. ✅ **Moved Mac-only concerns out of shared state** — device
   enumeration/selection/persistence, monitoring, direct-path suggestion and the
   DEBUG recorder now live in `MacAudioController`; `AppState` no longer names
   `AudioDeviceID`.
4. ✅ **Adapted the Mac engine without behaviour change** — `AudioEngine`,
   `AudioDevice`, `AudioDeviceWatcher` and `MonitorRenderer` are untouched;
   `MacAudioController` delegates 1:1 and preserves each callback's main-actor
   hop.
5. ✅ **Tests prove the seam** — `AppStateSharedSurfaceTests` (14) covers module
   open → `prepareSamplePlayback`, readiness mirroring, the play closure
   reaching `playSample`, gating, sensitivity persistence/restore, and all five
   events; `AppStateStartGatingTests` (2) covers the Retry regression;
   `MacAudioControllerTests` (9) covers the extracted device resolution.
6. ✅ **Moved only proven files** — `DetectionMode` extracted; no view or model
   reorganisation. `AppShell`/`GlobalSettingsView`/`ListenScreen` were kept
   Mac-only (C-list refinement, flagged in the Implementation Record).

### Exit criteria (met)

- ✅ **Shared state compiles without importing CoreAudio** — `AppState.swift`
  has no `CoreAudio`, `AudioDeviceID` or `AudioEngine` reference (commit
  `ccb9b6b`).
- ✅ **The Mac app behaves as before and its full suite is green** — 478 tests,
  0 failures; the smoke test showed two `com.apple.audio.IOThread.client`
  threads, flat CPU and no `-10877`.
- ✅ **A fake audio controller drives note, chord, level, error and recovery
  states without hardware** — `AppStateSharedSurfaceTests`, using an in-memory
  `PracticeStateStore` and never `AppState()`.

## Phase 3 — Production iOS audio and lifecycle (complete on iPhone, 2026-09-28)

Promote the selected Phase 1 primitive into a production controller. Everything
Phase 1 deliberately left out — real lifecycle, interruptions, route changes,
status surfaces, the playback manager and engine-leak checks — is implemented
here.

### Likely files

- new `Fretlight/iOS/` platform folder
- iOS audio-session/capture controller
- iOS app entry point and microphone usage description
- iOS controller unit tests with injected session/lifecycle seams

### Tasks

1. Promote the selected Phase 1 capture path into the iOS audio controller.
2. Configure and activate the audio session only while the app is foreground-
   active and needs listening or playback.
3. Handle microphone authorization, denial, interruptions, media-services reset,
   route changes, backgrounding and foreground recovery.
4. Use the system-selected route. Do not add device enumeration or pickers.
5. Keep input mono at the detector boundary even if the hardware route exposes
   more channels.
6. Support bundled sample playback without connecting input to output.
7. Surface starting, listening, interrupted, permission-denied and failed states
   through shared status types that the iOS UI can explain.

### Exit criteria

- Capture recovers after a simulated and real interruption.
- Denial leads to an explanatory recovery view with a Settings action.
- Repeated foreground/background cycles neither leak engines nor duplicate
  callbacks.
- Sample playback works while the microphone session is configured.

### Phase 3 result (2026-09-28)

**Complete on iPhone 14 Pro Max (iOS 27.0).** Design reviewed by DeepSeek Pro
before implementation and again before commit.

| Commit | Step |
| --- | --- |
| `98a6ea4` | Session / foreground / graph seams (iOS-only, `FretworkIOS/Audio/`) |
| `44655b6` | 138 samples + `index.json` bundled into the iOS app (exception entries removed; presence, index and full-decode tests); Mac bundle unchanged |
| `b7abac8` | `IOSAudioController` + `AppState+IOS` + 17 controller tests. One engine, sink capture dead-ended (no input→output path, C-03 structural), `.playAndRecord/.measurement/.defaultToSpeaker` for listening, `.playback` for playback-only; reuses `CaptureSink`/`SamplePlayer` (realtime blocks built nonisolated). Review fixes before commit: stopped runs were retained by the transition chain (engine leak across fg/bg — now released, with a deallocation test); samples loaded without building an output graph so the first note was silent (now eager, tested) |
| `b19e83b` | DEBUG smoke entry (`-FretworkPhase1Harness` still reaches the Phase 1 harness) |
| `766f16b` | Device-found: a playback-only run reported `listening` and started detection workers with no input; only a capture run now changes status/starts workers. The unit test had asserted the bug |
| `15e67d8` | Device-found: smoke-view Start/Stop shared one List row, so every tap fired both (smoke UI only) |
| `05613e1` | Smoke view shows live detection + 1 Hz stderr line |

**Device checks (owner-run; log corroborates where noted):**
listening — `playAndRecord/measurement`, **mono input (channelCount=1)**, 48 kHz,
notes detected (D3 143.6, A2 108.8, G3, B3, C2 in log), two clean start/stop
cycles, no Core Audio errors (log); sample playback while listening — audible,
**loud enough on the built-in speaker** despite `.measurement`, no feedback;
phone-call interruption auto-resumes; headphone plug/unplug keeps listening with
no microphone audio in the headphones; background/foreground ×5 resumes
listening each time; microphone denied → permission-denied state, no hang. The
interruption, route and background transitions happen while the smoke view is
not on screen, so its status log does not show them — those are owner-verified.

**Tests:** iOS 54/0; Mac suite unchanged (479 executed, 0 failures at Step 2).

**Carried forward:** the smoke view keeps the last level after Stop (cosmetic;
Phase 4 screens should reset the readout on stop). The Settings action on the
denied state is a Phase 4 UI task — Phase 3 verified the state itself. iPad
remains deferred. Detection gating around sample playback remains Phase 7.

## Phase 4 — iOS shell, navigation and settings

### Tasks

1. Promote the minimal iOS target from Phase 0 into the production shell. Keep
   Sparkle, Mac window commands and sample-capture tooling outside its target
   membership.
2. Use adaptive navigation: split-view hierarchy at regular width, compact
   navigation at iPhone width. Listen remains the predictable launch screen.
3. Replace the Mac settings popover with an iOS sheet or navigation destination.
4. iOS settings contain sensitivity, tuning, board orientation, live-note and
   privacy options. They contain no device, monitor or rescan controls.
5. Build explicit first-run/listening, microphone-denied, interrupted and audio-
   failed surfaces. Avoid a multi-page onboarding flow unless device testing
   proves the system prompt lacks necessary context.
6. Keep audio-rate reads out of navigation chrome and settings.

### Exit criteria

- Every screen is reachable with native compact and regular navigation.
- The shell is usable at the smallest supported iPhone width and on iPad.
- Platform-inapplicable controls never appear disabled; they are absent.

## Phase 5 — Responsive Listen screen and fretboard

### Tasks

1. Replace the wide Mac signal-path header on iOS with a compact listening
   status and detection-mode control. Do not display a fictitious input-to-
   output device path.
2. Reflow tuner, level, history and board controls vertically at compact width.
3. Prototype the full 22-fret board as a horizontally scrollable surface on
   iPhone. Preserve legible labels, minimum touch targets and the user's manual
   scroll position.
4. Test whether a user-invoked jump-to-live-position control is useful. Do not
   add automatic follow-scrolling unless human testing shows it does not fight
   inspection or practice.
5. Keep the full board visible where practical on iPad and in wider landscape
   layouts.
6. Verify Dynamic Type, VoiceOver, Reduce Motion, contrast and both board
   orientations.

### Exit criteria

- The Listen flow works in iPhone portrait and landscape without clipped or
  microscopic controls.
- The board remains readable and navigable through all 22 frets.
- Pitch/chord updates invalidate only their existing leaf surfaces.

## Phase 6 — Learning-module adaptation

### Tasks

1. Make `ModuleLayout`, shared glass controls and all ten module screens adapt
   between compact and regular width using shared layout primitives rather than
   ten unrelated fixes.
2. Stack note/key selection, options and actions on iPhone while retaining the
   established information hierarchy: title, controls, stage, explanation.
3. Reuse the compact fretboard behavior from Phase 5 everywhere.
4. Preserve the live-note leaf-view observation boundary and workstream 008's
   visual/accessibility contract if 008 has landed.
5. Verify long note/chord labels, the Circle screen, every picker option and
   every tuning at the smallest supported width.

### Exit criteria

- All ten modules are complete and usable on iPhone and iPad.
- No module creates its own one-off navigation, settings or board behavior.
- Existing module rule tests remain shared and green.

## Phase 7 — Playback exclusion and real-guitar validation

### Tasks

1. Gate note and chord analysis for the precise duration of app-owned sample
   playback plus a device-speaker decay tail.
2. Measure that tail on the representative iPhone and iPad hardware available;
   do not copy a guessed constant from macOS, and do not inherit an unmeasured
   value from the still-open workstream 007 (C-05).
3. Make listening versus playing state visible without flashing or moving the
   surrounding layout.
4. Verify a played sample cannot append note/chord history, advance guided
   practice or light a live position.
5. Run sessions with acoustic guitar and amplified electric guitar in quiet and
   ordinary-room-noise conditions at realistic placement distances.
6. Decide Q-03 from evidence and add source guidance only if it prevents a
   reproducible failure.

### Exit criteria

- The app never credits its own speaker output.
- Detection resumes promptly after the decay tail and catches the next played
  note.
- Real-guitar sessions meet an explicitly recorded latency and reliability bar.

### Results (2026-09-30 → 2026-10-01, iPhone 14 Pro Max, iOS 27.0; iPad deferred by owner)

Measured with two DEBUG-only instruments: `-FretworkBleedProbe` (plays 9
bundled samples through the speaker and logs what the gated and raw detection
streams report) and `-FretworkSessionLog` (one stderr line per gated note,
chord, gate and status change, plus 30 s summaries). Phone on a table at
practice distance.

**Speaker bleed and the gate.** Ungated, the app credited its own speaker on
7–9 of 9 samples, 0.08–0.26 s after a sample started. After a sample's nominal
end there were **zero** detections of any pitch in a quiet room (noise floor
−66 dB), and the level was back at the floor by +0.25 s, so the speaker leaves
no measurable acoustic tail. The first probe's 4 s "tails" were an artifact of a
level-based metric and were discarded. The gate (`PlaybackGate`, in
`IOSAudioController`) suppresses note and chord events from the play call to the
last scheduled sample's nominal end plus **150 ms**. That margin is the detector's
own latency, not a speaker tail: a 2048-sample window at 48 kHz (43 ms) plus the
3-of-5 median (≈99 ms), rounded up. On lift, both workers are reset and the
stale in-flight frames dropped. With the gate on, false credits were **0/9
gated against 9/9 raw** (quiet). In a TV/talking room, nothing passed during
playback either. The gated credits that remained came seconds after the gate
lifted and matched the room's own pitches, not the sample.
"Playing" replaces "Listening" in place, on the Listen pill and the module
capsule, with no layout movement (owner hand-checked).

**Real-guitar sessions** (session log; the owner's external tuner as reference):

| Session | Median abs cents | Octave flips | Onset→note median / p90 | Notes |
| --- | --- | --- | --- | --- |
| Acoustic, quiet (tuned) | 4–8 | 2 | (metric fixed afterwards) | Scale and chromatic run note-for-note |
| Acoustic, TV on | 6–8 | 6 | ≤0.05 s / 0.15–0.5 s | Playing correct, but see the room-noise finding |
| Electric, unplugged, quiet | 6 | 0 (2 octave-down D3→D2) | 0.10 s / 0.58 s | Notes −56 dB vs acoustic −39 dB |

A "low E reads D♯2" report was traced to the string really being at D♯2.
An independent autocorrelation of a raw on-device capture measured 77.7–78.2 Hz,
and the A string 110.3 Hz. The detector was right. The investigation also
removed a latent rate-chain risk: the workers are now told the sink's actual
capture rate (`660e936`).

**Bar met (iPhone):** never credits its own speaker (0/9 gated); resumes 150
ms after nominal end; on a tuned acoustic, median pitch error ≤ 8 cents,
onset→note median ≤ 0.1 s with p90 ≤ 0.6 s, and ≤ 6 octave flips in a session.

**Findings carried forward (not Phase 7 defects):**
- *Pitched room noise* (TV, voices) produces phantom notes with no one playing:
  13 in ~25 s, each ~0.2 s, median −54 dB. They overlap soft real playing
  (15/78 real notes were below −48 dB), so a plain level cut would drop real
  notes too. First thing to try is the existing sensitivity control in a noisy
  room. A noise-floor-relative gate would be a separate piece of work.
- *Unplugged electric:* low three strings hold the readout for a shorter
  time and need louder picking (owner). Consistent with the phone mic's weak
  low-frequency response; a display-hold change would be shared with the Mac.

## Phase 8 — Store readiness and final gates

The release goal is a public App Store listing for both iPhone and iPad (C-22).

### Tasks

1. Add final icons, launch presentation, privacy strings and App Store privacy
   disclosures. State plainly that audio is analysed on device and not stored
   or transmitted.
2. Confirm that iOS builds contain no Sparkle framework, Mac update keys,
   sample-capture command or Mac-only entitlements.
3. Run shared and platform-specific automated suites. Archive and install the
   release build on physical iPhone and iPad hardware.
4. Validate clean install, microphone grant/denial, relaunch, interruption,
   background/foreground, route change, sample playback and all learning
   modules.
5. Regression-test the Mac release build, direct launch, audio paths and
   Sparkle embedding after all target-membership changes.
6. Update `README.md`, `CLAUDE.md`, release documentation and `CHANGELOG.md` with
   the two-platform build/test workflows and the iOS audio decisions.
7. Complete the deferred App Store Connect app record and distribution signing
   (see Blockers) only after all earlier gates pass. Development-level
   provisioning, device trust and Developer Mode were already required for the
   Phase 1 installs, so any enrollment needed for those was resolved before
   Phase 1 (C-23). The bundle identifier is already fixed at
   `org.fretwork.app.ios`; confirm the public subtitle (Q-05) before submission.
8. Reassess a local shared Swift package. Record the decision either way; do
   not make package extraction a release blocker when target membership is
   already clear and maintainable.

### Exit criteria

- A release archive installs and completes the core listen-and-learn flow on a
  physical iPhone and iPad.
- The Mac release archive still launches and retains its existing capabilities.
- Another developer can reproduce both builds and their non-hardware tests from
  the repository documentation.

## Validation matrix

| Area | Required scenarios | Success signal | Failure signal |
| --- | --- | --- | --- |
| Permission | First request, granted, denied, Settings return | State is truthful and recovery needs no relaunch. | Blank meter, repeated prompt or silent failure. |
| Capture | Silence, single notes, scales, held chords, noisy room | Stable useful detections at normal playing distance. | Large buffering, self-triggering or unusable false positives. |
| Playback | Sample while listening, rapid samples, immediate player response | App output is ignored; the next real note is caught promptly. | Sample enters history/practice or gate hides the next note. |
| Lifecycle | Phone interruption, background/foreground, route change | One engine and one callback stream recover cleanly. | Duplicate callbacks, dead capture or persistent interruption state. |
| Compact UI | Smallest compatible iPhone reference (iPhone SE 2nd gen class) plus the actual available iPhone, portrait/landscape, large text | All actions and 22 frets remain reachable and legible. | Clipping, microscopic board or overlapping controls. |
| Regular UI | iPad mini (A17 Pro) and iPad (A16) references plus the 13-inch iPad Air (M3 or later) large-width case; portrait/landscape, split view/multitasking | Hierarchy uses space without becoming a stretched phone UI. | Fixed-width gaps, unusable popovers or lost selection. |
| Accessibility | VoiceOver, Dynamic Type, Reduce Motion, color distinction | Meaning and actions remain available without color or animation. | Pitch color is the only cue or focus order follows drawing order poorly. |
| Regression | Mac direct/split audio, monitoring, devices, Sparkle | Existing behavior and release launch are unchanged. | iOS simplification leaks into the Mac product. |

### Reference device coverage

Representative recent targets used to reason about the layout and audio matrix.
They are **not** a claim that the owner owns all of them, and they are not all
required for Phase 1. Compatibility source: [iOS 26 iPhone list](https://support.apple.com/en-is/guide/iphone/iphe3fa5df43/ios) and [iPadOS 26 device list](https://support.apple.com/pt-br/123706).

| Reference | Role | Why it is representative |
| --- | --- | --- |
| iPhone SE (2nd generation) | Smallest compatible iPhone | 4.7-inch, Home button, least horizontal room; still iOS 26 compatible, so it is the compact-width floor. |
| iPhone 14 Pro Max (available physical device) | Modern large iPhone | Owner-nominated Phase 1/7 device; Face ID and a large compact-width phone surface. Record its installed OS version before testing. |
| iPad mini (A17 Pro) | Compact iPad | Smallest recent iPad; exercises compact regular width and portrait/landscape reflow. |
| iPad (A16) | Mainstream iPad baseline | Most common recent consumer size and price tier. |
| 13-inch iPad Air (M3 or later) | Large regular width / multitasking | Largest common regular-width surface for split view and multiwindow. |
| iPad Pro 13-inch (M5) (available physical device) | Physical large-iPad validation | Owner-nominated Phase 1/7 device; covers large regular-width hardware and physical audio behavior, but not compact-iPad layout behavior. Record its installed OS version before testing. |

### Required physical devices

- Phase 1 uses the available **iPhone 14 Pro Max** and **iPad Pro 13-inch (M5)**
  (C-24/Q-07), with Developer Mode enabled, plus working development-level
  provisioning for the install (C-23). Record each installed OS version before
  measurement.
- Phase 1 and Phase 7 measurements must name the actual devices used.
- Because the available physical iPad is the 13-inch Pro, use it for Phase 1
  audio measurements and large-width validation. Continue Simulator coverage at
  iPad mini/iPad reference sizes; do not report those layouts as physical-device
  measurements.

## Deliberate removals on iOS

- Input and output picker rows
- Device rescan
- Monitor mute and monitor-level controls
- Direct-monitoring suggestion
- Input-to-output device-path summary
- Sparkle update UI and menu commands
- Debug sample-capture window/tooling
- Window minimum sizing and resizability rules

These are not temporarily hidden features. They are inapplicable to the chosen
iOS product. Keep them in the Mac target rather than leaving disabled rows or
TODO placeholders in the phone interface.

## Decision log

| Date | Decision | Evidence / rationale | Constraints affected | Revisit when |
| --- | --- | --- | --- | --- |
| 2026-09-28 | **Sharing principle (owner):** the best platform-specific result takes precedence over sharing, and clean, neat code does too. Share a piece only when doing so is easy, effortless and clean; never bend a view to fit both platforms. | Owner decision. Sharing already meets the bar below the view layer — theory, pitch, the audio seam, `AppState`, module models, fretboard/readout components. | C-06, C-07, C-19 | Never lightly; this governs Phases 4–6. |
| 2026-09-28 | `AppShell`, `GlobalSettingsView` and `ListenScreen` stay **Mac-only**; iOS builds its own. | Applying the sharing principle: AppShell is Mac window chrome (minimum widths, desktop sidebar, toolbar popover) — iPhone navigation is a Phase 4 decision on the device. GlobalSettingsView is a fixed-column desktop form — iOS gets a native `Form` in a sheet bound to the same `AppState` settings (sharing the *settings*, not the view). ListenScreen is heavily Mac routing — iOS gets a phone-first Listen screen; individual readout pieces (tuner, board section) are shared in Phase 5 only where one drops in cleanly, without restructuring the Mac file. No `#if os(macOS)` splicing inside these views. Supersedes the Phase 0 C-list note marking them "shared after Phase 2". | C-06, C-19 | If a Phase 4/5 piece turns out identical on both platforms with no adaptation. |
| 2026-09-28 | The iOS app **bundles the 138-note sample library** (~13 MB). | Owner decision: lessons need the samples and 13 MB is acceptable. Lands in Phase 3 with the iOS audio controller and sample player, plus a test that the iOS bundle contains all 138 `.m4a` files and `index.json` loads, so the library cannot silently drop out (Phase 2's exception set excludes it today). Playback-time detection gating stays Phase 7. | C-04, C-05 | Only if app size becomes a store constraint. |
| 2026-09-28 | Replace `.toggleStyle(.checkbox)` (macOS-only) in `NoteAssociationModuleScreen` with **chips on both platforms** (owner chose option A). | The screen already uses `ChipPicker` for chords, so layer toggles (chord tones, pentatonic, rest of scale) and Loop as tappable chips match it and are touch-friendly. Mac-visible change: update/compare pixel snapshots per CLAUDE.md. Removes that screen from the iOS exception set. Alternatives considered: custom checkbox (small tap targets), platform split (switches too bulky), keep excluded. | C-06, C-19 | — |
| 2026-10-01 | Playback gate = sample's nominal end + **150 ms**, in `IOSAudioController`, iOS only. | Measured on device: zero post-end detections and the level at the floor by +0.25 s, so the margin covers detector latency only (43 ms window + ≈99 ms median). A multi-second hold would mute the player's next note. | C-05 | Re-measure when the detector window, the median rule or playback changes. |
| 2026-10-01 | Keep the screen awake while listening, **default on**, with a Settings toggle (`preventsAutoLockWhileListening`). | Owner: a guitarist's hands are on the instrument; auto-lock ended listening. Applied only while `.listening`, the setting is on and the scene is active. | — | — |
| 2026-09-16 | Build a native universal iPhone/iPad app, not Catalyst. | The code is already SwiftUI, while the audio lifecycle and compact interface require native iOS treatment either way. | C-06, C-08, C-13 | Only if native target constraints prove impossible. |
| 2026-09-16 | Treat the device microphone as the primary input and omit routing UI. | Intended users are unlikely to connect audio interfaces; the system route is sufficient for the product promise. | C-01, C-02 | If real users demonstrate meaningful interface demand. |
| 2026-09-16 | Remove live microphone monitoring on iOS. | Device-speaker monitoring recaptures itself and creates echo/feedback; analysis does not require audible monitoring. | C-03 | If a future headphones-only monitoring feature has a validated need. |
| 2026-09-16 | Keep sample playback but gate detection around it. | Lessons require examples, while a nearby microphone will hear the device speaker. | C-04, C-05 | Re-measure when playback or detector architecture changes. |
| 2026-09-16 | Share product logic and retain separate native platform shells. | This preserves one theory/module source while keeping proven Mac HAL behavior out of the iOS design. | C-06, C-07 | If the shared seam becomes broader than the product logic it protects. |
| 2026-09-16 | Use horizontal board scrolling as the compact-width baseline. | Twenty-two frets cannot remain legible and touchable when uniformly scaled to portrait width. | C-08, C-09 | After the Phase 5 physical-device prototype. |
| 2026-09-18 | Keep both apps in this repository and Xcode project, with separate native app/test targets and schemes. | One repository prevents product-logic drift; target separation keeps platform frameworks, lifecycle and releases independent. | C-15, C-17 | If Xcode target membership becomes materially less maintainable than a workspace boundary. |
| 2026-09-18 | Migrate toward shared/macOS/iOS source folders incrementally. | A large initial move would obscure the audio seam and make regressions difficult to attribute. | C-16 | After each phase proves additional file ownership. |
| 2026-09-18 | Defer a local shared Swift package until after the cross-platform boundary is proven. | Packaging should enforce a discovered boundary, not create one speculatively around mixed state and resources. | C-18 | After Phase 6, before final release documentation. |
| 2026-09-18 | Fix the minimum deployment target at iOS/iPadOS 26.0, the bundle identifier at `org.fretwork.app.ios`, and the release goal at a public App Store listing for iPhone and iPad. | Owner decisions; a bundle ID is immutable after the first upload and public release needs enrollment later. | C-20, C-21, C-22, C-23 | Only if Apple's platform requirements or domain ownership change. |
| 2026-09-18 | Record the "do not edit the Mac app" instruction as an **Open** constraint (C-19/Q-06) rather than silently reinterpreting it. | An absolute reading forbids every shared edit and conflicts with the shared project (C-15); the safe reading permits minimal, verified shared edits. Both readings are stated as explicit options and neither is assumed; the owner must choose (A) or (B). | C-06, C-15, C-19 | Before any Phase 0 target/project mutation, or immediately if the shared seam proves unnecessary. |
| 2026-09-18 | Require the C-19/Q-06 answer **before** the first Phase 0 project mutation rather than before Phase 2. | Phase 0 inevitably edits the common `Fretlight.xcodeproj`; letting that proceed under a provisional reading would decide the user's explicit Mac-protection instruction by default. Planning and preflight remain permitted. | C-06, C-15, C-19 | If the owner's answer changes the architecture. |
| 2026-09-18 | Resolve C-19/Q-06 to option **(A)**: Mac-only files, user-visible behavior, UI, audio routing/monitoring, configuration, assets, signing, release tooling and platform-owned source are immutable, while minimal behavior-preserving shared-source and common-project edits are allowed only when required for iOS/iPadOS, with explicit classification and Mac regression verification. | Owner confirmed "ok lets go" after discussing the exact recommended wording. Option (B) would force a separate or copied architecture and conflict with C-06/C-15; option (A) keeps the single-source shared project while protecting the Mac product. | C-06, C-15, C-19 | If a shared edit cannot be made behavior-preserving, or if target membership becomes materially unmaintainable. |
| 2026-09-18 | Mark Phase 0 ready to execute now that C-19/Q-06 is answered. | Phase 0's first mutating task adds target/build entries to the common `Fretlight.xcodeproj`, which option (A) now permits under the minimal, verified boundary. | C-15, C-16, C-19 | If Phase 0 scaffolding reveals the shared seam is unworkable. |
| 2026-09-18 | Split provisioning sequencing: development-level signing/provisioning, device trust and Developer Mode before Phase 1; App Store Connect record and distribution signing at Phase 8. | A physical install in Phase 1 requires working development provisioning; if the configured team cannot provision, enrollment blocks Phase 1 rather than Phase 8. Distribution work remains deferred. | C-22, C-23 | If the configured team's provisioning capability changes. |
| 2026-09-18 | Mark C-11 (hardware audio excluded from the default test suite) **Inferred**, not Accepted. | The policy comes from `CLAUDE.md` test guidance and the readiness audit; the user did not explicitly accept it. | C-11 | If the owner explicitly confirms or changes the policy. |
| 2026-09-18 | Use representative recent iPhone/iPad references (iPhone SE 2nd gen, a recent Face ID iPhone, iPad mini A17 Pro, iPad A16, 13-inch iPad Air M3+) instead of assuming owned hardware. | Exact owned devices are unknown; reference coverage must not be mistaken for measured hardware. | C-08, C-09 | When the owner names the actual Phase 1 devices. |
| 2026-09-18 (revision 4) | Marked Phase 0 **complete** with full source/test ownership inventories, the proven iOS type-check evidence, the current architectural choice (isolated `FretworkIOS` root; shared membership deferred to Phase 2), created/edited files, git-status snapshot, build/test/product-inspection results and carried-forward risks. Recorded the pre-existing Mac test compile failure (0/453) as the one exception that must be repaired separately before Phase 2; the `Fretwork` module rename and the iOS `NSMicrophoneUsageDescription` landed during Phase 0; Phase 1 hardware/provisioning is not ready. | Status, Phase 0 (tasks, exit criteria, full Phase 0 record), change log, Implementation Record. | Phase 0 is now a complete, self-contained baseline; Phase 2 inherits the shared-membership + exception-set work now that the module is `Fretwork`; Phase 1 remains blocked on hardware and development provisioning. | Phase 2 applies the target-filtered exception set; the separate non-iOS test repair lands before Phase 2; the owner names Phase 1 devices and confirms provisioning (Q-07). |
| 2026-09-19 (revision 6) | Recorded the Simulator-first Phase 1 slice as implemented but Phase 1 incomplete; added the seven-file explicit membership inventory, Phase 1 harness file list, completed/pending task split, met-vs-pending exit criteria, and PBXFileReference fragility risk. Updated Phase 0's historical claim about isolated-root membership with a then-vs-now distinction. Appended Phase 1 Implementation Record with 13-test and build evidence. Mac immutable boundary and pre-existing test exception preserved. | Status, Phase 0 (intro callout, architectural choice), Phase 1 (entirely rewritten), change log, Implementation Record. | Phase 1 Simulator slice is now a recorded artifact; the same repository/shell architecture and physical-device prerequisites are unchanged. | Confirm physical-device provisioning and perform tap-vs-sink measurements before closing Phase 1. |
| 2026-09-27 (revision 7) | Recorded the iPhone 14 Pro Max physical-device capture spike (iOS 27.0, 48 kHz), selected `AVAudioSinkNode` over `installTap` and deleted the losing path and its enum case/helpers, and replaced the tap-block regression test with the sink equivalent. Ticked the tap-vs-sink comparison and the select-one-primitive checkbox; left iPad, CPU/thermal and the permission-state matrix unticked. Appended the physical-device Implementation Record. | Status, Phase 1 (header, harness description, tasks, exit criteria, risks), change log, Implementation Record. | The Phase 1 capture primitive is resolved, so Phase 2 can build the seam on the sink; Phase 1 still cannot close until the iPad and CPU/thermal measurements land. | Real-guitar detection, iPad and CPU/thermal measurement remain before Phase 1 exit. |
| 2026-09-27 (revision 8) | Added the physical-device metrics record: populated `latencyMs` from the sink host-time stamp to worker publication (min/median/max 27.2/30.9/33.1 ms over 6.0 logged minutes), whole-process CPU flat at 26.9–28.5% per ~1.2-min segment with `nominal` thermal and no callback dropouts (85–94 per 2 s), and the screen-on UI cost (~20 CPU points) that motivated the keep-awake change. Ticked the CPU/thermal task; left iPad and the permission-state matrix unticked, recording that the iPad is deferred by the owner for now. | Status, Phase 1 (header, tasks, exit criteria), decision log, Implementation Record. | CPU/thermal behaviour is now measured on iPhone; Phase 1 still cannot close until the iPad and permission-state matrix land. | iPad measurement (owner-timed), permission-state matrix and real-guitar detection remain before Phase 1 exit. |
| 2026-09-27 (revision 9) | Recorded Phase 2 complete: the `AudioControlling` seam, the `MacAudioController` move and the iOS synchronized-root membership plus exception set. Kept `AppShell`/`GlobalSettingsView`/`ListenScreen` Mac-only (refining the Phase 0 C list), excluded `NoteAssociationModuleScreen` for its iOS-unavailable `checkbox` Symbol and the note-sample library from the iOS bundle, and recorded that `start()` returns `Bool` so Retry cannot clear the error banner. | Phase 2 Implementation Record and commits `754da0b`–`4899ebf`. | C-06, C-07, C-10, C-15, C-19 | Owner confirms the C-list refinement; Phase 6 adapts `NoteAssociationModuleScreen`; Phase 3/6 decides the iOS sample-library delivery. |

## Change log

| Date | Constraint delta | Sections rewritten | Direction impact | New decision needed |
| --- | --- | --- | --- | --- |
| 2026-10-01 | Phase 7 complete on iPhone: gate measured (nominal end + 150 ms) and shipped, 0/9 gated self-credits; four real-guitar sessions recorded against a bar; Q-03 resolved (no guidance now); keep-screen-on setting added. | Status, Phase 7 results, Q-03, decision log. | No direction change. Room-noise phantoms and the short low-string hold on unplugged electric are carried forward as findings. | iPad measurement when the owner schedules it; Phase 8 needs the developer account. |
| 2026-09-28 | Owner sharing principle recorded; three Mac views confirmed Mac-only; iOS sample bundling and checkbox→chips decided; Phase 1 closed on iPhone with the guitar sweep. | Status, Phase 1 tasks, decision log. | Phases 4–6 build native iOS views and share below the view layer only where clean. Next: chips (Mac-visible, snapshot-verified), then Phase 3 with bundled samples. | iPad Phase 1 measurement when the owner schedules it. |
| 2026-09-18 | Accepted same-repository/separate-target ownership, incremental migration, independent platform configuration and deferred package extraction. | Status, constraints, selected direction, alternatives, execution contract, Phases 0/2/4/8 and decision log. | The selected direction is now an executable repository/target plan rather than only a conceptual shared-core split. | Its bundle-ID question was later resolved by C-21. |
| 2026-09-18 (revision 2) | Moved the C-19/Q-06 Mac-protection decision ahead of the first Phase 0 project mutation, with planning/preflight still allowed; split provisioning so development-level signing/device trust/Developer Mode precede Phase 1 while App Store Connect and distribution signing stay in Phase 8; relabelled C-11 Inferred rather than Accepted; restated the green-suite contract as a recorded exception until the Mac test compile failure is repaired; removed the stale bundle-ID answer from Q-05. | Status, constraints (C-11, C-19, C-23), verified finding 10, selected direction, open questions, Blockers, execution contract, Phases 0/1/2/8, decision log, change log, Implementation Record preflight. | Same direction, but Phase 0 can no longer mutate the common project until Q-06 is answered, and Phase 1 cannot install physically without development provisioning. | Yes — C-19/Q-06 before any Phase 0 target/project mutation; Q-05 subtitle before Phase 8. |
| 2026-09-18 (revision 3) | Promoted C-19 to Accepted and resolved Q-06 to option (A) after the owner confirmed the exact recommended wording; defined the immutable Mac boundary and the minimal, classified, regression-verified shared-edit allowance; removed the C-19/Q-06 blocker and provisional-interpretation language; marked Phase 0 ready to execute. | Status, C-19, Q-06, selected direction, Blockers, execution contract, Phases 0/1/2, decision log, change log, Implementation Record preflight. | Phase 0 may now execute its common-project mutations; the same-project/shared-core direction is confirmed and the separate/copied-architecture alternative no longer applies. Physical devices and development provisioning remain unconfirmed for Phase 1. | No new architecture decision; the next owner actions are the separate non-iOS Mac test-compile repair and the Phase 1 hardware/provisioning confirmation (Q-07). |
| 2026-09-18 (revision 5) | Accepted the owner-nominated physical test devices: iPhone 14 Pro Max and iPad Pro 13-inch (M5). Retained OS version, Developer Mode/device trust and provisioning as Phase 1 prerequisites, and retained compact-iPad Simulator coverage because the physical iPad is a large-width model. | Status, C-24, verified finding 10, Q-07, Blockers, Phase 1, validation matrix/reference devices, required physical devices, decision log and Implementation Record. | Hardware selection is no longer a Phase 1 blocker; readiness still depends on device setup and development provisioning. | Record installed OS versions and confirm trust/Developer Mode when the devices are connected. |
| 2026-09-27 (revision 9) | Recorded Phase 2 complete; the Mac test compile exception is repaired; the shared seam and iOS synchronized-root membership landed; `AppShell`/`GlobalSettingsView`/`ListenScreen` confirmed Mac-only, and `NoteAssociationModuleScreen` plus the note-sample library excluded from iOS. | Status, Phase 2 (status, files, tasks, exit criteria), decision log, Implementation Record. | Shared state now compiles for both platforms and the Phase 2 exit criteria are met; Phase 3/4/5/6 inherit the flagged adaptations. | Owner confirmation of the C-list refinement; no new architecture decision. |

## References

- Apple, iPhone models compatible with iOS 26:
  https://support.apple.com/en-is/guide/iphone/iphe3fa5df43/ios — source for the
  smallest compatible iPhone reference (iPhone SE 2nd generation) and the
  current Face ID reference (C-20).
- Apple, iPadOS 26 compatible devices: https://support.apple.com/pt-br/123706 —
  source for the iPad mini (A17 Pro), iPad (A16) and 13-inch iPad Air (M3 or
  later) references (C-20).
- Apple, App Store Connect app information (bundle ID immutability after a build
  upload): https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
  — why `org.fretwork.app.ios` is fixed now (C-21).
- Apple, preparing your app for distribution:
  https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution
  — the distribution signing and App Store submission steps deferred to Phase 8,
  while development-level provisioning is required earlier for the Phase 1
  physical installs (C-22, C-23).

## Implementation Record

### Preflight (2026-09-18)

- Mac application target: builds.
- Default Mac test suite: **compile-fails before running (0/453)** because
  `FretlightTests/FretboardBoardViewTests.swift:17-18` passes `.standard` /
  `.dropD` where the parameter type `Tuning` has no such members; the intended
  spellings are `Tunings.standard` / `Tunings.dropD`. Pre-existing, not caused by
  009. Recorded as a blocker to repair in a separate change before the shared-code
  implementation baseline (Phase 2). The test file was not edited as part of this
  workstream revision.
- Development provisioning: unconfirmed. A local Development Team is
  configured, but no provisioning profile, trusted device or Developer Mode
  workflow is confirmed. Development-level provisioning is required for the
  Phase 1 physical installs; if the team cannot provision, Apple Developer
  Program enrollment blocks Phase 1. The App Store Connect app record and
  distribution signing remain deferred to Phase 8 (C-23).
- Physical hardware: the owner nominated an **iPhone 14 Pro Max** and an **iPad
  Pro 13-inch (M5)** for Phase 1/7 testing (C-24). Their installed OS versions,
  connection/trust and Developer Mode remain unconfirmed. Phase 0 is
  Simulator-only.
- Mac-protection boundary (C-19/Q-06): resolved 2026-09-18 to option (A); the
  owner confirmed "ok lets go" after discussing the exact recommended wording.
  Phase 0 may execute its common-project mutations under the minimal,
  behavior-preserving, Mac-regression-verified boundary recorded in C-19.
- Physical devices are identified but not confirmed ready. Phase 1 waits on
  recording their OS versions, connection/trust, Developer Mode and
  development-level provisioning; Phase 2 waits on the test compile-failure
  repair.

### Phase 0 (2026-09-18) — complete, with one recorded exception

> **Phase 1 update (2026-09-19):** The claim below that "the iOS target compiles
> **only** its isolated `FretworkIOS/` filesystem-synchronized root" was accurate
> at Phase 0 completion. Phase 1 added explicit membership for seven shared files;
> see the Phase 1 Implementation Record below.

Baseline commit: `32643f6` (`main`). Toolchain: Xcode 27.0 (27A266a), SDK
`iphonesimulator27.0`, only installed iOS runtime 26.5. Simulator used: iPhone 17
Pro `2D89BEAB-E0BF-4982-9F96-17B4E8199F64`; iPad Pro 13-inch (M5)
`57C59EFB-CBE5-49E7-B1DB-9A573ADFF9DF` booted but unused in Phase 0.

A **concurrent Phase 0 fix landed during this session**: the iOS module was
renamed to `Fretwork` (explicit `PRODUCT_MODULE_NAME` removed),
`NSMicrophoneUsageDescription` was added to the iOS configs,
`FretworkIOSTests/FretworkIOSScaffoldTests.swift` was switched to
`@testable import Fretwork` with `testHostedAppMinimumOSIs26` reading the hosted
bundle's `MinimumOSVersion`, and `IOSScaffoldView` dropped its `minimumOS` marker
(adding `.accessibilityHidden(true)` on the decorative icon). The iOS build/test
and product inspection above were re-run **after** that fix. No repository file
outside this workstream document was edited by the reporting session itself.

**Outcome.** The minimal `Fretwork-iOS` app target
(`B100000000000000000000A1`), `Fretwork-iOSTests` target
(`B100000000000000000000B1`) and shared schemes exist. The iOS target compiles
**only** its isolated `FretworkIOS/` filesystem-synchronized root; no existing
production source is a member and no file moved. Source classification (68
shared / 10 macOS-only + Mac `Assets.xcassets` / 18 requires-extraction) and test
classification (35 immediately portable / 3 after extraction / 14 macOS-only /
1 new iOS file with 2 tests) are recorded in the Phase 0 section above; iOS
type-check evidence (`swiftc -typecheck -module-name Fretwork` against the iOS
Simulator SDK, exit 0 both with and without `-D DEBUG`) is recorded there too.

**Commands and results.**

```bash
xcodebuild -project Fretlight.xcodeproj -list
# Fretlight, FretlightTests, Fretwork-iOS, Fretwork-iOSTests; schemes Fretlight, Fretwork-iOS

xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build
# ** BUILD SUCCEEDED **

xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test
# ** TEST FAILED ** — compile error only, 0/453 run:
# FretboardBoardViewTests.swift:17:58  error: type 'Tuning' has no member 'standard'
# FretboardBoardViewTests.swift:18:58  error: type 'Tuning' has no member 'dropD'

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
# ** BUILD SUCCEEDED **

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
# ** TEST SUCCEEDED ** — 2 tests, 0 failures

git diff --check   # clean (exit 0)
```

Mac launch smoke: `.../Debug/Fretwork.app/Contents/MacOS/Fretwork` in the
background (pid 8112); CPU 2.3% at 3s and 2.7% at 7s (flat); no `-10877` /
`kAudioUnitErr_*` / Core Audio errors on stdout/stderr; killed with `pkill -9`.

**Product inspection.** iOS `Debug-iphonesimulator/Fretwork.app`: no Sparkle
(`find` and `otool -L` both empty), no `SU*` keys, 0 `.m4a`, no `index.json`
(shared membership deferred), iOS `Assets.car` only,
`CFBundleIdentifier = org.fretwork.app.ios`, `MinimumOSVersion = 26.0`,
`NSMicrophoneUsageDescription = "Fretwork listens to your guitar input to
identify notes."`, `PRODUCT_MODULE_NAME = Fretwork`, no Mac entitlements, empty
Frameworks phase, no audio activation. Mac `Debug/Fretwork.app` unchanged:
`Sparkle.framework` present, 138 `.m4a` + `index.json`, `Assets.car`,
`org.fretwork.app`, its own microphone string. The iOS app icon is the
placeholder (one universal 1024×1024 entry, no image file). The iOS
`DEVELOPMENT_TEAM` is deliberately omitted; enabling physical installs is a
Phase 1 provisioning action (C-23).

**Recorded exception.** The pre-existing Mac test compile failure (0/453) at
`FretlightTests/FretboardBoardViewTests.swift:17-18` remains. The file was not
edited in Phase 0. Repair it as a separate non-iOS change **before Phase 2**;
after that repair both suites must be green at every phase gate.

**Phase 1 status.** Not ready. Phase 0 proved Simulator scaffolding only. The
physical devices are now selected—iPhone 14 Pro Max and iPad Pro 13-inch (M5)—
but Phase 1 still needs their installed OS versions recorded, Developer Mode and
device trust confirmed, and working development-level automatic
signing/provisioning.

**Phase 2 status.** Blocked on (a) the separate Mac test repair above and (b) the
target-filtered `PBXFileSystemSynchronizedBuildFileExceptionSet` (29 entries)
that admits the 68 shared files to iOS. The `Fretwork` module-name precondition
landed during Phase 0 (`-showBuildSettings` reports `PRODUCT_MODULE_NAME =
Fretwork`; the iOS test imports `Fretwork`), so Phase 2 can add the shared root
and exception set directly. The iOS `NSMicrophoneUsageDescription` is now present
and must remain before the Phase 1 physical spike.

### Phase 1 Simulator slice (2026-09-19) — implemented; physical-device spike pending

Toolchain: Xcode 27.0 (27A266a), SDK `iphonesimulator27.0`, iOS runtime 26.5.
Simulator: iPhone 17 Pro (`2D89BEAB-E0BF-4982-9F96-17B4E8199F64`).

**Phase 1 files created.**

```
FretworkIOS/Phase1/Phase1AnalysisPipeline.swift
FretworkIOS/Phase1/Phase1SyntheticFeeder.swift
FretworkIOS/Phase1/Phase1MicrophoneHarness.swift
FretworkIOS/Phase1/Phase1HarnessModel.swift
FretworkIOS/Phase1/Phase1HarnessView.swift
```

**Existing shared files added to iOS target (explicit PBXFileReference/PBXBuildFile).**

```
Fretlight/Audio/AudioAnalysisWorker.swift
Fretlight/Audio/RingBuffer.swift
Fretlight/Audio/SensitivitySettings.swift
Fretlight/Pitch/PitchDetector.swift
Fretlight/Pitch/NoteMapper.swift
Fretlight/Models/PitchDisplayState.swift
Fretlight/Theory/PitchClass.swift
```

**New iOS test file.** `FretworkIOSTests/Phase1HarnessTests.swift` (9 tests).

**Results.**

```bash
xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
# ** BUILD SUCCEEDED **

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
# ** TEST SUCCEEDED ** — 13 tests, 0 failures
#   FretworkIOSScaffoldTests 4/4
#   Phase1HarnessModelTests 7/7
#   Phase1SyntheticPipelineTests 2/2

xcodebuild -project Fretlight.xcodeproj -scheme Fretlight \
  -destination 'platform=macOS' build
# ** BUILD SUCCEEDED ** (no regression)

git diff --check   # clean (exit 0)
```

**Product inspection** (iOS `Debug-iphonesimulator/Fretwork.app`):

- `CFBundleIdentifier = org.fretwork.app.ios`
- `MinimumOSVersion = 26.0`
- `NSMicrophoneUsageDescription = "Fretwork listens to your guitar input to identify notes."`
- No Sparkle, no `SU*` keys, no embedded Frameworks, no Mac entitlements
- iOS `Assets.car` only (no Mac catalog)
- `PRODUCT_MODULE_NAME = Fretwork`

**Design properties intentionally excluded from Phase 1:**

- No `AppState` or platform-neutral audio-controller seam (Phase 2).
- No production lifecycle, interruption/route recovery or status surfaces (Phase 3).
- No navigation shell or settings (Phase 4).
- No sample-playback or detection gating (Phase 7).
- Only the `AVAudioSinkNode` capture path exists; the losing `installTap` path
  was deleted after physical-device measurement.

**Phase 1 physical-device spike partially measured (iPhone only).**

The iPhone 14 Pro Max capture spike ran (iOS 27.0, 24A435, Developer Mode
enabled). `AVAudioSinkNode` was selected over `installTap`, and the losing path
plus its enum case, `CaptureKind.tap` and `makeTapBlock` were deleted. The iPad
Pro 13-inch (M5) is **deferred by the owner for now**; CPU/thermal and latency
are recorded below, and the permission-state matrix and real-guitar detection
remain pending.

### Phase 1 physical-device capture spike — iPhone (2026-09-27) — partial

**Device.** iPhone 14 Pro Max (iPhone15,3, "Phoebe"), **iOS 27.0 (24A435)**,
Developer Mode enabled, wired; UDID `00008120-001C3D003EA0C01E`
(`xcrun devicectl device info details`). 48 kHz session
(`.playAndRecord`/`.measurement`). Guitar in Drop D, low string ~73 Hz.

**Raw console log.** `/tmp/fretwork-phase1-console.log` — lines 3–18 tap run,
19–31 sink run, both driven by `Phase1HarnessView` Start/Stop through
`Phase1DiagnosticLogger` (2 s interval).

| Primitive | Callback frames | Callback rate | Update rate | `latencyMs` |
| --- | --- | --- | --- | --- |
| `installTap(onBus:bufferSize: 1024)` | 4800 (~100 ms) | ~10/s | ~10/s | 0 (unpopulated) |
| `AVAudioSinkNode` | 1120 (~23.3 ms) | ~44/s | ~22/s | 0 (unpopulated) |

Both detected the same open-string pitches (D2 72.9 Hz, D3 145 Hz, A2 109.7 Hz,
E4 329 Hz). One tap sample reported B3 hz=123.9 — a one-off octave slip, not
reproduced.

**Latency gap.** `latencyMs` is 0 in both because the iOS path never populates
`PitchDisplayState.latencyMilliseconds`. End-to-end latency is therefore **not
measured**; callback size/rate is the evidence, and the tap's fixed ~100 ms
chunks made detection ~4x staler than the sink's ~23 ms.

**Root cause (commit `e858416`).** `AVAudioNodeTapBlock` /
`AVAudioSinkNodeReceiverBlock` are `NS_SWIFT_NONSENDABLE`; a closure literal
inside the `@MainActor` harness inherits MainActor isolation and traps on the
first realtime callback. Both are built in `nonisolated` factories; the iOS
target enables the Swift 6 language mode.

**Decision.** Select `AVAudioSinkNode`; delete the losing path. Removed
`Phase1CaptureMode.microphoneTap`, `CaptureKind.tap`, `makeTapBlock` and
`installTap`; default mode is now `.microphoneSink`. The tap-block regression
test was replaced by the sink equivalent (hand-built `AudioBufferList`, called
from a detached task, asserting `rawCallbackCountSnapshot() == 1`).

**Commands and results.**

```bash
xcrun devicectl device info details --device 00008120-001C3D003EA0C01E
# OS Version: 27.0 (24A435); Developer Mode Status: Enabled (1)

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
# ** TEST SUCCEEDED ** — 21 tests, 0 failures
#   FretworkIOSScaffoldTests 4/4
#   Phase1DiagnosticLoggerTests 2/2
#   Phase1HarnessModelTests 11/11
#   Phase1MicrophoneHarnessBlockTests 1/1
#   Phase1SyntheticPipelineTests 3/3
```

**Still pending (capture spike).** iPad Pro 13-inch (M5) (deferred by the
owner for now); the permission-state matrix (granted/denied/undetermined);
real acoustic/amplified guitar detection at realistic distances. CPU/thermal
and latency are recorded next.

### Phase 1 physical-device metrics — iPhone (2026-09-27)

Same device and session as the capture spike: iPhone 14 Pro Max (iPhone15,3),
iOS 27.0 (24A435), `AVAudioSinkNode`, 48 kHz, 1120-frame callbacks (~44/s).
Raw console logs: `/tmp/fretwork-phase1-metrics-run1.log` (short runs; screen
dimmed mid-session, before keep-awake existed) and
`/tmp/fretwork-phase1-metrics-run2.log` (keep-awake build, screen on).

**`latencyMs` (now populated).** `Phase1AnalysisPipeline` computes it from the
host-time stamp in the sink callback to `mach_absolute_time()` on the analysis
worker (`Phase1Diagnostics.swift`). Run 2 logged **180 samples = 6.0 min** of
capture (the user reports a 10-minute session; only 6 min reached the log, so
these figures describe the logged 6 min, not the full 10). min/median/max
**27.2 / 30.9 / 33.1 ms**. The session reported `inputLatencyMs=1.37`,
`ioBufferMs=23.33`, so mic-to-detection is **~30–35 ms**, excluding
analog/HAL latency beyond `inputLatency`. It is a **lower bound**: the stamp is
the most recent ring write, understating the oldest analysed sample by up to
one 2048-frame window (~43 ms).

**CPU/thermal.** Whole-process CPU (Mach `thread_basic_info`) per ~1.2-min
segment: **26.9, 25.7, 26.4, 29.0, 28.5%** — flat, no uptime ramp. Thermal
`nominal` throughout. Callbacks **85–94 per 2 s** across the whole run: **no
dropouts**. Run 1 showed the screen dimming mid-session and CPU falling from
~35% to ~15% at that point: screen-on UI rendering costs roughly **20 CPU
points**. `Phase1HarnessView` now disables the idle timer while capturing
(`UIApplication.isIdleTimerDisabled`) so the screen stays on.

**Commands and results.**

```bash
xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
# ** TEST SUCCEEDED ** — 30 tests, 0 failures
#   Phase1DiagnosticFormatterTests 9/9 (latency math, CPU scale, wording)
```

**Still pending.** iPad Pro 13-inch (M5) (deferred by the owner for now);
the permission-state matrix (granted/denied/undetermined); real
acoustic/amplified guitar detection at realistic distances.

### Phase 2 (2026-09-27) — complete

**Commits.** `754da0b` extract `DetectionMode`; `f274b5f` add
`AudioControlling`/`AudioControllerEvent`; `826f320` add `MacAudioController`
and its pure device-resolution tests; `ccb9b6b` the atomic rewire; `c210f6d`
shared-surface tests; `4899ebf` iOS target membership and exception set. The Mac
test compile failure that gated the phase's green-suite exit criterion was
repaired first in `3e0a461`.

**Outcome.** `AppState` depends on `any AudioControlling` and imports neither
CoreAudio nor names `AudioDeviceID`/`AudioEngine`. Device enumeration, selection
and persistence, monitor routing, the direct-path suggestion and the DEBUG
recorder live in `MacAudioController`. `AppState+Mac` supplies the macOS
`AppState()` default and the `macAudio` cast. The five engine callbacks collapse
into one `onEvent` → `handle(_:)`.

**Preserved invariants.** `sensitivity` is restored then explicitly
`applySensitivity()`d in init; `onEvent` is subscribed before any `start()` can
fire; device rescans stay off the main actor behind the existing 300 ms debounce;
navigation never rebuilds the graph (`AppShellNavigationTests` asserts via
`macAudio`); audio-rate reads stay in their leaf views.

**Reviewed fixes.**
- `onEvent` is typed `(@MainActor @Sendable (AudioControllerEvent) -> Void)?`, so
  `AppState` calls `handle(event)` directly instead of adding a second `Task`
  hop; the controller already hops once per engine callback.
- `AudioControlling.start() -> Bool` fixes the regression the review caught:
  clearing `errorMessage`/`isReconnecting` before `MacAudioController`'s device
  guard let a Retry with no device selected wipe the banner. `AppState.start()`
  clears only when a start was actually issued; `AppStateStartGatingTests` pins
  both branches.
- The designated `AppState.init(audio:store:)` documents that `AppState` and
  `MacAudioController` must share the same `PracticeStateStore`; `AppState()`
  guarantees it.
- `deinit` uses `isolated deinit`, since a plain deinit cannot call the
  `@MainActor stop()`. Verified to type-check against the macOS 14 deployment
  target and to launch and run; the Swift concurrency runtime back-deploys the
  isolated-deinit shim.

**Tests.**

```bash
xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' test
# ** TEST SUCCEEDED ** — 478 tests, 10 skipped, 0 failures
# (453 at the start; +9 MacAudioControllerTests, +2 AppStateStartGatingTests,
#  +14 AppStateSharedSurfaceTests)

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,id=CCF133DA-ABFB-459A-BC8C-1720C8E62FE6' test
# ** TEST SUCCEEDED ** — 30 tests, 0 failures

xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'id=00008120-001C3D003EA0C01E' -allowProvisioningUpdates \
  -derivedDataPath /tmp/fretwork-ios-dd build
# ** BUILD SUCCEEDED **
```

**Smoke test (Debug `Fretwork.app`, launched directly).** Two
`com.apple.audio.IOThread.client` threads in `sample <pid> 3`; CPU flat at 0.4%
(TIME 0.41 s → 0.43 s over 5 s); no `-10877`/`kAudioUnitErr`/error output; only
the launched PID was killed.

**iOS target membership (commit `4899ebf`).** `A0000...004 /* Fretlight */` was
added to the iOS target's `fileSystemSynchronizedGroups` with a per-target
`PBXFileSystemSynchronizedBuildFileExceptionSet`. The seven shared files the
target previously compiled explicitly (`AudioAnalysisWorker`, `RingBuffer`,
`SensitivitySettings`, `PitchDetector`, `NoteMapper`, `PitchDisplayState`,
`PitchClass`) and their `PBXBuildFile`/`PBXFileReference` entries were removed so
nothing builds twice. `PRODUCT_MODULE_NAME` stays `Fretwork`.

Exception list (17 files + 139 resources = 156 entries): `FretlightApp.swift`,
`AppState+Mac.swift`, `Audio/{AudioDevice, AudioDeviceWatcher, AudioEngine,
MacAudioController, MonitorRenderer}.swift`, `Models/SampleCaptureModel.swift`,
`Views/{AppShell, CheckForUpdatesView, DevicePickerView, GlobalSettingsView,
ListenScreen, SampleCaptureHost, SampleCaptureView}.swift`, `Assets.xcassets`,
and every file under `Resources/NoteSamples/`.

Extras beyond the plan's list:
- `Views/Modules/NoteAssociationModuleScreen.swift` uses the `checkbox` SF
  Symbol, unavailable on iOS. Excluded rather than changing the Mac rendering;
  **Phase 6 must adapt it** (a portable symbol or an iPhone screen).
- `Resources/NoteSamples/*` (138 `.m4a` + `index.json`). Membership exceptions
  do not honour a plain resource directory, only discrete members, so each file
  is listed. **Phase 3/6 must decide how iOS obtains the sample library**
  (bundle it then, download it, or omit it); shipping 13 MB into the Phase 2
  scaffold was not intended.

**iOS `.app` size.** 1.5 MB scaffold baseline → **8.7 MB** after membership; the
increase is the shared Swift code. With the samples accidentally included it was
22 MB, so the exception saved ~13 MB. The Mac app still carries all 138 samples
plus `index.json`.

**C-list refinement — flagged for the owner.** Phase 0's category C marked
`AppShell`, `GlobalSettingsView` and `ListenScreen` as "shared after Phase 2".
Phase 2 keeps them Mac-only: they own device/monitor/direct-path rows that are
Mac-only by definition, and Phase 4/5 build a fresh iOS shell, settings sheet and
compact listen header. Only `PitchReadoutView`, `FretboardView`,
`DetectionBoardAdapter`, `ModuleLayout` and the ten module screens are genuinely
shared (with `NoteAssociationModuleScreen` excepted above). This refines, rather
than contradicts, the C list; the owner should confirm.
