import SwiftUI

/// The two useful ways to read a contextual fretboard: the note's literal
/// name, or the job it performs inside the exercise's current harmony.
enum FretboardLabelMode: String, CaseIterable {
    case notes
    case degrees
}

/// Shared compact selector used in each learning screen's options card.
struct FretboardLabelPicker: View {
    @Binding var selection: FretboardLabelMode

    var body: some View {
        Picker("Labels", selection: $selection) {
            Text("Notes").tag(FretboardLabelMode.notes)
            Text("Numbers").tag(FretboardLabelMode.degrees)
        }
        .labelsHidden()
        .fixedSize()
        .help("Show note names or the degrees used by this lesson")
    }
}

extension Array where Element == FretboardDot {
    /// The models retain their degree/interval labels as their teaching
    /// source. This presentation-only transform swaps only labelled dots to
    /// their real pitch names, so deliberately blank context dots stay quiet.
    func showingNoteNames(in tuning: Tuning) -> Self {
        map { dot in
            guard !dot.label.isEmpty, let pitchClass = dot.pitchClass(in: tuning) else { return dot }
            var named = dot
            named.label = pitchClass.name()
            return named
        }
    }
}

/// The frame every learning module renders into, so layout lives in one place.
///
/// The Swift counterpart of `../fretwork/src/lib/components/ModuleLayout.svelte`
/// and its three zones:
///
/// - **controls** — the module's selectors and its play button
/// - **stage** — the hero, almost always the fretboard
/// - **readout** — stats and the theory copy explaining what is on the board
///
/// The web's responsive rules do not come across: they exist because that app
/// is used on a tablet in portrait with a guitar in the way. This is a Mac
/// window with a floor of 950 x 800, so the desktop arrangement is the only
/// arrangement — controls in a wrapping bar, stage full width, readout beneath.
///
/// `../fretwork/AGENTS.md` prescribes this skeleton for every module, and
/// workstream 006's first verified finding is that the Swift equivalent should
/// exist *before* the second module rather than after the fifth.
struct ModuleLayout<Controls: View, Stage: View, Readout: View>: View {
    let module: LearningModule
    let state: AppState
    @ViewBuilder var controls: Controls
    @ViewBuilder var stage: Stage
    @ViewBuilder var readout: Readout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // `controls` now draws its own cards internally — a fixed-size
                // one around the module's note/key picker (`.moduleNotesCard()`)
                // and a second below it for everything else
                // (`.moduleOptionsCard()`), so the note picker holds the same
                // position and size across every module rather than resizing
                // around whatever secondary controls that module happens to
                // have. `readout` still gets one card of its own — the stage
                // keeps its own look (`BoardCanvas` already draws its
                // instrument-body card).
                controls
                stage
                readout
                    // The readout is the interpretation of the full-width
                    // fretboard, not a small sidebar beneath it. Give it the
                    // same horizontal claim as the board and enough room for
                    // its larger teaching type to breathe.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .glassCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NotePalette.backdrop)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(module.title)
                    .font(.largeTitle.weight(.semibold))
                Text(module.blurb)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if state.showsLiveNoteOnModules {
                ModuleLiveNoteReadout(state: state)
            }
        }
    }
}

/// The live Listen readout distilled to its one useful practising cue. This
/// leaf owns the audio-rate `display` read so changing notes does not
/// invalidate the rest of a module's controls, board, or teaching copy.
private struct ModuleLiveNoteReadout: View {
    let state: AppState

    var body: some View {
        let display = state.display
        let noteColor = display.note.map { NotePalette.color(for: $0.name) }
        // iOS playback gate: while a sample the app itself is playing would
        // otherwise be re-captured by the mic, detection is suppressed and the
        // caption swaps to PLAYING. Always false on Mac (input and output are
        // separate devices), so the Mac capsule stays pixel-identical.
        let playing = state.audio.isSuppressingForPlayback

        VStack(spacing: 4) {
            Text(playing ? "PLAYING" : "LISTENING")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Text(display.note.map { "\($0.name)\($0.octave)" } ?? "—")
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .frame(minWidth: 104)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(noteColor?.opacity(0.28) ?? .white.opacity(0.08))
                        .overlay {
                            Capsule()
                                .stroke(noteColor?.opacity(0.52) ?? .white.opacity(0.10), lineWidth: 1)
                        }
                        .shadow(color: noteColor?.opacity(0.26) ?? .clear, radius: 12)
                }
        }
        .animation(.easeInOut(duration: 0.2), value: display.note?.midiNote)
        .animation(.easeInOut(duration: 0.2), value: playing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display.note.map { "Live note \($0.name)\($0.octave)" } ?? "Listening for a note")
    }
}

