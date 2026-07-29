import SwiftUI

// Ports the web client's fixed dark theme (sparklet/src/app/globals.css and
// the Tailwind neutral/violet/emerald/red shades used throughout
// src/components/feed/*.tsx) — the web app has no light mode, so this app
// doesn't either; SparkletApp forces .dark so system light mode can't wash
// it out. Named after the Tailwind shade each mirrors, not the sRGB value,
// so this stays easy to diff against the web class names it's ported from.
enum Theme {
    // globals.css: --background: #0a0a0a
    static let background = Color(hex: 0x0A0A0A)

    // Card/input panels — Tailwind neutral-900 (bg-neutral-900).
    static let panel = Color(hex: 0x171717)
    // Slightly lighter panel — neutral-800 (bg-neutral-800), e.g. unmatched
    // category chips.
    static let panelAlt = Color(hex: 0x262626)
    // Panel borders — neutral-700 (border-neutral-700).
    static let border = Color(hex: 0x404040)

    // Text — neutral-100/300/400/500.
    static let textPrimary = Color(hex: 0xF5F5F5)
    static let textSecondary = Color(hex: 0xD4D4D4)
    static let textTertiary = Color(hex: 0xA3A3A3)
    static let textMuted = Color(hex: 0x737373)

    // Brand accent — violet-600/500/300 (primary buttons / highlights /
    // on-dark accent text, e.g. the matched-category chip and focus rings).
    static let accent = Color(hex: 0x7C3AED)
    static let accentBright = Color(hex: 0x8B5CF6)
    static let accentText = Color(hex: 0xC4B5FD)

    // Correct/incorrect answer states — emerald-500/300 and red-500/300,
    // exactly QuizView.tsx's "border-emerald-500 bg-emerald-500/15
    // text-emerald-300" / the red equivalent.
    static let success = Color(hex: 0x10B981)
    static let successText = Color(hex: 0x6EE7B7)
    static let danger = Color(hex: 0xEF4444)
    static let dangerText = Color(hex: 0xFCA5A5)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
