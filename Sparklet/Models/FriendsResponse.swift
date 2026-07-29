import Foundation

// Mirrors GET /api/friends (sparklet/src/app/api/friends/route.ts), added
// specifically to give native clients a JSON source for the friends list —
// the web app builds this server-side in the profile page's own query
// (src/app/profile/page.tsx), which iOS has no equivalent of.
struct FriendsResponse: Decodable {
    let friendCode: String
    let friends: [FriendRow]
    let incoming: [FriendRow]
    let outgoing: [FriendRow]
}

struct FriendRow: Decodable, Identifiable, Hashable {
    let friendshipId: String
    let name: String
    let email: String

    var id: String { friendshipId }
}
