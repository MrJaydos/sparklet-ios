import Foundation

// Mirrors Feed.tsx's `sparklet.categories` localStorage key — the topic
// filter applied to the feed. Empty means "Random / Everything," same as
// the web (no selection is a real, meaningful state here, not "unset").
enum CategoryPreference {
    private static let key = "sparklet.categories"

    static func get() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func set(_ slugs: [String]) {
        UserDefaults.standard.set(slugs, forKey: key)
    }
}
