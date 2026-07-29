import SwiftUI

// Mirrors src/components/MapView.tsx's live force-directed graph — every
// dot is a card the user's completed, lines connect related facts. The
// settled starting layout comes from the server (GET /api/map, same
// forceLayout() the web uses); this view runs only the *live*
// wake-on-touch physics on top of it (KnowledgeMapViewModel.step()), plus
// pan/pinch-zoom/drag-to-bump/tap-to-preview gestures ported from the
// web's pointer-event handling.
struct KnowledgeMapView: View {
    @ObservedObject var viewModel: KnowledgeMapViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var panOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var activeDrag: ActiveDrag?
    @State private var dragMoved = false

    private enum ActiveDrag {
        case pan(start: CGSize)
        case node(id: String, lastTranslation: CGSize)
    }

    private static let minScale: CGFloat = 0.5
    private static let maxScale: CGFloat = 3
    private static let dragThreshold: CGFloat = 4
    private static let edgeColor = Color(hex: 0x525252, opacity: 0.35)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isLoading, viewModel.nodes.isEmpty {
                        ProgressView().tint(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if viewModel.nodes.isEmpty {
                        Text("Read a few cards and your map will start growing here.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 60)
                    } else {
                        header
                        mapCanvas
                        categoryChips
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("🗺️ Knowledge map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $viewModel.previewNode) { node in
                previewCard(node)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.totalLearned)")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("facts learned overall")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
            Text("Your most recent \(viewModel.nodes.count), connected below — drag the background to pan, drag a dot to bump it, pinch to zoom")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    private var mapCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                TimelineView(.animation) { _ in
                    Canvas { context, size in
                        viewModel.step()
                        draw(in: &context, size: size)
                    }
                }
                .gesture(dragGesture(canvasSize: geo.size))
                .simultaneousGesture(magnificationGesture)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        panOffset = .zero
                        zoomScale = 1
                        zoomAtGestureStart = 1
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Theme.panel.opacity(0.9), in: Circle())
                }
                .padding(10)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Theme.panel.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Drawing

    private func baseScale(_ canvasSize: CGSize) -> CGFloat {
        CGFloat(min(canvasSize.width / viewModel.viewW, canvasSize.height / viewModel.viewH))
    }

    private func toScreen(_ p: (x: Double, y: Double), canvasSize: CGSize) -> CGPoint {
        let scale = baseScale(canvasSize) * zoomScale
        let cx = canvasSize.width / 2 + panOffset.width
        let cy = canvasSize.height / 2 + panOffset.height
        return CGPoint(x: cx + (p.x - viewModel.centerX) * Double(scale), y: cy + (p.y - viewModel.centerY) * Double(scale))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        var edgePath = Path()
        for edge in viewModel.edges {
            guard let a = viewModel.position(of: edge.source), let b = viewModel.position(of: edge.target) else { continue }
            edgePath.move(to: toScreen(a, canvasSize: size))
            edgePath.addLine(to: toScreen(b, canvasSize: size))
        }
        context.stroke(edgePath, with: .color(Self.edgeColor), lineWidth: 1)

        let scale = baseScale(size) * zoomScale
        for node in viewModel.nodes {
            guard let p = viewModel.position(of: node.id) else { continue }
            let center = toScreen(p, canvasSize: size)
            let r = CGFloat(viewModel.radius(for: node.id)) * scale
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(Color(hexString: node.category.colorHex)))
            context.stroke(circle, with: .color(Theme.background), lineWidth: 1.5)
        }
    }

    // MARK: - Gestures

    private func hitTestNode(at location: CGPoint, canvasSize: CGSize) -> String? {
        let scale = baseScale(canvasSize) * zoomScale
        for node in viewModel.nodes.reversed() {
            guard let p = viewModel.position(of: node.id) else { continue }
            let center = toScreen(p, canvasSize: canvasSize)
            let r = CGFloat(viewModel.radius(for: node.id)) * scale + 10 // tap padding
            if hypot(location.x - center.x, location.y - center.y) <= r {
                return node.id
            }
        }
        return nil
    }

    private func dragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeDrag == nil {
                    if let nodeId = hitTestNode(at: value.startLocation, canvasSize: canvasSize) {
                        viewModel.beginDrag(nodeId: nodeId)
                        activeDrag = .node(id: nodeId, lastTranslation: .zero)
                    } else {
                        activeDrag = .pan(start: panOffset)
                    }
                    dragMoved = false
                }
                if hypot(value.translation.width, value.translation.height) > Self.dragThreshold {
                    dragMoved = true
                }
                switch activeDrag {
                case .node(let id, let last):
                    let deltaScreen = CGSize(
                        width: value.translation.width - last.width,
                        height: value.translation.height - last.height
                    )
                    let scale = baseScale(canvasSize) * zoomScale
                    let userDelta = CGSize(width: deltaScreen.width / scale, height: deltaScreen.height / scale)
                    viewModel.updateDrag(nodeId: id, userSpaceDelta: userDelta)
                    activeDrag = .node(id: id, lastTranslation: value.translation)
                case .pan(let start):
                    panOffset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                if case .node(let id, _) = activeDrag {
                    viewModel.endDrag()
                    if !dragMoved, let node = viewModel.nodes.first(where: { $0.id == id }) {
                        viewModel.previewNode = node
                    }
                }
                activeDrag = nil
                dragMoved = false
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(Self.maxScale, max(Self.minScale, zoomAtGestureStart * value))
            }
            .onEnded { _ in
                zoomAtGestureStart = zoomScale
            }
    }

    // MARK: - Category chips & preview

    private var categoryChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(viewModel.categoryBreakdown, id: \.category.slug) { entry in
                let tint = Color(hexString: entry.category.colorHex)
                Text("\(entry.category.icon) \(entry.category.name) · \(entry.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.2), in: Capsule())
            }
        }
    }

    private func previewCard(_ node: MapNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let tint = Color(hexString: node.category.colorHex)
            Text("\(node.category.icon) \(node.category.name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint.opacity(0.2), in: Capsule())
            Text(node.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(node.body)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(4)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }
}
