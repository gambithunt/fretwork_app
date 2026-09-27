# Workstream 008: Live-Note Chip Feedback

## Objective

Give the live-note readout on learning tabs the feeling of a quiet instrument
responding to a played note: immediate, warm, and confidence-building, without
turning a small status indicator into a competing visual event.

This document is a design and implementation brief for another model. It
describes the intended result and the constraints that protect it. It contains
no implementation code.

## Required outcome

- The readout has one stable label, **LISTENING**, above the note capsule.
- The detected note name and octave are the single visual focus: large, bold,
  and optically centered inside the capsule.
- The capsule, not a separate dot, carries the note's pitch-class color.
- Detection arrives as a soft color bloom and leaves as a soft return to the
  neutral material. It must feel responsive, not flashy.
- The readout remains compact enough to live at the upper-right of every
  learning module header.
- Frequent pitch updates affect only this leaf view, never the surrounding
  lesson layout, controls, or fretboard.

## Non-goals

- A level meter, tuner, cents gauge, pulse animation, or a second explanation
  of the detected note.
- Making the capsule look like a tappable button.
- A saturated full-color badge, rainbow effect, continuous breathing loop, or
  animation that suggests a sustained note when none is present.
- Changing pitch detection, tuning logic, or the global setting that controls
  whether the readout appears on learning tabs.

## Desired feeling

The component should feel like a small piece of dark glass catching the color
of the string that was just played. The player should register the result in a
glance: *the app heard me; this is the note.*

The emphasis is on **arrival**, not spectacle. Color should appear as if it
gently fills the material from within, then settle. When detection ends, the
color should recede without looking like an error or a reset. The static
LISTENING label makes the component feel continuously attentive even while the
capsule is neutral.

## Constraint register

| ID | Constraint | Status | Strength | Source | Rationale |
| --- | --- | --- | --- | --- | --- |
| C-01 | Put LISTENING above the capsule and keep it stable in every state. | Accepted | Hard | User | A stable label is calmer and clearer than swapping between LISTENING and LIVE NOTE. |
| C-02 | Remove the separate color dot. | Accepted | Hard | User decision | The colored capsule already communicates pitch class; the dot duplicates it and steals horizontal space. |
| C-03 | Make the note roughly twice the previous size and center it in the capsule. | Accepted | Hard | User | The detected note is the primary glanceable cue. |
| C-04 | Use the detected note's palette color as a subtle capsule tint that fades in and out. | Accepted | Hard | User | The tint creates the desired responsive-instrument feeling. |
| C-05 | Preserve a dark, restrained visual language. | Inferred | Soft | Existing module headers and user reaction | A solid bright badge would overpower the lesson title and board. |
| C-06 | Keep live audio-rate observation isolated to the readout leaf. | Accepted | Hard | Existing architecture | Pitch changes must not invalidate the wider module layout. |
| C-07 | Provide the same meaning to assistive technology. | Accepted | Hard | Existing accessibility behavior | A visual tint must not be the sole statement of detected pitch. |

## Selected direction: Quiet color bloom

### Composition

1. Place a small uppercase **LISTENING** label above the capsule. It is muted,
   letter-spaced, and never changes text when a note arrives.
2. Center the note label and octave together in the capsule. Treat `C#3` and
   `G3` as centered strings, not as left-aligned data in a status row.
3. Give the note a large, bold rounded face with stable digit width for the
   octave. The note should read at a glance from the center of the lesson.
4. Use a neutral translucent dark/white-on-dark capsule when there is no
   detected note. It remains present but quiet, showing an em dash rather than
   an empty or collapsing shape.
5. On detection, tint the capsule with the established pitch-class color at
   low opacity. Add only a very soft matching edge and diffuse glow. The note
   text stays high contrast; do not color it so strongly that it loses clarity.

### State and motion contract

