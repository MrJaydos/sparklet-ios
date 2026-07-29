import SwiftUI

struct LeaderboardView: View {
    @ObservedObject var viewModel: LeaderboardViewModel
    @Environment(\.dismiss) private var dismiss

    private static let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    boardPicker

                    if viewModel.isLoading, viewModel.response == nil {
                        ProgressView().tint(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let response = viewModel.response {
                        if response.rows.isEmpty {
                            Text(emptyMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.top, 8)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(response.rows.enumerated()), id: \.element.id) { index, row in
                                    rankRow(rank: index + 1, name: row.name, xp: row.xp, isSelf: row.userId == response.viewerId)
                                }
                            }
                        }

                        if let me = response.me, !response.inTop {
                            rankRow(rank: me.rank, name: response.selfName, xp: me.xp, isSelf: true)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("🏆 Leaderboard")
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
            await viewModel.loadIfNeeded()
        }
    }

    private var boardPicker: some View {
        HStack(spacing: 8) {
            ForEach(LeaderboardViewModel.Board.allCases, id: \.self) { board in
                Button(board.label) {
                    viewModel.board = board
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    viewModel.board == board ? Theme.accent : Color.clear,
                    in: Capsule()
                )
                .foregroundStyle(viewModel.board == board ? .white : Theme.textTertiary)
                .overlay(
                    Capsule().strokeBorder(viewModel.board == board ? Color.clear : Theme.border)
                )
            }
        }
    }

    private var emptyMessage: String {
        switch viewModel.board {
        case .friends: return "No friends on the board yet — add some from the friends screen."
        case .today: return "Nobody has earned XP today yet — the first card you read puts you on the board."
        case .week: return "Nobody has earned XP this week yet — the first card you read puts you on the board."
        case .all: return "Nobody has earned XP yet — the first card you read puts you on the board."
        }
    }

    private func rankRow(rank: Int, name: String, xp: Int, isSelf: Bool) -> some View {
        HStack(spacing: 12) {
            Text(rank <= 3 ? Self.medals[rank - 1] : "\(rank)")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28)

            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if isSelf {
                    Text("you")
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                }
            }

            Spacer()

            Text("⚡ \(xp)")
                .font(.subheadline.bold())
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            isSelf ? Theme.accent.opacity(0.12) : Theme.panel,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelf ? Theme.accent.opacity(0.6) : Theme.border)
        )
    }
}
