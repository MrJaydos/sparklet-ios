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
    @State private var wasSkipped = false
    @State private var isSubmitting = false

    private var canSubmit: Bool { text.count >= 10 && text.count <= 600 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(prompt.category.icon) Explain it back")
                    .font(.caption.bold())
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(categoryColor.opacity(0.2), in: Capsule())
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
        }
        .padding()
        // Mirrors ExplainView.tsx's `justify-center` — vertically centered
        // rather than pinned to the top with a trailing Spacer eating the
        // leftover room, flagged live by the user as looking off.
        .frame(maxHeight: .infinity, alignment: .center)
        .clipped()
        // No boxed panel — FeedView paints one shared per-category backdrop
        // behind this and every other slide kind, matching
        // ExplainView.tsx's own full-bleed `h-dvh w-full` shape rather than
        // a boxed card.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryColor: Color {
        Color(hexString: prompt.category.colorHex)
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
                            wasSkipped = true
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

    // Mirrors ExplainView.tsx's own reveal box (`rounded-xl bg-neutral-900/90
    // p-4`) — a semi-opaque panel over the full-bleed backdrop, distinct
    // from the boxed-panel-per-card look this view no longer has overall.
    private func resultView(_ result: ExplainAnswerResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if wasSkipped {
                // Mirrors ExplainView.tsx's separate "revealed" state: the
                // backend's `feedback` string for a skip is deliberately
                // generic ("No worries — here's a reminder...", see
                // src/app/api/explain/[cardId]/answer/route.ts) — it's not
                // meant to be the payoff by itself. The web shows the card's
                // own body text instead, already known client-side via
                // `prompt`, not by re-fetching anything. An earlier iOS pass
                // rendered `result.feedback` unconditionally here, which for
                // a skip showed only that generic line and nothing else —
                // flagged live by the user tapping "I don't know" and seeing
                // no actual information.
                Text("📖 Here's a reminder")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                Text(prompt.body)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(result.feedback)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                if result.xp.awarded > 0 {
                    XpAwardChip(xp: result.xp)
                }
            }
        }
        .padding()
        .background(Theme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }
}
