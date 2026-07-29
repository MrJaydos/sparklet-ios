import SwiftUI

// Mirrors the web's two-step OnboardingGrid (name, then a >=3 interest
// picker) — presented as a fullScreenCover from FeedView when
// ProfileResponse.needsOnboarding is true, rather than a separate route,
// since this client has no server-driven page redirect to hook into.
struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onComplete: () -> Void
    @State private var step: Step = .name

    private enum Step { case name, interests }

    private static let minPicks = 3
    private static let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .name: nameStep
                case .interests: interestsStep
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height, alignment: .center)
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await viewModel.loadCategories() }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should we call you?")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("So the next screen can say hi properly. Totally optional.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            TextField("Your name", text: $viewModel.name)
                .textInputAutocapitalization(.words)
                .foregroundStyle(Theme.textPrimary)
                .padding()
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))

            Button {
                step = .interests
            } label: {
                Text(viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            let trimmedName = viewModel.name.trimmingCharacters(in: .whitespaces)
            Text(trimmedName.isEmpty ? "What sparks your curiosity?" : "Okay, \(trimmedName), what interests you?")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Pick at least \(Self.minPicks) topics — your feed will show just these. You can widen or switch topics anytime from the feed.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            if viewModel.isLoading {
                ProgressView().tint(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(viewModel.categories, id: \.slug) { category in
                        categoryChip(category)
                    }
                }
            }

            let picked = viewModel.selectedSlugs.count
            Button {
                Task {
                    await viewModel.complete(skip: false)
                    onComplete()
                }
            } label: {
                Text(picked < Self.minPicks ? "Pick \(Self.minPicks - picked) more" : "Start with \(picked) topics")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .opacity(picked < Self.minPicks ? 0.4 : 1)
            .disabled(picked < Self.minPicks || viewModel.isSubmitting)

            Button {
                Task {
                    await viewModel.complete(skip: true)
                    onComplete()
                }
            } label: {
                Text("Skip — show me everything")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .foregroundStyle(Theme.textTertiary)
            .disabled(viewModel.isSubmitting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryChip(_ category: Category) -> some View {
        let active = viewModel.selectedSlugs.contains(category.slug)
        let tint = Color(hexString: category.colorHex)
        return Button {
            viewModel.toggle(category.slug)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(category.icon).font(.title3)
                Text(category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(active ? tint.opacity(0.25) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(active ? tint : Theme.border))
        }
    }
}
