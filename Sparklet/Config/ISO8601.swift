import Foundation

extension ISO8601DateFormatter {
    // The backend's timestamps all come from JS's Date.toISOString() (via
    // Prisma DateTime → NextResponse.json(), or an explicit .toISOString()
    // call) — that format always includes milliseconds, which the default
    // ISO8601DateFormatter() (no options) fails to parse.
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
