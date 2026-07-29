import Foundation

// Mirrors GET /api/map (sparklet/src/app/api/map/route.ts), which ports
// getKnowledgeMap() + the server-side settled forceLayout() out of the
// web's src/app/map/page.tsx.
struct MapResponse: Decodable {
    let nodes: [MapNode]
    let edges: [MapEdge]
    let totalLearned: Int
    // Server-settled starting layout (220 Fruchterman-Reingold iterations)
    // — the client only runs the *live* wake-on-touch physics on top of
    // these, same division of work as the web (see KnowledgeMapViewModel).
    let positions: [MapPosition]
}

struct MapNode: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let category: Category
}

struct MapEdge: Decodable, Hashable {
    let source: String
    let target: String
}

struct MapPosition: Decodable {
    let id: String
    let x: Double
    let y: Double
}
