import SwiftUI

struct NotificationsView: View {
    @ObservedObject var viewModel: NotificationsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.friendAlerts) { alert in
                        alertRow(alert, icon: "person.2.fill")
                    }
                    ForEach(viewModel.adminAlerts) { alert in
                        alertRow(alert, icon: "wrench.fill")
                    }

                    if viewModel.notifications.isEmpty && !viewModel.isLoading {
                        Text("When someone replies in a comment thread you're part of, it shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 8)
                    }

                    ForEach(viewModel.notifications) { notification in
                        notificationRow(notification)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    ProgressView().tint(Theme.textTertiary)
                }
            }
            .navigationTitle("Notifications")
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
            await viewModel.loadAndMarkRead()
        }
    }

    private func alertRow(_ alert: NotificationAlert, icon: String) -> some View {
        Label(alert.label, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.4)))
    }

    private func notificationRow(_ notification: NotificationItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(notification.actorName).bold() + Text(" commented on ") + Text(notification.cardTitle).fontWeight(.medium))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            if let preview = notification.preview {
                Text("\u{201C}\(preview)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            notification.read ? Theme.panel : Theme.accent.opacity(0.15),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(notification.read ? Theme.border : Theme.accent.opacity(0.6))
        )
    }
}
