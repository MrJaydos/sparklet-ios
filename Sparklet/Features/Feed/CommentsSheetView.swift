import SwiftUI

// Mirrors CommentsSheet.tsx/CommentsPanel — a comment thread + composer.
struct CommentsSheetView: View {
    let cardId: String
    let cardTitle: String
    let authSession: AuthSession
    let onCountChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [Comment]?
    @State private var draft = ""
    @State private var isPosting = false
    @State private var reportingCommentId: String?

    private let api = CardActionsAPI()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if let comments {
                                if comments.isEmpty {
                                    Text("No comments yet — start the conversation.")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 24)
                                } else {
                                    ForEach(comments) { comment in
                                        commentRow(comment).id(comment.id)
                                    }
                                }
                            } else {
                                ProgressView().tint(Theme.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: comments?.count) { _, _ in
                        if let lastId = comments?.last?.id {
                            withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                    Button {
                        Task { await post() }
                    } label: {
                        Text("Post")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("💬 \(cardTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: Binding(
            get: { reportingCommentId.map { ReportRoute(id: $0) } },
            set: { reportingCommentId = $0?.id }
        )) { route in
            ReportSheetView(target: .comment(id: route.id), authSession: authSession) {
                reportingCommentId = nil
            }
        }
        .task {
            await load()
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Text(comment.author)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textTertiary)
                    if comment.mine {
                        Text("(you)")
                            .font(.caption)
                            .foregroundStyle(Theme.accentText)
                    }
                }
                Spacer()
                Text(timeAgo(comment.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
                if !comment.mine {
                    Button {
                        reportingCommentId = comment.id
                    } label: {
                        Image(systemName: "flag")
                            .font(.caption2)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            Text(comment.body)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func load() async {
        do {
            let response = try await api.fetchComments(cardId: cardId, token: authSession.token)
            comments = response.comments
            onCountChange(response.comments.count)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            comments = []
        }
    }

    private func post() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let comment = try await api.postComment(cardId: cardId, body: body, token: authSession.token)
            comments = (comments ?? []) + [comment]
            onCountChange(comments?.count ?? 0)
            draft = ""
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the draft stays put so the user can retry.
        }
    }
}

private struct ReportRoute: Identifiable {
    let id: String
}

private func timeAgo(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter.withFractionalSeconds.date(from: iso) else { return "" }
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86400 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86400)d ago"
}
