# Fretwork

A macOS app for guitarists. It listens to your guitar, plays it back through
whichever speakers or headphones you choose, and shows the note you just
played on a 22-fret fretboard — including which position on the neck it
thinks you actually played it at.

## Requirements

macOS 14 or later, and Xcode with the macOS 14 SDK. Swift 6 with strict
concurrency checking set to `complete`.

## Build and run

```
xcodebuild -project Fretlight.xcodeproj -scheme Fretlight -destination 'platform=macOS' build
```

Run the tests with `test` in place of `build`. Kill any leftover app
process first — one from a previous run can hang the test host's launch
with no useful error:

```
pkill -9 -f "Fretwork.app/Contents/MacOS"
```

**Naming:** the Xcode project, target and scheme are all still called
`Fretlight`, the original name. The product and the Swift module are
`Fretwork`. Tests import `Fretwork`, not `Fretlight`.

## Releasing

Fretwork is distributed from fretwork.org as a signed — but deliberately
un-notarized — disk image, and updates itself with Sparkle.

```
./scripts/build-release.sh build
```

produces `build/Fretwork-<version>.dmg`, an `appcast.xml` carrying the
release's EdDSA signature, and a `version.json` the website reads. Pushing a
`v*` tag runs the same script on CI and publishes the result to R2.

Two separate keys are involved and neither is recoverable:

- **The "Fretwork Code Signing" certificate.** Self-signed, valid to 2046. It
  is what makes the app's designated requirement stable across builds, which
  is what makes a user's microphone permission survive an update. Rotating it
  re-prompts every existing install.
- **The Sparkle EdDSA private key**, in the login keychain under service
  `https://sparkle-project.org`. It signs each release archive. Without it no
  further update can ever be offered to an installed copy.

Neither is in this repo. Back both up outside the machine.

### What users see

The app is not notarized, so the first launch is blocked by Gatekeeper and the
user has to allow it once in System Settings → Privacy & Security. Sparkle
strips the quarantine attribute from updates it installs, so this happens on
first install only, not on every update.

### CI secrets

| Name | What |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | base64 of the signing certificate exported as .p12 |
| `SIGNING_CERTIFICATE_PASSWORD` | that .p12's password |
| `KEYCHAIN_PASSWORD` | any throwaway value; scopes the runner's temp keychain |
| `SPARKLE_PRIVATE_KEY` | output of `generate_keys -x` |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | R2 token with Object Read & Write |
| `CLOUDFLARE_ACCOUNT_ID` | for the R2 S3 endpoint |
| `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_CACHE_PURGE_TOKEN` | to purge the appcast at the edge |

Plus a repository **variable** `R2_BUCKET` naming the bucket.


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
  Views/     SwiftUI
```

`CLAUDE.md` holds the working notes: build and smoke-test workflows, and the
decisions worth not rediscovering.
