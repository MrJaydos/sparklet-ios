import Foundation
import CoreGraphics

@MainActor
final class KnowledgeMapViewModel: ObservableObject {
    @Published private(set) var nodes: [MapNode] = []
    @Published private(set) var edges: [MapEdge] = []
    @Published private(set) var totalLearned = 0
    @Published private(set) var isLoading = false
    @Published var previewNode: MapNode?

    struct NodeSim {
        var x: Double
        var y: Double
        var vx = 0.0
        var vy = 0.0
    }

    // Live simulation state — deliberately not @Published. KnowledgeMapView
    // redraws via a continuously-ticking TimelineView(.animation) while the
    // screen is open and reads this fresh every frame, so publishing it too
    // would just double the invalidation cost for no benefit. (The web
    // version sleeps its requestAnimationFrame loop once the graph settles,
    // purely as a battery optimization for a page that can stay open
    // indefinitely; a ~20k-pairwise-comparison step() at 60fps is trivial
    // for a native CPU on a sheet a user has open for well under a minute,
    // so this port always steps rather than porting that sleep/wake state
    // machine — doing so safely would mean mutating an @Published flag from
    // inside TimelineView's content closure, a footgun not worth it here.)
    private(set) var sim: [String: NodeSim] = [:]
    private(set) var draggingNodeId: String?

    // Fit to the graph's initial settled shape — an organic, asymmetric
    // extent, not a fixed square. Computed once from the server's starting
    // positions and never recomputed; a strong center-pull force in step()
    // keeps live-physics drift from wandering off it, same as the web.
    private(set) var viewW = 600.0
    private(set) var viewH = 600.0
    private(set) var centerX = 300.0
    private(set) var centerY = 300.0

    private(set) var degree: [String: Int] = [:]
    private(set) var categoryBreakdown: [(category: Category, count: Int)] = []

    private let api = MapAPI()
    private let authSession: AuthSession

    private static let padding = 24.0
    private static let damping = 0.82
    private static let repel = 14000.0
    private static let spring = 0.02

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func loadIfNeeded() async {
        guard nodes.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetch(token: authSession.token)
            apply(response)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the screen just shows the empty state.
        }
    }

    private func apply(_ response: MapResponse) {
        nodes = response.nodes
        edges = response.edges
        totalLearned = response.totalLearned

        sim = Dictionary(uniqueKeysWithValues: response.positions.map {
            ($0.id, NodeSim(x: $0.x, y: $0.y))
        })

        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in response.positions {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        if !minX.isFinite {
            minX = 0; minY = 0; maxX = 600; maxY = 600
        }
        viewW = maxX - minX + Self.padding * 2
        viewH = maxY - minY + Self.padding * 2
        centerX = (minX + maxX) / 2
        centerY = (minY + maxY) / 2

        var deg: [String: Int] = [:]
        for n in nodes { deg[n.id] = 0 }
        for e in edges {
            deg[e.source, default: 0] += 1
            deg[e.target, default: 0] += 1
        }
        degree = deg

        var order: [String] = []
        var groups: [String: (Category, Int)] = [:]
        for n in nodes {
            if groups[n.category.slug] == nil {
                groups[n.category.slug] = (n.category, 0)
                order.append(n.category.slug)
            }
            groups[n.category.slug]!.1 += 1
        }
        categoryBreakdown = order.map { (groups[$0]!.0, groups[$0]!.1) }
    }

    func radius(for nodeId: String) -> Double {
        min(14, 4 + Double(degree[nodeId] ?? 0) * 1.8)
    }

    // MARK: - Live physics

    // Continuous, velocity-based variant of the same repel/spring/center
    // forces the server's one-shot forceLayout() uses — ports MapView.tsx's
    // step() 1:1, same constants (REPEL/SPRING/DAMPING).
    func step() {
        let ids = Array(sim.keys)
        guard !ids.isEmpty else { return }
        var forces: [String: (x: Double, y: Double)] = Dictionary(
            uniqueKeysWithValues: ids.map { ($0, (0.0, 0.0)) }
        )

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let a = sim[ids[i]]!
                let b = sim[ids[j]]!
                var dx = a.x - b.x
                var dy = a.y - b.y
                let dist = max(8, (dx * dx + dy * dy).squareRoot())
                let f = Self.repel / (dist * dist)
                dx = (dx / dist) * f
                dy = (dy / dist) * f
                forces[ids[i]]!.x += dx
                forces[ids[i]]!.y += dy
                forces[ids[j]]!.x -= dx
                forces[ids[j]]!.y -= dy
            }
        }

        let restLength = ((viewW * viewH) / Double(max(1, ids.count))).squareRoot() * 0.7
        for e in edges {
            guard let a = sim[e.source], let b = sim[e.target] else { continue }
            var dx = b.x - a.x
            var dy = b.y - a.y
            let dist = max(0.01, (dx * dx + dy * dy).squareRoot())
            let f = Self.spring * (dist - restLength)
            dx = (dx / dist) * f
            dy = (dy / dist) * f
            forces[e.source]!.x += dx
            forces[e.source]!.y += dy
            forces[e.target]!.x -= dx
            forces[e.target]!.y -= dy
        }

        for id in ids {
            if id == draggingNodeId { continue } // pinned to the pointer
            var p = sim[id]!
            var f = forces[id]!
            f.x += (centerX - p.x) * 0.01
            f.y += (centerY - p.y) * 0.01
            p.vx = (p.vx + f.x) * Self.damping
            p.vy = (p.vy + f.y) * Self.damping
            p.x += p.vx
            p.y += p.vy
            sim[id] = p
        }
    }

    func beginDrag(nodeId: String) {
        draggingNodeId = nodeId
    }

    func updateDrag(nodeId: String, userSpaceDelta: CGSize) {
        guard var p = sim[nodeId] else { return }
        p.x += Double(userSpaceDelta.width)
        p.y += Double(userSpaceDelta.height)
        p.vx = 0
        p.vy = 0
        sim[nodeId] = p
    }

    func endDrag() {
        draggingNodeId = nil
    }

    func position(of nodeId: String) -> (x: Double, y: Double)? {
        sim[nodeId].map { ($0.x, $0.y) }
    }
}
