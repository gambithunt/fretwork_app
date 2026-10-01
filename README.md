# Fretwork

Guitar apps for macOS and iOS. Both listen to your guitar on the built-in or
chosen input and show the note you just played on a 22-fret fretboard —
including which position on the neck it thinks you actually played it at. The
Mac app also monitors the signal back out through whichever speakers or
headphones you choose.

## Requirements

macOS 14 or later (Mac app) or iOS/iPadOS 26 or later (iPhone/iPad app), plus
Xcode with the matching SDKs. Swift 6 with strict concurrency checking set to
`complete`.

## Build and run

The repository holds one Xcode project with two apps, each with its own target
and scheme:

| Platform | Scheme | Targets |
| --- | --- | --- |
| Mac | `Fretlight` | `Fretlight`, `FretlightTests` |
| iPhone/iPad | `Fretwork-iOS` | `Fretwork-iOS`, `Fretwork-iOSTests` |

**Mac:**

```
xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build
```

Run the tests with `test` in place of `build`. Kill any leftover app
process first — one from a previous run can hang the test host's launch
with no useful error:

```
pkill -9 -f "Fretwork.app/Contents/MacOS"
```

**iPhone/iPad (Simulator):**

```
xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

**iPhone/iPad (physical device):** a Release build for a generic device does
not need a connected phone, and is what the store-readiness audit inspects:

```
xcodebuild -project Fretlight.xcodeproj -scheme Fretwork-iOS \
  -configuration Release -destination 'generic/platform=iOS' build
```

To install and watch a development build on a trusted, Developer-Mode device:

```
xcrun devicectl device install app --device <UDID> \
  /path/to/Build/Products/Debug-iphoneos/Fretwork.app
xcrun devicectl device process launch --device <UDID> --console org.fretwork.app.ios
```

`xcrun devicectl device info details --device <UDID>` confirms Developer Mode.

**Naming:** the Xcode project, its Mac target and Mac scheme are still called
`Fretlight`, the original name. The product and the Swift module are
`Fretwork`; the iOS target and scheme are `Fretwork-iOS`. Tests import
`Fretwork`, not `Fretlight`.

## Releasing

The Mac app is distributed from [fretwork.org/mac](https://fretwork.org/mac) as
a signed but deliberately un-notarized disk image, and updates itself with
Sparkle. Pushing a `v*` tag builds, signs and publishes a release; nothing
else does.

```
./scripts/build-release.sh build
```

produces the same artifacts locally without publishing: a universal signed
`.dmg`, an `appcast.xml` carrying the release's EdDSA signature, and a
`version.json` the website reads at runtime.

Before tagging, bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` — the
tag is only a trigger, and every version string comes from the built app's
`Info.plist`.

Two keys are involved, a signing certificate and Sparkle's EdDSA key. Neither
is in this repo and neither is recoverable: losing the first re-prompts every
user for microphone access, losing the second means no update can ever be
offered again.

**See [docs/releasing.md](docs/releasing.md)** for how the pipeline works step
by step, how to test it, how to verify a release actually landed, and how to
back the keys up.

## Viewing anonymous usage telemetry

Anonymous usage telemetry is strictly opt-in: an enabled app sends at most one
daily activity record containing its version and an approximate country. It
never includes audio, notes, practice history, device information, identity,
IP address, or precise location.

Cloudflare stores the records in Workers Analytics Engine. In the Cloudflare
dashboard, select the Fretwork account and open **Analytics & Logs → Analytics
Engine**; the dataset is named `fretwork_usage`. The dashboard is useful for
confirming the dataset and Worker, while the included report gives the useful
active-user, country, version, and daily-trend summary.

Create a least-privilege read-only token at **Profile → API Tokens → Create
Token → Create Custom Token**. Give it **Account → Account Analytics → Read**,
limit it to the Fretwork account, and copy its value (Cloudflare only displays
it once). Find the account ID in that account's dashboard overview, then run:

