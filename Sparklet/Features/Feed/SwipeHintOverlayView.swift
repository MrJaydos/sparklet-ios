import SwiftUI

// Mirrors Feed.tsx's one-time "Start swiping to learn" hint — an animated
// upward-flicking hand + fading trail, shown once for a brand-new visitor
// and dismissed by the first real swipe. Ports globals.css's swipe-hand/
// swipe-trail keyframes (translateY+rotate+opacity over 1.7s, looping) onto
// a single shared PhaseAnimator so the hand and trail stay in lockstep —
// two independent PhaseAnimators would each run their own internal clock
// and drift out of sync with each other over time.
struct SwipeHintOverlayView: View {
    private enum Phase: CaseIterable {
        case start   // CSS 0%: translateY(10px) rotate(14deg), opacity 0
        case rising  // CSS 18%: translateY(4px) rotate(12deg), opacity 1
        case peak    // CSS 62%: translateY(-30px) rotate(-16deg), opacity 1
        case gone    // CSS 82%/100%: translateY(-52px) rotate(-20deg), opacity 0
    }

    var body: some View {
        VStack(spacing: 12) {
            PhaseAnimator(Phase.allCases) { phase in
                ZStack(alignment: .bottom) {
                    trail(phase)
                    hand(phase)
                }
            } animation: { phase in
                switch phase {
                case .start: .linear(duration: 0.01) // instant snap back to the loop start
                case .rising: .easeInOut(duration: 0.3)
                case .peak: .easeInOut(duration: 0.75)
                case .gone: .easeInOut(duration: 0.35)
                }
            }
            .frame(height: 110)

            Text("Start swiping to learn")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 6)
        }
        // Same "look but don't block" intent as the web's pointer-events-none
        // wrapper — this sits above the feed purely as a visual cue.
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hand(_ phase: Phase) -> some View {
        Text("👆")
            .font(.system(size: 44))
            .shadow(radius: 4)
            .offset(y: handOffset(phase))
            .rotationEffect(.degrees(handRotation(phase)))
            .opacity(handOpacity(phase))
    }

    @ViewBuilder
    private func trail(_ phase: Phase) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.4), .white.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 6, height: 64)
            .scaleEffect(y: trailScale(phase), anchor: .bottom)
            .opacity(trailOpacity(phase))
    }

    private func handOffset(_ phase: Phase) -> CGFloat {
        switch phase {
        case .start: 10
        case .rising: 4
        case .peak: -30
        case .gone: -52
        }
    }

    private func handRotation(_ phase: Phase) -> Double {
        switch phase {
        case .start: 14
        case .rising: 12
        case .peak: -16
        case .gone: -20
        }
    }

    private func handOpacity(_ phase: Phase) -> Double {
        switch phase {
        case .start: 0
        case .rising: 1
        case .peak: 1
        case .gone: 0
        }
    }

    private func trailScale(_ phase: Phase) -> CGFloat {
        switch phase {
        case .start: 0.2
        case .rising: 0.6
        case .peak: 1.0
        case .gone: 1.15
        }
    }

    private func trailOpacity(_ phase: Phase) -> Double {
        switch phase {
        case .start: 0
        case .rising: 0.5
        case .peak: 0.7
        case .gone: 0
        }
    }
}