| State | Capsule | Text | Motion | Intended read |
| --- | --- | --- | --- | --- |
| No stable note | Neutral dark glass; faint border; no colored glow. | Large muted em dash. | Settle quietly to neutral. | “I am listening.” |
| Stable note arrives | Pitch-class tint, fine colored rim, soft nearby glow. | Large centered note and octave. | One short, smooth ease-in. | “I heard this note.” |
| Different stable note | Tint moves directly to the next pitch color. | Content changes without layout shift. | Short crossfade/settle; no bounce. | “The pitch changed.” |
| Detection disappears | Return to neutral glass. | Em dash. | Same short ease-out. | “Still listening.” |

Use a single controlled transition around 180–220 ms. It should be long enough
to read as a fade and short enough to track normal guitar playing. Animate
state changes only; never run a looping pulse. If the detector reports a rapid
sequence of notes, each update may interrupt the preceding fade and settle
toward the newest state. Do not queue or replay old transitions.

### Material limits

- The tint should be translucent, roughly a quarter-strength color rather than
  a flat full-color fill.
- The outline may be a little stronger than the fill, but should still read as
  glass catching light—not as a selected control.
- The glow must be diffuse and low contrast. It supports peripheral recognition
  of a new note but must not compete with lit notes on the fretboard.
- The neutral state needs enough visible material to retain the component's
  footprint, preventing header layout from seeming to flicker or change width.

### Deliberate removals

- No leading note-color dot.
- No LIVE NOTE label beneath the value.
- No duplicate color swatch, meter, musical-note icon, or instruction text.
- No scale, spring bounce, or high-frequency flash on every detection update.

## Component boundary

The readout belongs in the shared module header so every learning tab behaves
identically. It should consume the existing detected note display and existing
pitch-class palette; it must not create a parallel detection or color system.

Keep the view as the only header child that reads the audio-updated display.
The parent header, module controls, explanatory copy, and fretboard should not
be re-evaluated merely because a player changes notes. This is both a
performance constraint and a visual one: a note change must feel like an
internal light change, not a rearrangement of the page.

The accessibility name must continue to state either “Listening for a note” or
“Live note {name}{octave}.” The static visible label and color are supporting
cues, not the only semantic output.

## Validation plan

| Scenario | What to inspect | Success signal | Failure signal |
| --- | --- | --- | --- |
| Silence on opening a learning tab | Neutral state and header geometry | Capsule is calm, visible, and does not look disabled. | Empty gap, flashing placeholder, or changing header width. |
| Single sustained note | Arrival and settled state | A brief color bloom resolves into a readable note. | Bright badge, unnecessary pulse, or delayed note. |
| Scale played at normal tempo | Interrupted transitions | Latest note always wins; motion feels continuous. | Queued animations, flicker, strobing, or stale color. |
| Rapid/noisy detection | Restraint under imperfect input | Component stays readable and does not dominate the fretboard. | Repeated bouncing or distracting glow. |
| Sharp/flat note names and multiple octaves | Optical centering and width | `C#3`, `Bb3`, and `G3` remain centered without resizing the header. | Left drift, clipping, or capsule width jumping. |
| Live note preference off | Feature boundary | Readout is absent and no audio-rate visual work is performed there. | Empty reserved space or hidden animation work. |
| VoiceOver | Semantic equivalence | Current detected pitch is announced clearly. | Color is the only indication of the note. |

## Decision log

| Date | Decision | Rationale |
| --- | --- | --- |
| 2026-09-02 | Use the capsule itself as the pitch-color carrier. | It removes redundant decoration and gives the note a clearer center stage. |
| 2026-09-02 | Keep LISTENING stable above the capsule. | It communicates ongoing attention without competing with the note value. |
| 2026-09-02 | Use a short non-looping color fade. | The desired feeling is responsive and musical, not animated for its own sake. |

## Implementation completion criteria

Another model may consider this work complete only when the shared learning-tab
readout follows the composition and state contract above, remains stable under
rapid real-note changes, preserves accessibility output, and is reviewed by a
human while playing a real guitar. A static preview alone is insufficient for
judging this interaction.
