import Foundation

// Mirrors GET /api/profile (sparklet/src/app/api/profile/route.ts, added
// specifically to give native clients a JSON source for the XP ring/streak
// state that the web client previously only got from a server-rendered
// page). Two distinct daily numbers, kept separate on purpose (see
// AGENTS.md): `xpToday`/`xpGoal` answer "did I hit my XP today", `cardsToday`
// answers "did I hit my count today".
struct ProfileResponse: Codable {
    let xp: Int
    let xpToday: Int
    let xpGoal: Int
    let cardsToday: Int
    let currentStreak: Int
    let longestStreak: Int
    let freezesAvailable: Int
}
