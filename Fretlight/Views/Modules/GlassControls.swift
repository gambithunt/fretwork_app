import SwiftUI

/// The shared material and motion language for every learning module screen.
///
/// Before this file, each module screen carried its own copy of a "root
/// button" (nine near-identical implementations) with an instant, unanimated
/// colour swap for selection, sat as plain text on the background with no
/// grouping, and gave no audible feedback for a tap that wasn't wired to an
/// explicit Play button. Listen's own panels (`TunerPanel`, `InputLevelPanel`)
/// already had a material — a translucent card, a hairline border, springy
/// content transitions — the module screens just never drew it. This file is
/// that material, factored out once, plus the "gravity" motion (a spring with
/// deliberate overshoot) the fretboard's own dots use, so a selection
/// highlight travelling between chips and a dot landing on the neck read as
/// the same physical system.
enum FretworkMotion {
    /// The spring behind every selection highlight and every dot's arrival —
    /// `Animation.bouncy` verbatim (`spring(duration: 0.5, bounce: 0.3)`),
    /// Apple's own named preset, rather than a hand-tuned approximation of
    /// it. Two hand-tuned passes at this undershot the bounce parameter
    /// (landing around 0.18) trying to tame what was actually a performance
    /// problem elsewhere (see `FretboardBoardView`'s `.drawingGroup()`) —
    /// the curve itself was never the thing making this feel wrong.
    static let gravity = Animation.bouncy
    /// A tighter spring for the momentary press-and-release of a tap.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.55)
}

// MARK: - Glass panel

/// The translucent shell Listen's panels draw: a faint white fill over a
/// hairline border. Every module's controls and readout now draw the same
/// shell, so the screen reads as one instrument rather than text floating
/// directly on the background.
private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var fill: Double = 0.045
    var stroke: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(fill), in: RoundedRectangle(cornerRadius: cornerRadius))
            // A glass highlight must sit over a known dark surface. Without
            // this base, a control group can composite the transparent card
            // against a system light backing layer (most visibly on
            // Harmonizing's stacked controls).
            .background(NotePalette.backdrop, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(stroke), lineWidth: 1))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16, fill: Double = 0.045, stroke: Double = 0.06) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, fill: fill, stroke: stroke))
    }

    /// The shell every module's primary note/key picker sits in — its own
    /// card, held to the same floor height everywhere it appears, so that
    /// card doesn't shift position or size as you move between modules with
    /// different amounts of stuff underneath it. The picker is centred in
    /// the card's vertical space (`alignment: .leading` centres vertically,
    /// keeps the leading edge), so a one-row picker gets equal breathing
    /// room above its title and below its chips rather than all the slack
    /// dumped underneath. The floor is small — just enough that the card
    /// doesn't visibly resize between modules — not a reserve of empty space.
    func moduleNotesCard() -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(18)
            .glassCard()
    }

    /// The shell for everything else a module's controls hold — secondary
    /// pickers, play/stop buttons — as its own card below the notes card.
    /// Full width so the controls can spread across one comfortable row
    /// instead of huddling shrink-wrapped at the left, and a floor height so
    /// a module with a single row of controls sits at the same height as one
    /// with two. Modules that genuinely stack several control sections
    /// (Harmonizing's degree row, Note Association's layers) still grow past
    /// the floor.
    func moduleOptionsCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassCard()
    }
}

// MARK: - Tactile press

/// Elastic Glass's press feedback — a brief compression that springs back —
/// used on every chip and edge-nav control below instead of `.plain`'s flat
/// opacity dim.
struct ElasticPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(FretworkMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Sliding chip picker

/// A wrapping grid of mutually exclusive chips whose fill *travels* between
/// chips on selection — a `matchedGeometryEffect`-driven highlight sliding
/// from the old choice to the new one — instead of the flat, unanimated
/// colour swap every module used to do independently. One component now
/// backs the root/key pickers and the roman-numeral degree rows alike; only
/// the label content and per-chip tint differ between them.
struct ChipPicker<Value: Hashable, Label: View>: View {
    let values: [Value]
    let selection: Value
    /// The chip's own hue: pitch colour for a note picker, a single accent
    /// for a degree row. The label decides its own text colour separately.
    let tint: (Value) -> Color
    let onSelect: (Value) -> Void
    /// An extra lift for a chip that's *also* the thing currently sounding —
    /// Note Association's playing chord — independent of `selection`.
    var isEmphasized: (Value) -> Bool = { _ in false }
    var help: ((Value) -> String?)? = nil
    /// Defaults to reading whatever `Text` the label puts on screen, which is
    /// right for a single-`Text` label (a pitch class). A multi-line label
    /// (a degree chip's roman numeral over its chord name) needs its own,
    /// since VoiceOver would otherwise only pick up one of the two lines.
    var accessibilityLabel: ((Value) -> String)? = nil
    @ViewBuilder var label: (Value, Bool) -> Label

    @Namespace private var glow

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                chip(value)
            }
        }
    }

    private func chip(_ value: Value) -> some View {
        let isActive = value == selection
        let emphasized = isEmphasized(value)
        let color = tint(value)
        // Sound is the model's job, not this component's: `onSelect` already
        // reaches into whichever module model owns the tap, and every one of
        // them now plays the note/chord it just selected. This only owns the
        // visual spring.
        return Button {
            withAnimation(FretworkMotion.gravity) { onSelect(value) }
        } label: {
            label(value, isActive)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    ChipFill(color: color, lit: isActive, emphasized: emphasized)
                        // Only the lit fill travels — an unlit chip has
                        // nothing to hand off from, and giving every chip
                        // the same id would make the namespace ambiguous.
                        .modifier(TravelIfLit(id: "chip-highlight", namespace: glow, lit: isActive))
                )
        }
        .buttonStyle(ElasticPressStyle())
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .modifier(OptionalHelp(text: help?(value)))
        .modifier(OptionalAccessibilityLabel(text: accessibilityLabel?(value)))
    }
}

