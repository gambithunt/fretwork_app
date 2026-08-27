import Foundation

/// A round of "show me where it is" prompts, one at a time.
///
/// Ported from `../fretwork/src/lib/recall-challenge.ts`. It is deliberately
/// *not* a quiz that marks you and moves on: a wrong answer goes to an
/// `incorrect` phase you retry from, so the round only advances once the shape
/// has actually been recalled. That is what makes it practice rather than a
/// test.
///
/// Pure state, no clock and no audio, so a module can drive it from a tap and a
/// test can drive it directly.
@MainActor
@Observable
final class RecallChallenge<Context, Answer: Equatable> {
    enum Phase: String, Sendable, Equatable {
        case idle, prompt, incorrect, correct, complete
    }

    struct Prompt: Identifiable {
        let id: String
        /// What the board should show while this is being asked.
        let context: Context
        /// The answer that counts as recalled.
        let expected: Answer
    }

    private(set) var phase: Phase = .idle
    private(set) var index = 0
    private(set) var total = 0
    private(set) var correctCount = 0
    /// Wrong answers on the *current* prompt. Reset per prompt, not per round —
    /// it drives the "try again" copy rather than a score.
    private(set) var attempts = 0
    private(set) var prompt: Prompt?
    private(set) var lastAnswer: Answer?

    private var prompts: [Prompt] = []

    var isRunning: Bool { phase != .idle }
    /// Whether an answer would be accepted right now.
    var isAcceptingAnswers: Bool { phase == .prompt || phase == .incorrect }

    func start(_ prompts: [Prompt]) {
        self.prompts = prompts
        guard !prompts.isEmpty else { return reset() }
        show(index: 0, correctCount: 0)
    }

    func answer(_ answer: Answer) {
        guard isAcceptingAnswers, let prompt else { return }
        lastAnswer = answer
        if answer == prompt.expected {
            phase = .correct
            correctCount += 1
        } else {
            phase = .incorrect
            attempts += 1
        }
    }

    /// Back to the prompt after a wrong answer. The prompt itself does not
    /// change — the point is to find the same shape again.
    func retry() {
        guard phase == .incorrect else { return }
        phase = .prompt
        lastAnswer = nil
    }

    func next() {
        guard phase == .correct else { return }
        show(index: index + 1, correctCount: correctCount)
    }

    func restart() {
        guard !prompts.isEmpty else { return }
        show(index: 0, correctCount: 0)
    }

    func stop() {
        prompts = []
        reset()
    }

    private func show(index: Int, correctCount: Int) {
        guard index < prompts.count else {
            // A finished round keeps its score: the count is the whole point of
            // having played it.
            phase = .complete
            self.index = index
            total = prompts.count
            self.correctCount = correctCount
            prompt = nil
            lastAnswer = nil
            attempts = 0
            return
        }
        phase = .prompt
        self.index = index
        total = prompts.count
        self.correctCount = correctCount
        attempts = 0
        prompt = prompts[index]
        lastAnswer = nil
    }

    private func reset() {
        phase = .idle
        index = 0
        total = 0
        correctCount = 0
        attempts = 0
        prompt = nil
        lastAnswer = nil
    }
}