```sh
export CF_ACCOUNT_ID='your Cloudflare account ID'
export CF_ANALYTICS_TOKEN='your read-only API token'
./scripts/telemetry-report.sh
```

Keep the token out of the repository and never place it in the app or Worker.
See [docs/telemetry.md](docs/telemetry.md) for the data model, deployment, and
custom SQL-query details.

## How it works

Audio in, note out:

1. **Capture** — an `AVAudioSinkNode` takes samples out of the engine at the
   hardware block size. Not `installTap`, whose buffer size is advisory and
   which macOS answers with 4410-frame chunks regardless of what you ask
   for, costing a tenth of a second before anything downstream even starts.
2. **Detection** — YIN, on a background queue. YIN needs several waveform
   periods, so at 48 kHz with a 2048-sample window the low E's detection
   latency is bounded around 25–40 ms by physics, not by the code.
3. **Pitch** — the detected frequency becomes a note name, octave and a
   cents-off-perfect reading.
4. **Position** — pitch alone can't say where on the neck you played: most
   notes in range have more than one position and some have five.
   `FretPositionResolver` tracks where your fretting hand appears to be and
   ranks the candidates by how far the hand would have to travel.

Meanwhile the captured signal is monitored back out. Two paths:

- **Direct** — when one device serves both input and output (any real audio
  interface does), a single engine binds to it and capture and playback
  share one IO cycle and one clock. This is the low-latency path, and the
  app offers to switch you onto it when it notices you could be.
- **Buffered** — genuinely separate devices (built-in mic to built-in
  speakers) can't share one audio unit, so a second engine plays back from a
  ring buffer, with drift correction between the two clocks. It works, and
  you can hear the difference.

The telemetry row under the meter reports which one is live.

### iOS differences

The phone app is a native product, not a port, so a few Mac behaviours are
deliberately absent rather than disabled:

- **One input and one output.** There is no device picker, rescan or
  device-path summary. iOS routes the system microphone and speaker.
- **No live monitoring.** Playing the microphone back through the phone's
  speaker recaptures itself and feeds back. Analysis does not need it, so the
  iOS app does not monitor at all.
- **Sample playback is gated.** A lesson's guitar sample is heard by the same
  microphone, so detection is suppressed from a sample's start until 150 ms
  past its nominal end (measured on an iPhone 14 Pro Max).
- **Capture uses `AVAudioSinkNode`, not `installTap`.** The tap delivers fixed
  ~100 ms chunks on device; the sink delivers ~23 ms, keeping detection fresh
  (Phase 1 measurement).
- **No Sparkle, no sample-capture tooling, and no DEBUG harness in Release.**
  The Phase 1/3/7 launch-argument views are `#if DEBUG` and absent from a
  release archive.

Store copy and the privacy/support pages live in
[docs/app-store/](docs/app-store/).

## Controls

- **Input / Output** — pick devices independently. Selections are stored by
  the device's stable UID, so unplugging and replugging an interface keeps
  your choice.
- **Monitor** — mute, and level for the playback you hear.
- **Sensitivity** — one dial from strict to lenient. Strict means fewer
  false triggers on a noisy signal; lenient catches weaker and quieter
  notes. It drives two detector thresholds that the UI deliberately doesn't
  expose separately.

## Layout

```
Fretlight/
  Audio/     Core Audio: capture, monitoring, devices, ring buffers
  Pitch/     Pure DSP and logic — no Core Audio: YIN, note mapping, tuning,
             fret-position resolution
  Models/    AppState, the single owner of UI state
  Views/     SwiftUI (Mac)
FretworkIOS/
  Audio/     AVAudioSession/AVAudioEngine capture and sample playback
  Listen/    The phone-first Listen screen and its readouts
  Modules/   One screen per learning module, plus the shared scaffold
  Shell/     Navigation, settings, snapshot harness
  Debug/     DEBUG-only diagnostic writers
```

`CLAUDE.md` holds the working notes: build and smoke-test workflows, and the
decisions worth not rediscovering.
