import SwiftUI

// Predict-then-reveal (FeedMisconception, POST /api/misconception/[id]/answer).
// Same unseen-required timing as guess — committing true/false only makes
// sense before the correction is shown.
struct MisconceptionCardView: View {
    let misconception: FeedMisconception
    let onSubmit: (Bool) async -> MisconceptionAnswerResponse?
    let onXp: (XpSummary) -> Void

    @State private var picked: Bool?
    @State private var result: MisconceptionAnswerResponse?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(misconception.category.icon) True or false?")
                    .font(.caption.bold())
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(categoryColor.opacity(0.2), in: Capsule())
                Spacer()
            }

            Text(misconception.claim)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            if let result {
                resultView(result)
            } else {
                HStack(spacing: 12) {
                    choiceButton(true, label: "True")
                    choiceButton(false, label: "False")
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        // No boxed panel — FeedView paints one shared per-category backdrop
        // behind this and every other slide kind, matching
        // MisconceptionView.tsx's own full-bleed `h-dvh w-full` shape
        // rather than a boxed card.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryColor: Color {
        Color(hexString: misconception.category.colorHex)
    }

    private func choiceButton(_ choice: Bool, label: String) -> some View {
        Button {
            guard !isSubmitting else { return }
            picked = choice
            isSubmitting = true
            Task {
                if let response = await onSubmit(choice) {
                    result = response
                    onXp(response.xp)
                }
                isSubmitting = false
            }
        } label: {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.panelAlt, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .foregroundStyle(Theme.textPrimary)
        .disabled(isSubmitting)
    }

    // Mirrors MisconceptionView.tsx's own reveal box (`rounded-xl
    // bg-neutral-900/90 p-4`) — a semi-opaque panel over the full-bleed
    // backdrop, distinct from the boxed-panel-per-card look this view no
    // longer has overall.
    private func resultView(_ result: MisconceptionAnswerResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actually \(result.answer ? "true" : "false")")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(result.correct ? "You called it!" : "Common misconception")
                .font(.subheadline.bold())
                .foregroundStyle(result.correct ? Theme.successText : Theme.textTertiary)
            Text(result.explanation)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if result.xp.awarded > 0 {
                XpAwardChip(xp: result.xp, combo: result.combo, multiplier: result.multiplier)
            }
        }
        .padding()
        .background(Theme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }
}
