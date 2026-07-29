import SwiftUI

// The web's StreakBadge/XpRing popovers (sparklet repo,
// src/components/feed/) slide down from the top edge — their "sheet-drop"
// CSS class plus `fixed inset-0 flex flex-col justify-start` — not up from
// the bottom like a standard iOS `.sheet()`. This reproduces that: a
// dimmed full-screen backdrop (tap to dismiss) with content pinned to the
// top edge, rounded only at the bottom, sliding/fading in from the top.
struct TopDropdown<DropdownContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let dropdownContent: () -> DropdownContent

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .onTapGesture { close() }

                        dropdownContent()
                            .background(Theme.background)
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
                            .overlay(
                                UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24)
                                    .strokeBorder(Theme.border)
                            )
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.25), value: isPresented)
    }

    private func close() {
        isPresented = false
    }
}

extension View {
    func topDropdown<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(TopDropdown(isPresented: isPresented, dropdownContent: content))
    }
}
