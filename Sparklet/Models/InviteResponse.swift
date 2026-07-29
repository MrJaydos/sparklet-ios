import Foundation

// Mirrors POST /api/invite/[refId]/accept (sparklet/src/app/api/invite/
// [refId]/accept/route.ts), which ports the auto-friend + streak-freeze
// reward logic out of the web's src/app/invite/[refId]/page.tsx.
struct InviteResponse: Decodable {
    let status: Status
    let referrerName: String?
    let rewardGranted: Bool

    enum Status: String, Decodable {
        case invalid, self_ = "self", friended, already
    }
}
