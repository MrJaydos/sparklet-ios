import Foundation

// Mirrors POST /api/billing/apple/verify (sparklet/src/app/api/billing/
// apple/verify/route.ts).
struct BillingAPI {
    let client: APIClient = .shared

    private struct VerifyRequest: Encodable { let signedTransactionInfo: String }

    func verify(signedTransactionInfo: String, token: String?) async throws -> BillingVerifyResponse {
        try await client.post(
            "api/billing/apple/verify",
            body: VerifyRequest(signedTransactionInfo: signedTransactionInfo),
            token: token
        )
    }
}