/// Draws only the live-note feedback layer over a lesson fretboard. Keeping
/// this separate from `FretboardBoardView` means a pitch update redraws this
/// small set of halos, not the board's dots, controls, or teaching copy.
private struct ModuleLiveNoteGlow: View {
    let state: AppState
    let dots: [FretboardDot]
    let frets: Int
    let tuning: Tuning
    let flipped: Bool
    var margins: BoardGeometry.Margins = .labelled

    @ViewBuilder var body: some View {
        // Do not read `display` while the feature is off. Besides making the
        // feature genuinely inert, that removes this view's audio-rate
        // dependency until the player opts in.
        if state.showsLiveNoteOnModules, state.highlightsLiveNoteOnFretboards {
            activeGlow
        }
    }

    private var activeGlow: some View {
        // Keep the layer present while silence arrives so the matching rings
        // leave with the requested brief fade instead of disappearing as a
        // whole overlay in one transaction.
        let note = state.display.note
        return GeometryReader { proxy in
            let geometry = BoardGeometry(
                size: proxy.size,
                frets: frets,
                strings: tuning.openMIDINotes.count,
                flipped: flipped,
                margins: margins
            )
            ZStack {
                if let note {
                    let matchingDots = Self.matching(dots, pitchClass: PitchClass(note.midiNote), tuning: tuning)
                    let color = NotePalette.color(for: note.name)
                    ForEach(matchingDots) { dot in
                        Circle()
                            .strokeBorder(color.opacity(0.72 * dot.alpha), lineWidth: 2)
                            .frame(width: dot.radius * 2 + 8, height: dot.radius * 2 + 8)
                            .shadow(color: color.opacity(0.78 * dot.alpha), radius: 9)
                            .position(geometry.point(dot.position))
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: note?.midiNote)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func matching(_ dots: [FretboardDot], pitchClass: PitchClass, tuning: Tuning) -> [FretboardDot] {
        dots.filter { $0.pitchClass(in: tuning) == pitchClass }
    }
}

extension View {
    /// Adds live-note feedback to a lesson board without handing the board an
    /// audio-rate dependency. The active dot model stays the sole authority
    /// on which lesson positions are visible; this layer merely decorates the
    /// visible positions that match the detected pitch class.
    func moduleLiveNoteGlow(
        state: AppState,
        dots: [FretboardDot],
        frets: Int,
        tuning: Tuning,
        flipped: Bool,
        margins: BoardGeometry.Margins = .labelled
    ) -> some View {
        overlay {
            ModuleLiveNoteGlow(
                state: state,
                dots: dots,
                frets: frets,
                tuning: tuning,
                flipped: flipped,
                margins: margins
            )
        }
    }
}

/// A labelled row of mutually exclusive choices — the shape the web gets from
/// `ButtonGroup`.
///
/// The web uses buttons rather than a dropdown because that app is driven by
/// touch with a guitar in your hands, and workstream 006 records explicitly that
/// this is a product constraint which *does not transfer*. So this is a real
/// macOS `Picker`, in menu style.
///
/// Never `.pickerStyle(.segmented)`: `CLAUDE.md` records a measured leak of
/// ~1800 `ObservationRegistrar` contexts per 30 s when a segmented picker is
/// rebuilt at audio rate. Modules do not currently rebuild that fast, but they
/// will once workstream 007 puts live detection on these screens, and the leak
/// grows with uptime rather than announcing itself.
struct ModulePicker<Value: Hashable, Label: View>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    @ViewBuilder var label: (Value) -> Label

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    label(value).tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// One figure with its caption — the web's `.stat-grid` cell.
// MARK: - Control card

/// One labelled cell in a module's control card: a small caps caption above
/// the control, in the same style the ROOT/KEY picker captions already use.
///
/// This is the owner-driven fix for controls that used to bunch on the left:
/// every control — menu pickers, toggle chips, the primary action — is now a
/// cell with its own caption, and the cells share the card width evenly
/// instead of huddling shrink-wrapped at the leading edge.
struct ModuleControlCell<Content: View>: View {
    let caption: String
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: 7) {
            Text(caption.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

extension View {
    /// Wraps a control in a labelled cell so call sites read as one line each.
    func moduleControlCell(caption: String, alignment: HorizontalAlignment = .leading) -> some View {
        ModuleControlCell(caption: caption, alignment: alignment) { self }
    }
}

/// The one primary action a module owns (Play/Strum/Practise/Play interval/…).
///
/// It always sits in the *last* cell, at the card's trailing edge, at one
/// consistent size — the owner noticed it changing size and position between
/// modules. Its Stop sits right beside it in the same cell, so the two are one
/// fixed unit rather than two buttons that drift apart.
struct ModulePrimaryAction: View {
    let title: String
    var systemImage: String = "play.fill"
    var disabled: Bool = false
    let action: () -> Void
    let stopAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    // A button label never wraps: its measured width is the
                    // full one-line label, so the flow layout moves the whole
                    // action group to a new row when it doesn't fit instead
                    // of squeezing "Play progression" onto two lines.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 132)
            }
            .modulePrimaryButton()
            .disabled(disabled)

            Button(action: stopAction) {
                Label("Stop", systemImage: "stop.fill")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .moduleSecondaryButton()
        }
    }
}

/// A secondary action — Stop, Loop, Strum chord, Anticlockwise/Clockwise,
/// Full neck — rendered as a plain glass capsule on iPad, the native bezel on
/// the Mac.
struct ModuleSecondaryAction: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .primary
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .moduleSecondaryButton(tint: tint)
        }
        .disabled(disabled)
    }
}

/// The card shell every module's labelled control cells live in. Cells flow
/// left-to-right into rows, each cell kept at its measured natural width and
/// the row's leftover space distributed *between* cells (justified), so rows
/// stay evenly spread and a chip group never wraps inside a cell that was
/// made wider than the chips need. A cell that doesn't fit moves to the next
/// row whole; the primary action, always the last cell, ends its row at the
/// card's trailing edge. A `.moduleControlFullWidth()` cell spans a whole row.
/// The `.spread` distribution keeps Notes' action row — Play/Stop leading,
/// Clear all trailing, the middle empty — as its own deliberate exception.
struct ModuleControlCard<Content: View>: View {
    enum Distribution {
        case balanced
        case spread
    }

