import SwiftUI

// Guess-before-reveal (FeedGuess, POST /api/guess/[id]/answer). The true
// answer never reaches the client until after a guess is locked in —
// unlike quiz, there's no "options" to leak it through.
struct GuessCardView: View {
    let guess: FeedGuess
    let onSubmit: (Double) async -> GuessAnswerResponse?
    let onXp: (XpSummary) -> Void

    @State private var value: Double
    @State private var result: GuessAnswerResponse?
    @State private var isSubmitting = false

    init(
        guess: FeedGuess,
        onSubmit: @escaping (Double) async -> GuessAnswerResponse?,
        onXp: @escaping (XpSummary) -> Void
    ) {
        self.guess = guess
        self.onSubmit = onSubmit
        self.onXp = onXp
        _value = State(initialValue: (guess.min + guess.max) / 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(guess.category.icon) Guess")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.panelAlt, in: Capsule())
                Spacer()
            }

            Text(guess.prompt)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            if let result {
                revealView(result)
            } else {
                sliderView
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }

    private var sliderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(formattedValue(value))
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            Slider(
                value: $value,
                in: guess.min...guess.max,
                step: guess.integer ? 1 : (guess.max - guess.min) / 100
            )
            .tint(Theme.accentBright)
            .disabled(isSubmitting)

            Button {
                guard !isSubmitting else { return }
                isSubmitting = true
                Task {
                    if let response = await onSubmit(value) {
                        result = response
                        onXp(response.xp)
                    }
                    isSubmitting = false
                }
            } label: {
                Text("Lock in guess")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .disabled(isSubmitting)
        }
    }

    private func revealView(_ result: GuessAnswerResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Answer: \(formattedValue(result.answer))")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(result.correct ? "Nice guess!" : "Close, but not quite")
                .font(.subheadline.bold())
                .foregroundStyle(result.correct ? Theme.successText : Theme.textTertiary)
            Text(result.explanation)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if result.xp.awarded > 0 {
                XpAwardChip(xp: result.xp, combo: result.combo, multiplier: result.multiplier)
            }
        }
    }

    private func formattedValue(_ v: Double) -> String {
        let number = guess.integer ? String(Int(v.rounded())) : v.formatted(.number.precision(.fractionLength(0...1)))
        return guess.unit.isEmpty ? number : "\(number) \(guess.unit)"
    }
}
