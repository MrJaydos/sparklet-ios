import SwiftUI

struct FriendsView: View {
    @ObservedObject var viewModel: FriendsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputValue = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    friendCodeRow
                    addFriendRow

                    if let notice = viewModel.notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    section("Requests", rows: viewModel.incoming) { row in
                        requestRow(row)
                    }
                    section("Sent", rows: viewModel.outgoing) { row in
                        sentRow(row)
                    }
                    section("Friends", rows: viewModel.friends) { row in
                        friendRow(row)
                    }

                    if !viewModel.isLoading, viewModel.friends.isEmpty, viewModel.incoming.isEmpty, viewModel.outgoing.isEmpty {
                        Text("Add someone by email or friend code to get started.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.isLoading && viewModel.friends.isEmpty && viewModel.incoming.isEmpty && viewModel.outgoing.isEmpty {
                    ProgressView().tint(Theme.textTertiary)
                }
            }
            .navigationTitle("Friends")
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
        .task {
            await viewModel.load()
        }
    }

    private var friendCodeRow: some View {
        HStack {
            Text("Your code:")
                .foregroundStyle(Theme.textTertiary)
            Text(viewModel.friendCode ?? "\u{2014}")
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                if let code = viewModel.friendCode {
                    UIPasteboard.general.string = code
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .foregroundStyle(Theme.accentText)
            .disabled(viewModel.friendCode == nil)
        }
        .font(.subheadline)
        .padding()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var addFriendRow: some View {
        HStack {
            TextField("Email or friend code", text: $inputValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))

            Button {
                Task { await sendRequest() }
            } label: {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("Add")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .disabled(isSending || inputValue.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func section<Row: View>(_ title: String, rows: [FriendRow], @ViewBuilder row: @escaping (FriendRow) -> Row) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                ForEach(rows) { row($0) }
            }
        }
    }

    private func requestRow(_ row: FriendRow) -> some View {
        personRow(row) {
            HStack(spacing: 8) {
                actionButton("Accept", tint: Theme.success) { await viewModel.accept(row.friendshipId) }
                actionButton("Decline", tint: Theme.dangerText) { await viewModel.remove(row.friendshipId) }
            }
        }
    }

    private func sentRow(_ row: FriendRow) -> some View {
        personRow(row) {
            actionButton("Cancel", tint: Theme.textTertiary) { await viewModel.remove(row.friendshipId) }
        }
    }

    private func friendRow(_ row: FriendRow) -> some View {
        personRow(row) {
            actionButton("Remove", tint: Theme.dangerText) { await viewModel.remove(row.friendshipId) }
        }
    }

    private func personRow<Actions: View>(_ row: FriendRow, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(row.email)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if viewModel.busyId == row.friendshipId {
                ProgressView().tint(Theme.textTertiary)
            } else {
                actions()
            }
        }
        .padding()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private func actionButton(_ title: String, tint: Color, action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .font(.footnote.bold())
            .foregroundStyle(tint)
            .disabled(viewModel.busyId != nil)
    }

    private func sendRequest() async {
        isSending = true
        defer { isSending = false }
        await viewModel.sendRequest(inputValue)
        inputValue = ""
    }
}
