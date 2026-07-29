import Foundation

// Mirrors POST /api/billing/apple/verify (sparklet/src/app/api/billing/
// apple/verify/route.ts) — the authoritative response after the server
// verifies a signed StoreKit transaction and reconciles it onto the user's
// row, so the client can reflect the new state immediately.
struct BillingVerifyResponse: Decodable {
    let premium: Bool
    let expiresAt: String?
}