    var distribution: Distribution = .balanced
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            switch distribution {
            case .balanced:
                ModuleControlFlowLayout { content }
            case .spread:
                ModuleSpreadLayout { content }
            }
        }
        .moduleOptionsCard()
    }
}

/// Marks a cell as spanning its own full-width row, instead of sharing a row
/// with its neighbours.
private struct ModuleFullWidthKey: LayoutValueKey {
    static let defaultValue = false
}

/// Marks a cell as *starting* a new row while keeping its natural width and
/// flowing with the cells after it — the degree-chip row in Harmonizing and
/// Note Association, which always begins its own row but shares it with the
/// progression and primary action.
private struct ModuleRowBreakKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func moduleControlFullWidth() -> some View {
        layoutValue(key: ModuleFullWidthKey.self, value: true)
    }

    func moduleControlRowBreak() -> some View {
        layoutValue(key: ModuleRowBreakKey.self, value: true)
    }
}

/// Natural-width flow: pack as many cells onto each row as fit by their
/// measured ideal widths (full-width cells force a row break), then keep every
/// cell at its natural width and distribute the row's leftover space *between*
/// cells, justified. Nothing grows beyond its content — a chip group's cell is
/// exactly as wide as its chips, so the chips stay one line and the whole cell
/// moves to the next row when it doesn't fit. The primary action is always the
/// last cell, so the card's last row — shared or alone — ends at the trailing
/// edge.
struct ModuleControlFlowLayout: Layout {
    var hSpacing: CGFloat = 14
    var vSpacing: CGFloat = 14

    struct Cache {
        var rows: [[Int]]
        var rowWidths: [[CGFloat]]
        var rowHeights: [CGFloat]
        var rowGaps: [CGFloat]
        var totalHeight: CGFloat
    }

    func makeCache(subviews: Subviews) -> Cache {
        compute(subviews: subviews, width: nil)
    }

    private func idealWidth(_ subview: LayoutSubview) -> CGFloat {
        max(1, subview.sizeThatFits(.unspecified).width)
    }

