# iOS learning modules

Every learning module on iOS reuses the Mac's model + portrait screen and adds
a landscape layout via one shared primitive. This file is the recipe, so the
next module follows the same pattern instead of inventing a tenth variant.

## The pattern

Each module gets **two files** (plus tests for any extracted wording):

1. `Fretlight/Models/<Name>ModuleModel.swift` — the rules. Already exists and
   is shared; never fork it. Create it through `AppState`'s factory
   (`state.make<Name>ModuleModel()`), which wires playback and persistence.
2. `FretworkIOS/Modules/IOS<Name>Screen.swift` — the iOS surface.

The iOS surface is a thin wrapper:

```swift
struct IOSIntervalsScreen: View {
    @Bindable var state: AppState
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var landscapeModel: IntervalsModuleModel?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                if let model = landscapeModel {
                    IOSIntervalsLandscape(state: state, model: model)
                } else {
                    Color.clear.task {
                        if landscapeModel == nil {
                            landscapeModel = state.makeIntervalsModuleModel()
                            state.refreshSamplePlaybackReadiness()
                        }
                    }
                }
            } else {
                IntervalsModuleScreen(state: state)   // Mac portrait fallback (D-18)
            }
        }
        .background(NotePalette.backdrop)
    }
}
```

The landscape view wraps the shared `IOSModuleLandscapeScaffold`
(`IOSModuleLandscapeScaffold.swift`) — the **one** primitive, not ten one-offs:

- **top row** — glass back, title + subtitle, optional standard-tuning pill
  (`isFixedShapeModule: true` for Chords/Pentatonic/Harmonizing), live-note
  leaf.
- **neck** — `@ViewBuilder`; usually `FretboardBoardView`. Circle passes its
  ring + small triad board instead.
- **bottom band** — leading/trailing ‹ › corner controls, centre drawer button,
  or (during a guided run) ■ Stop + the current step (`bandMode`,
  `guidedRunStepText`, `onStopGuidedRun`).
- **drawer** — a native Liquid Glass sheet (medium/large detents, system
  grabber). Content is your `@ViewBuilder`; the scaffold adds the dark scheme
  and accent tint.

Then register the screen in `IOSModuleScreen.swift` (the dispatch switch and the
`hasScaffold` list) — that is what turns the list's "coming soon" placeholder
into the real module.

## Rules that must not be re-litigated

- **D-22 margins** live in the scaffold: 12 pt top, 16 pt side, 12 pt bottom.
  Don't add your own.
- **Nav bar (landscape pop jump).** The bar stays present but empty/transparent
  in landscape (`iosModuleNavigationBar`), and `IOSModuleScreen` applies it.
  Never toggle nav-bar visibility in a module screen.
- **Audio-rate reads** stay in the leaves (`IOSModuleLiveNoteLeaf`). A module
  screen's body must not read `state.display`/`chordDisplay`/history.
- **Silently-mute guard.** Any Play/Strum button is `disabled` until
  `state.isSamplePlaybackReady`, with `IOSModulePlaybackNotice(state:)` shown.
- **Fixed-shape modules** (Chords, Pentatonic, Harmonizing) pass
  `isFixedShapeModule: true` and draw their board in `Tunings.standard`, never
  the global tuning — those frets detune rather than transpose.
- **Subtitles and step text** are spelled in `IOSModuleLandscapeFormat`, not
  inline, and unit-tested in `FretworkIOSTests/IOSModuleLandscapeTests.swift`.

## Screenshot scenarios

Add a `-IOSSnapshot<Name>Landscape`, `-IOSSnapshot<Name>Drawer` (and, for
guided-run modules, `-IOSSnapshot<Name>Guided`) to
`FretworkIOS/Shell/IOSSnapshotHarness.swift` so the landscape surface can be
captured deterministically. See the existing `intervals`/`pentatonic`/`circle`
scenarios for the shape.
