import SwiftUI

// Free-recall prompt (FeedExplainPrompt, POST /api/explain/[cardId]/answer).
// Graded live by an LLM against the card body — no guest path (each attempt
// costs a real call), and a resubmit returns the stored grade rather than
// re-grading (see the route's cost-control comment).
struct ExplainCardView: View {
    let prompt: FeedExplainPrompt
    let onSubmit: (String) async -> ExplainAnswerResponse?
    let onSkip: () async -> ExplainAnswerResponse?
    let onXp: (XpSummary) -> Void

    @State private var text = ""
    @State private var result: ExplainAnswerResponse?
    @State private var isSubmitting = false

    private var canSubmit: Bool { text.count >= 10 && text.count <= 600 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(prompt.category.icon) Explain it back")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.panelAlt, in: Capsule())
                Spacer()
            }

            Text(prompt.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            if let result {
                resultView(result)
            } else {
                composerView
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }

    private var composerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Theme.textPrimary)
                .frame(height: 100)
                .padding(8)
                .background(Theme.panelAlt, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                .disabled(isSubmitting)

            HStack {
                Button("I don't know") {
                    guard !isSubmitting else { return }
                    isSubmitting = true
                    Task {
                        if let response = await onSkip() {
                            result = response
                            onXp(response.xp)
                        }
                        isSubmitting = false
                    }
                }
                .foregroundStyle(Theme.accentText)
                .disabled(isSubmitting)

                Spacer()

                Button {
                    guard canSubmit, !isSubmitting else { return }
                    isSubmitting = true
                    Task {
                        if let response = await onSubmit(text) {
                            result = response
                            onXp(response.xp)
                        }
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(Theme.accentBright)
                    } else {
                        Text("Submit").font(.headline)
                    }
                }
                .foregroundStyle(canSubmit ? Theme.accentBright : Theme.textMuted)
                .disabled(!canSubmit || isSubmitting)
            }
        }
    }

    private func resultView(_ result: ExplainAnswerResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.feedback)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            if result.xp.awarded > 0 {
                XpAwardChip(xp: result.xp)
            }
        }
    }
}
