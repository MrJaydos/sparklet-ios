import SwiftUI

enum ReportTarget {
    case card(id: String)
    case comment(id: String)
}

// Mirrors ReportSheet.tsx — a reason-picker sheet shared by cards and
// comments.
struct ReportSheetView: View {
    let target: ReportTarget
    let authSession: AuthSession
    let onClose: () -> Void

    @State private var reason: ReportReason?
    @State private var detail = ""
    @State private var state: SubmitState = .idle

    private enum SubmitState { case idle, sending, done }

    private let api = CardActionsAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state == .done {
                Text("✅ Thanks — we'll take a look.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                Text(targetLabel)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)

                VStack(spacing: 8) {
                    ForEach(ReportReason.allCases, id: \.self) { r in
                        Button {
                            reason = r
                        } label: {
                            Text(r.label)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(
                                    reason == r ? Theme.danger.opacity(0.15) : Theme.panel,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(reason == r ? Theme.danger : Theme.border)
                                )
                                .foregroundStyle(reason == r ? Theme.dangerText : Theme.textSecondary)
                        }
                    }
                }

                TextField("Anything else we should know? (optional)", text: $detail, axis: .vertical)
                    .lineLimit(2...4)
                    .padding()
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    .onChange(of: detail) { _, newValue in
                        if reason == nil, !newValue.isEmpty { reason = .other }
                    }

                Button {
                    Task { await submit() }
                } label: {
                    Text(state == .sending ? "Sending…" : "Send report")
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 12)
                .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .disabled(reason == nil || state == .sending)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }

    private var targetLabel: String {
        switch target {
        case .card: return "Report this card"
        case .comment: return "Report this comment"
        }
    }

    private func submit() async {
        guard let reason, state == .idle else { return }
        state = .sending
        do {
            switch target {
            case .card(let id):
                _ = try await api.reportCard(cardId: id, reason: reason, detail: detail.isEmpty ? nil : detail, token: authSession.token)
            case .comment(let id):
                _ = try await api.reportComment(commentId: id, reason: reason, detail: detail.isEmpty ? nil : detail, token: authSession.token)
            }
            state = .done
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onClose()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            state = .idle
        }
    }
}
