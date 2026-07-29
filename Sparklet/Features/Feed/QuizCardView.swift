import SwiftUI

// Renders both a recall quiz (FeedQuiz, POST /api/quiz/[id]/answer) and a
// due review served as a question (FeedReviewQuiz, POST
// /api/reviews/[id]/answer) — identical UI, only the submit endpoint and a
// "Review" vs "Quiz" label differ, mirroring QuizView.tsx's `variant` prop.
struct QuizCardView: View {
    let question: String
    let options: [String]
    let category: Category
    let isReview: Bool
    let onSubmit: (Int) async -> QuizAnswerResponse?
    let onXp: (XpSummary) -> Void

    @State private var selected: Int?
    @State private var result: QuizAnswerResponse?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(category.icon) \(isReview ? "Review" : "Quiz")")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.panelAlt, in: Capsule())
                Spacer()
            }

            Text(question)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 10) {
                ForEach(options.indices, id: \.self) { index in
                    optionButton(index)
                }
            }

            if let result {
                resultView(result)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }

    private func optionButton(_ index: Int) -> some View {
        Button {
            guard result == nil, !isSubmitting else { return }
            selected = index
            isSubmitting = true
            Task {
                if let response = await onSubmit(index) {
                    result = response
                    onXp(response.xp)
                }
                isSubmitting = false
            }
        } label: {
            HStack {
                Text(options[index])
                Spacer()
            }
            .padding()
            .background(optionBackground(index), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(optionBorder(index)))
        }
        .foregroundStyle(Theme.textPrimary)
        .disabled(result != nil || isSubmitting)
    }

    private func optionBackground(_ index: Int) -> Color {
        guard let result else {
            return selected == index ? Theme.accent.opacity(0.15) : Theme.panelAlt
        }
        if index == result.correctIndex { return Theme.success.opacity(0.15) }
        if index == selected { return Theme.danger.opacity(0.15) }
        return Theme.panelAlt
    }

    private func optionBorder(_ index: Int) -> Color {
        guard let result else {
            return selected == index ? Theme.accentBright : .clear
        }
        if index == result.correctIndex { return Theme.success }
        if index == selected { return Theme.danger }
        return .clear
    }

    private func resultView(_ result: QuizAnswerResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.correct ? "✅ Nailed it" : "💡 Good try — now you know")
                .font(.subheadline.bold())
                .foregroundStyle(result.correct ? Theme.successText : Theme.dangerText)
            Text(result.explanation)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if result.xp.awarded > 0 {
                XpAwardChip(xp: result.xp, combo: result.combo, multiplier: result.multiplier)
            }
        }
    }
}

// Shared "+N XP" (and combo, when it's active) chip used by every answer
// view's result state — mirrors Celebration.tsx's XpReward.
struct XpAwardChip: View {
    let xp: XpSummary
    var combo: Int = 0
    var multiplier: Double = 1

    var body: some View {
        HStack(spacing: 8) {
            Text("+\(xp.awarded) XP")
                .font(.caption.bold())
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.2), in: Capsule())

            // Same threshold as Celebration.tsx's XpReward — a combo only
            // starts showing once it's actually worth bragging about.
            if combo >= 3 {
                Text("🔥 \(combo) in a row · ×\(multiplier.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
        }
    }
}
