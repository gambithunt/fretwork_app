# App Store listing — Fretwork (iOS)

Draft copy for App Store Connect. Each field is labelled with its Apple
character limit so it can be pasted in without re-counting. Bundle ID is
`org.fretwork.app.ios`; the public product name is **Fretwork**.

## Name

```
Fretwork
```

## Subtitle (≤ 30)

```
Play guitar, see the fretboard
```

Length: 30.

## Promotional text (≤ 170)

```
Point your phone at your guitar and watch every note land on the fretboard. Ten bite-sized lessons explain why. Analysed on your device — no account, no subscription.
```

Length: 166 of 170.

## Description (≤ 4000)

```
Fretwork turns your phone into a guitar teacher that can hear you.

Hold your phone near the guitar and play. Fretwork listens through the
built-in microphone, works out the pitch on the device, and lights the note on
a 22-fret fretboard — including which position on the neck you most likely
played it at. Strum a chord and it names that too.

Nothing is recorded, stored, or sent anywhere. The microphone audio is
analysed in memory and thrown away.

WHAT YOU GET FOR FREE
• Listen — live note and chord detection with a tuner, level meter and
  position-aware fretboard.
• Notes on the fretboard — the foundation lesson: where every note lives.

ONE-TIME UNLOCK
A single one-time purchase opens the other nine learning modules. There is no
subscription and nothing renews.

• Intervals — the distance between two notes, the building block of theory.
• Octaves — find the same note higher up the neck.
• Triads — three notes stacked in 3rds; how chords are actually built.
• Major, minor & power chords — movable shapes traced back to their root.
• Pentatonic scales — five positions with clear root indicators.
• Scales — major and minor shapes and the intervals that define them.
• Harmonizing the scale — build the chords of a key by stacking scale tones.
• Note association — the chord, the shape to solo with and the scale, one key.
• Circle of fifths — how all the keys relate.

Every lesson plays real guitar samples, shows the shape on the board, and lets
you practise it while Fretwork listens.

WHAT FRETWORK IS NOT
• No account and no sign-in.
• No subscription and no ads.
• No tracking, analytics or advertising identifiers.
• No audio leaves your device. Ever.

Built for guitarists who want to understand the neck, not just play along.

Requirements: iPhone or iPad running iOS/iPadOS 26 or later.

Privacy policy: https://fretwork.org/privacy
Support: https://fretwork.org/support
```

Length: 1,898 of 4,000 (verified with a character count before upload).

## Keywords (≤ 100, comma-separated, no spaces)

```
learn,chords,scales,tuner,practice,music,theory,notes,intervals,pentatonic
```

Length: 74. No word is repeated from the name ("Fretwork") or subtitle ("Play
guitar, see the fretboard").

## Category

- Primary: **Music**
- Secondary: **Education**

## Age rating

Answer **None** to every content-flag question in App Store Connect (no
violence, sexual content, profanity, drugs, gambling, horror, mature themes or
user-generated content). No unrated web content is embedded. Resulting rating:
**4+**.

## App privacy (nutrition label)

**Data Not Collected.**

No tracking. No data is linked to the user and no data is used to track them.
The iOS app has no analytics, no advertising SDKs and no account system; the
microphone audio is analysed on-device and discarded. The bundle ships a
`PrivacyInfo.xcprivacy` with an empty `NSPrivacyCollectedDataTypes` array.

The Mac build has an optional anonymous usage pulse, but that build is not
distributed through the App Store and the iOS app cannot reach the endpoint
(see `FretworkIOS/Settings/IOSSettingsSheet.swift` and the `#if os(macOS)`
guards in `AppState`).

## In-app purchase

Type: **Non-consumable**. It unlocks the nine learning modules on the same
Apple ID, forever.

- **Display name (≤ 30):**

  ```
  All Learning Modules
  ```

- **Description (≤ 45):**

  ```
  Unlock the nine advanced guitar lessons
  ```

- **Price:** Tier for **US$6.99**.

The free tier is Listen and Notes; the paid unlock is the other nine. Restore
Purchases must be reachable from the paywall and from Settings.

## Review notes for Apple

```
Fretwork listens to the guitar through the device microphone and analyses the
audio entirely on-device. It never records or transmits audio.

To test the core flow:
1. Launch the app. It opens on the Listen screen.
2. Tap Start (or the microphone prompt) and allow microphone access when
   asked. Denying it shows a recovery message and a link to Settings.
3. Play a single note — hum or pluck near the phone works — and the note and
   fretboard position appear. Play several notes; a sustained chord is also
   detected.
4. Open "Notes on the fretboard" from the list. This lesson is free.
5. Open any other lesson. The paywall appears. The purchase is a single
   non-consumable ("All Learning Modules"). A StoreKit sandbox account unlocks
   it; "Restore Purchases" is on the paywall and in Settings.

No account or sign-in is required. There is no server component for the core
experience. If a review device has no microphone input, a note played into the
built-in mic on the simulator is not required — the app can also be tested by
tapping a lesson's Play control to hear bundled samples, though live detection
needs microphone access.
```

## Pre-upload checklist

- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped in
      `project.pbxproj` (iOS target).
- [ ] `Config/Info-iOS.plist`: `ITSAppUsesNonExemptEncryption = false`.
- [ ] `PrivacyInfo.xcprivacy` present in the iOS bundle (see the scaffold test).
- [ ] Screenshots at the required iPhone and iPad sizes.
- [ ] IAP created in App Store Connect with the same product ID the app uses.
- [ ] Privacy policy and support pages live at the two `fretwork.org` URLs.