    private func compute(subviews: Subviews, width: CGFloat?) -> Cache {
        guard !subviews.isEmpty else {
            return Cache(rows: [], rowWidths: [], rowHeights: [], rowGaps: [], totalHeight: 0)
        }
        let available = width ?? .infinity

        // Greedy row packing by ideal widths; a full-width cell ends the row
        // and gets a row to itself.
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            // A full-width cell gets a row to itself; a row-break cell flushes
            // the current row and then flows normally at its natural width.
            if subview[ModuleFullWidthKey.self] || subview[ModuleRowBreakKey.self] {
                if !current.isEmpty { rows.append(current); current = []; currentWidth = 0 }
                if subview[ModuleFullWidthKey.self] {
                    rows.append([index])
                    continue
                }
            }
            let ideal = idealWidth(subview)
            let added = ideal + (current.isEmpty ? 0 : hSpacing)
            if available.isFinite, !current.isEmpty, currentWidth + added > available {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(index)
            currentWidth += (current.count == 1 ? ideal : ideal + hSpacing)
        }
        if !current.isEmpty { rows.append(current) }

        var rowWidths: [[CGFloat]] = []
        var rowHeights: [CGFloat] = []
        var rowGaps: [CGFloat] = []
        var totalHeight: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let isFullWidthRow = row.count == 1 && subviews[row[0]][ModuleFullWidthKey.self]
            var widths: [CGFloat] = []
            var height: CGFloat = 0

            if isFullWidthRow {
                let w = available.isFinite ? available : idealWidth(subviews[row[0]])
                widths = [w]
                height = subviews[row[0]].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            } else {
                for index in row {
                    let w = idealWidth(subviews[index])
                    widths.append(w)
                    height = max(height, subviews[index].sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
                }
            }

            // Leftover space goes between the cells, never into them. A
            // two-cell row that is not the last row packs left with normal
            // spacing — justifying it would pin its two cells to opposite
            // ends. The last row (the primary action) and rows of three or
            // more justify, so the action still ends at the trailing edge.
            let isLastRow = rowIndex == rows.count - 1
            let justify = row.count >= 3 || (isLastRow && row.count >= 2)
            let gap: CGFloat
            if !isFullWidthRow, justify, available.isFinite {
                let used = widths.reduce(0, +) + hSpacing * CGFloat(row.count - 1)
                gap = hSpacing + max(0, available - used) / CGFloat(row.count - 1)
            } else {
                gap = hSpacing
            }

            rowWidths.append(widths)
            rowHeights.append(height)
            rowGaps.append(gap)
            totalHeight += height
        }
        totalHeight += vSpacing * CGFloat(max(0, rows.count - 1))

        return Cache(rows: rows, rowWidths: rowWidths, rowHeights: rowHeights, rowGaps: rowGaps, totalHeight: totalHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let computed = compute(subviews: subviews, width: proposal.width)
        cache = computed
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            width = computed.rowWidths.enumerated().reduce(CGFloat(0)) { widest, pair in
                let (index, row) = pair
                let rowWidth = row.reduce(0, +) + computed.rowGaps[index] * CGFloat(max(0, row.count - 1))
                return max(widest, rowWidth)
            }
        }
        return CGSize(width: width, height: computed.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let computed = compute(subviews: subviews, width: bounds.width)
        cache = computed
        var y = bounds.minY
        for (rowIndex, row) in computed.rows.enumerated() {
            let isFullWidthRow = row.count == 1 && subviews[row[0]][ModuleFullWidthKey.self]
            // A lone cell on the last row is the trailing primary action.
            let isLoneTrailingCell = row.count == 1 && rowIndex == computed.rows.count - 1
            var x = bounds.minX
            if isLoneTrailingCell, !isFullWidthRow {
                x = bounds.maxX - computed.rowWidths[rowIndex][0]
            }
            for (position, index) in row.enumerated() {
                let cellWidth = computed.rowWidths[rowIndex][position]
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellWidth, height: computed.rowHeights[rowIndex])
                )
                x += cellWidth + computed.rowGaps[rowIndex]
            }
            y += computed.rowHeights[rowIndex] + vSpacing
        }
    }
}

/// Space-between flow for Notes' action row: the first cell leading, the last
/// cell trailing, anything between distributed across the gap.
struct ModuleSpreadLayout: Layout {
    var hSpacing: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = (proposal.width ?? 0).isFinite && (proposal.width ?? 0) > 0
            ? proposal.width!
            : sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, subviews.count - 1)) * hSpacing
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0

        if subviews.count == 1 {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: sizes[0].width, height: height))
            return
        }

        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: sizes[0].width, height: height))
        let last = subviews.count - 1
        subviews[last].place(at: CGPoint(x: bounds.maxX - sizes[last].width, y: bounds.minY), anchor: .topLeading,
                             proposal: ProposedViewSize(width: sizes[last].width, height: height))

        if subviews.count > 2 {
            let firstRight = bounds.minX + sizes[0].width
            let lastLeft = bounds.maxX - sizes[last].width
            let slot = (lastLeft - firstRight) / CGFloat(subviews.count - 1)
            for i in 1..<last {
                let x = firstRight + slot * CGFloat(i) - sizes[i].width / 2
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: sizes[i].width, height: height))
            }
        }
    }
}