private struct OptionalAccessibilityLabel: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityLabel(text)
        } else {
            content
        }
    }
}

/// The one lit/unlit fill shared by `ChipPicker`'s sliding highlight and
/// `ToggleChipGrid`'s independent toggles — flat and translucent, with a
/// colour-matched glow standing in for depth rather than a top-to-bottom
/// gradient and an edge glint. The gradient read as a beveled 3D button,
/// which is the opposite of the glass this app draws everywhere else — a
/// fretboard dot is flat colour plus glow too, not a shaded sphere. Only how
/// the *lit* state is reached differs between the two callers (one highlight
/// travelling vs. many toggling independently); the fill itself is the same
/// material either way.
private struct ChipFill: View {
    let color: Color
    let lit: Bool
    var emphasized: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14))
            if lit {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.82))
                    .shadow(color: color.opacity(emphasized ? 0.75 : 0.5), radius: emphasized ? 9 : 6)
            }
        }
    }
}

/// Applies `matchedGeometryEffect` only while lit, so `ChipFill` stays usable
/// by a grid where more than one chip can be lit at once (nothing shared
/// between them to travel) as well as by `ChipPicker`'s single travelling
/// highlight.
private struct TravelIfLit: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let lit: Bool

    func body(content: Content) -> some View {
        if lit {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Independent toggle grid

/// A wrapping grid of chips that toggle *independently* — more than one can
/// be lit at once, unlike `ChipPicker`'s single travelling highlight. Backs
/// Notes' "tap to toggle every position" row, where each of the twelve pitch
/// classes is its own on/off switch rather than one selection among twelve.
struct ToggleChipGrid<Value: Hashable, Label: View>: View {
    let values: [Value]
    let isActive: (Value) -> Bool
    let tint: (Value) -> Color
    let onTap: (Value) -> Void
    var help: ((Value) -> String)? = nil
    var accessibilityValue: ((Value, Bool) -> String)? = nil
    @ViewBuilder var label: (Value, Bool) -> Label

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                chip(value)
            }
        }
    }

    private func chip(_ value: Value) -> some View {
        let active = isActive(value)
        let color = tint(value)
        return Button {
            withAnimation(FretworkMotion.gravity) { onTap(value) }
        } label: {
            label(value, active)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(ChipFill(color: color, lit: active))
        }
        .buttonStyle(ElasticPressStyle())
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .modifier(OptionalHelp(text: help?(value)))
        .modifier(OptionalAccessibilityValue(text: accessibilityValue?(value, active)))
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityValue(text)
        } else {
            content
        }
    }
}

/// `.help(_:)` only accepts a `String`, never an optional — this applies it
/// only when the caller actually has one, so `ChipPicker` can offer a tooltip
/// closure without forcing every caller to supply one.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// The twelve-note picker nearly every module opens its controls with. A
/// thin convenience over `ChipPicker` so the nine near-identical call sites
/// this replaced become one line each.
struct PitchClassPicker: View {
    let title: String
    let selection: PitchClass
    let onSelect: (PitchClass) -> Void
    /// Notes' own note buttons additionally say when a pitch class's every
    /// position is already placed; every other module leaves this nil.
    var help: ((PitchClass) -> String?)? = nil

    private static let values = (0..<12).map(PitchClass.init)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            ChipPicker(
                values: Self.values,
                selection: selection,
                tint: NotePalette.color(for:),
                onSelect: onSelect,
                help: help
            ) { pitchClass, isActive in
                Text(pitchClass.name())
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isActive ? Color.black : NotePalette.color(for: pitchClass))
            }
        }
    }
}

// MARK: - Fretboard navigation

/// A "previous"/"next" row sitting directly above the board it moves, rather
/// than flanking it — the board is the widest thing on any of these screens,
/// so giving up two 32pt columns on either end to reach it was real width the
/// neck could otherwise use. Triads, Chords and Octaves all have a "move this
/// shape up or down the neck" action.
struct FretboardEdgeNav<Board: View>: View {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var previousDisabled = false
    var nextDisabled = false
    @ViewBuilder var board: () -> Board

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if onPrevious != nil || onNext != nil {
                HStack(spacing: 8) {
                    if let onPrevious {
                        navButton(systemImage: "chevron.left", disabled: previousDisabled, action: onPrevious)
                            .help("Move to the previous position")
                    }
                    if let onNext {
                        navButton(systemImage: "chevron.right", disabled: nextDisabled, action: onNext)
                            .help("Move to the next position")
                    }
                }
            }
            board()
        }
    }

    private func navButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(FretworkMotion.gravity) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(ElasticPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

// MARK: - Fret range

/// Lets a board reach past its module's usual ceiling to the full 22-fret
/// neck, without changing what the module teaches — the shape stays the
/// size it is, the neck around it just gets longer. Purely a rendering
/// choice: every module's board already scales to however many frets it's
/// told to draw.
struct FretRangeToggle: View {
    @Binding var isExpanded: Bool
    let defaultFrets: Int

    var body: some View {
        Button {
            withAnimation(FretworkMotion.gravity) { isExpanded.toggle() }
        } label: {
            Label(
                isExpanded ? "To fret \(defaultFrets)" : "Full neck (22)",
                systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            )
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.secondary)
        .help(isExpanded ? "Show only up to fret \(defaultFrets), where this shape lives" : "Show the full 22-fret neck")
    }
}
