import Foundation

// Mirrors the web's `sparklet.depth` localStorage key (LearnCard.tsx) — a
// manual depth switch is also a preference: remember it and auto-apply to
// future cards as they scroll into view, until switched back to Standard.
// UserDefaults is this app's equivalent of localStorage; the key name
// matches the web's for parity even though the two stores aren't shared.
enum DepthPreference {
    private static let key = "sparklet.depth"

    // nil (never set) and .standard (explicitly reset) both mean "don't
    // auto-apply anything" — callers should treat them the same way the
    // web's auto-apply effect does (`pref !== "SIMPLE" && ... → return`).
    static func get() -> DepthLevel? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return DepthLevel(rawValue: raw)
    }

    static func set(_ level: DepthLevel) {
        UserDefaults.standard.set(level.rawValue, forKey: key)
    }
}
