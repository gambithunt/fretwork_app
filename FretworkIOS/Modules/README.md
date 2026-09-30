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
    @State private var model: IntervalsModuleModel?

    var body: some View {
        Group {
            if let model {
                IOSIntervalsStage(state: state, model: model)
            } else {
                Color.clear.task {
                    if model == nil {
                        model = state.makeIntervalsModuleModel()
                        state.refreshSamplePlaybackReadiness()
                    }
                }
            }
        }
        .background(NotePalette.backdrop)
    }
}
```

The screen wraps the shared `IOSModuleScaffold` (`IOSModuleScaffold.swift`) —
the **one** primitive for both orientations, not ten one-offs:

- **top row (landscape)** — glass back, title + subtitle, optional
  standard-tuning pill (`isFixedShapeModule: true` for
  Chords/Pentatonic/Harmonizing), live-note leaf. Portrait keeps the native
  nav bar (back, title, gear) and renders the subtitle + live note under it.
- **neck** — `@ViewBuilder`; almost always `FretboardBoardView`. In portrait
  the scaffold puts it in a horizontal scroll strip sized by `frets` and
  auto-scrolled to `focusFret` (D-06 — legible, not shrunk).
- **companion** — `@ViewBuilder` (default `EmptyView`); Circle's ring, drawn
  leading of the board in landscape and above the strip in portrait (D-28).
- **bottom band** — two optional corner controls (`leadingAction`/
  `trailingAction`, each an `IOSModuleBandAction`) around the centre drawer
  button (landscape only), or (during a guided run) ■ Stop + the current step
  (`bandMode`, `guidedRunStepText`, `onStopGuidedRun`).

  The corner slots are one API, not two:

  ```swift
  // Position-stepping modules: the ‹ › arrows.
  leadingAction: .step(systemImage: "chevron.left",
                       accessibilityLabel: "Previous position",
                       disabled: isPrevDisabled,
                       action: { model.move(by: -1) }),
  trailingAction: .step(systemImage: "chevron.right",
                        accessibilityLabel: "Next position",
                        disabled: isNextDisabled,
                        action: { model.move(by: 1) }),

  // Icon actions (Notes' Clear / Play all, Triads Paths' play / stop):
  //   .step(systemImage: "trash", accessibilityLabel: "Clear all notes", ...)

  // A labelled primary action with no trailing control (Scales' ▶ Practise):
  leadingAction: IOSModuleBandAction(title: "Practise",
                                     systemImage: "play.fill",
                                     accessibilityLabel: "Practise",
                                     disabled: ...,
                                     action: { model.startGuided() }),
  trailingAction: nil,
  ```

  A `nil` corner is simply not drawn; a non-nil `title` renders the labelled
  prominent button, a `nil` title renders the icon-only glass circle.
- **drawer** — your `@ViewBuilder`. In landscape it is a native Liquid Glass
  sheet (medium/large detents, system grabber); in portrait the same view is
  rendered inline below the band as the scrolling page (no sheet, no duplicate
  content definitions).

Then register the screen in `IOSModuleScreen.swift` — add the `content` switch
case (and, if it ever stops being exhaustive, the `hasScaffold` case). All ten
modules now have a screen; the Mac screens are no longer used on iOS and the
"coming soon" placeholder is unused.

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

Add a `-IOSSnapshot<Name>Landscape`, `-IOSSnapshot<Name>Drawer`,
`-IOSSnapshot<Name>Portrait` (and, for guided-run modules,
`-IOSSnapshot<Name>Guided`) to `FretworkIOS/Shell/IOSSnapshotHarness.swift` so
each surface can be captured deterministically. Portrait scenarios set
`moduleScenario` without adding the case to `forcesLandscape`, so the
simulator's default portrait orientation wins.
