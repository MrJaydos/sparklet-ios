import Foundation

// Parses the refId out of an invite URL — https://sparkletapp.com/invite/<id>
// once Universal Links are active (see project.yml's entitlements comment),
// or the same path delivered via `xcrun simctl openurl` for local testing.
// A free function rather than inline in SparkletApp.swift's RootView so it's
// unit-testable independent of the view hierarchy.
enum InviteLink {
    static func refId(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "invite" else { return nil }
        return parts[1]
    }
}