/// Lays fixed-size chips (layer toggles, rotation buttons) on a single line at
/// their natural widths. Chips never wrap inside their cell: the control
/// card's flow layout measures this cell's full one-line width and moves the
/// whole cell to the next row when it does not fit.
struct ModuleChipRowLayout: Layout {
    var hSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(max(0, subviews.count - 1)) * hSpacing
        let height = sizes.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + hSpacing
        }
    }
}

// MARK: - Platform control styles

/// The one place a module control decides its platform look.
///
/// The Mac keeps its `.borderedProminent` primary and native bezel/popup for
/// everything else — the owner likes the current Mac look. iPad landscape
/// hosts these same Mac screens unchanged (`IOSModuleScreen.usesMacLayout`),
/// so *only there* do the controls need Liquid Glass (D-23): a tinted glass
/// capsule for the primary action, a plain glass capsule for menu pickers and
/// secondary actions. iPhone never instantiates these views (it uses the iOS
/// scaffold), so `#if os(iOS)` is exactly "iPad" in practice.
extension View {
    /// The primary action as a tinted Liquid Glass capsule on iPad, the
    /// established prominent button on the Mac.
    @ViewBuilder
    func modulePrimaryButton() -> some View {
        #if os(iOS)
        self.buttonStyle(ModuleGlassPrimaryButtonStyle())
        #else
        self.buttonStyle(.borderedProminent).tint(NotePalette.accent)
        #endif
    }

    /// A secondary action as a plain glass capsule on iPad; identity on the
    /// Mac, which already draws a native bezel for an unstyled `Button`.
    @ViewBuilder
    func moduleSecondaryButton(tint: Color = .primary) -> some View {
        #if os(iOS)
        self.buttonStyle(ModuleGlassSecondaryButtonStyle(tint: tint))
        #else
        self
        #endif
    }

    /// A menu picker as a plain glass capsule on iPad; identity on the Mac,
    /// which already draws a native popup.
    @ViewBuilder
    func moduleMenuPicker() -> some View {
        #if os(iOS)
        self
            .tint(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(in: .capsule)
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Tinted Liquid Glass capsule for the primary action: a faint accent wash
/// under a glass capsule with accent icon/text. `NotePalette.accent` on the
/// dark backdrop is ~7.7:1 contrast, comfortably past the 4.5:1 floor, and it
/// replaces `.glassProminent`'s full mint fill which overpowered every screen.
struct ModuleGlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(NotePalette.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(NotePalette.accent.opacity(0.12), in: Capsule())
            .glassEffect(in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(FretworkMotion.press, value: configuration.isPressed)
    }
}

/// Plain Liquid Glass capsule for secondary actions.
struct ModuleGlassSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(FretworkMotion.press, value: configuration.isPressed)
    }
}
#endif

struct ModuleStat: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
                // The value changes as the player interacts; without this a
                // digit appearing re-lays-out the row around it.
                .contentTransition(.numericText())
        }
        .frame(minWidth: 112, alignment: .leading)
    }
}

/// The theory copy under the stage. Prose, deliberately: this is the part that
/// teaches, and the web keeps it as paragraphs rather than bullet fragments.
struct ModuleProse: View {
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 900, alignment: .leading)
    }
}

/// Platform wording for the "samples not ready" notice. iOS has no device
/// picker, so its message names the real readiness signal (the sample library
/// and a running graph) instead of an audio device.
enum ModuleAudioNoticeWording {
    static let notReady: String = {
        #if os(iOS)
        "Notes will not sound until audio is ready."
        #else
        "Notes will not sound until an audio device is connected — choose one in Settings."
        #endif
    }()
}

/// Shown on a module when a tap would produce no sound.
///
/// Exists because the first two modules shipped silently broken: every tap
/// called into a playback path that was never initialised, and there was
/// nothing on screen — or in a log — to say so. A module that cannot make a
/// sound should say which of the two reasons applies rather than leaving the
/// player wondering whether they mis-tapped.
struct ModuleAudioNotice: View {
    let isReady: Bool
    let error: String?

    var body: some View {
        if let error {
            notice(
                "The bundled note library could not be loaded, so notes cannot play. \(error)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        } else if !isReady {
            notice(
                ModuleAudioNoticeWording.notReady,
                systemImage: "speaker.slash.fill",
                tint: .secondary
            )
        }
    }

    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .fixedSize(horizontal: false, vertical: true)
    }
}
