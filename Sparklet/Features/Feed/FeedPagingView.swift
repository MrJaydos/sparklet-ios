import SwiftUI
import UIKit

// A UIKit-backed replacement for the vertical paging ScrollView + LazyVStack
// + .scrollTargetBehavior(.paging) FeedView used to use. That approach let
// each item's SwiftUI-computed height (.containerRelativeFrame(.vertical))
// drift out of agreement with the actual per-swipe scroll distance
// .scrollTargetBehavior(.paging) computed — the root cause of two
// live-confirmed bugs (a persistent sliver of the next item peeking at the
// bottom of every page, and a worse regression where the PREVIOUS item's
// content bled into the top of the screen on some pages). A plain
// UICollectionView with isPagingEnabled = true has no such drift: paging
// scrolls in increments of the scroll view's own bounds.height, and every
// cell is sized to that exact same bounds.size (FeedPagingLayout below), so
// "one page" and "one swipe" are the same number by construction.
struct FeedPagingView<Content: View>: UIViewRepresentable {
    let items: [FeedItem]
    @Binding var visibleCardId: String?
    // Mirrors FeedView's old `@State private var scrollProxy:
    // ScrollViewProxy?` + `.onAppear { scrollProxy = proxy }` pattern —
    // called once from makeUIView so FeedView can trigger programmatic
    // jumps (advanceToNextItem, the goal-reached re-snap, and the
    // load()/refresh()/filter-apply/reconcile reseeds) the same way it used
    // to call scrollProxy?.scrollTo(id:anchor:).
    let onProxyReady: (FeedPagingProxy) -> Void
    // A plain UIRefreshControl on this collection view, unlike the old
    // SwiftUI ScrollView + .scrollTargetBehavior(.paging) combination (see
    // FeedView's now-removed refresh button comment) — isPagingEnabled only
    // affects snap behavior once a drag ends, not the initial overscroll
    // drag itself, so UIRefreshControl's own pull gesture never had a
    // conflict to begin with here. Requested directly by the user in favor
    // of the header's explicit refresh button, which is now gone.
    let onRefresh: () async -> Void
    @ViewBuilder let content: (FeedItem, Bool) -> Content

    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: FeedPagingLayout())
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        // A fixed floating header sits above this collection view via
        // FeedView's own VStack, not as a safe-area inset here — this just
        // keeps the system keyboard/notch safe-area machinery from
        // perturbing page geometry the way the old ScrollView's interaction
        // with safe areas did.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = context.coordinator
        collectionView.register(FeedPagingCell.self, forCellWithReuseIdentifier: FeedPagingCell.reuseIdentifier)

        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .white
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        let coordinator = context.coordinator
        coordinator.onRefresh = onRefresh
        let dataSource = UICollectionViewDiffableDataSource<Int, FeedItem>(collectionView: collectionView) { collectionView, indexPath, item in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPagingCell.reuseIdentifier, for: indexPath) as! FeedPagingCell
            cell.configure {
                coordinator.content?(item, item.id == coordinator.currentVisibleId)
            }
            return cell
        }
        coordinator.collectionView = collectionView
        coordinator.dataSource = dataSource
        coordinator.content = content
        coordinator.currentVisibleId = visibleCardId
        coordinator.onVisibleIdChange = { id in visibleCardId = id }

        var snapshot = NSDiffableDataSourceSnapshot<Int, FeedItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
        coordinator.lastItems = items

        // Deferred to the next run loop tick rather than called inline:
        // makeUIView runs synchronously as part of SwiftUI's own view-update
        // pass, and onProxyReady's whole job is writing back to a @State
        // var on FeedView (pagingProxy) — mutating state synchronously
        // during a view update is exactly the "modifying state during view
        // update, this will cause undefined behavior" trap, and was
        // confirmed live to silently no-op (a debug label reading
        // pagingProxy straight from FeedView's body stayed nil indefinitely
        // when this call was inline). The old ScrollViewReader equivalent
        // never hit this because .onAppear{ scrollProxy = proxy } fires
        // after the view has actually appeared, not during the render pass.
        let proxy = FeedPagingProxy { id, animated in
            coordinator.scrollTo(id: id, animated: animated)
        }
        DispatchQueue.main.async {
            onProxyReady(proxy)
        }

        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.content = content
        coordinator.currentVisibleId = visibleCardId
        coordinator.onRefresh = onRefresh

        let old = coordinator.lastItems
        guard items != old else { return }

        var snapshot = NSDiffableDataSourceSnapshot<Int, FeedItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)

        // Append (infinite-load growth — FeedViewModel.loadMoreIfNeeded):
        // old items are an exact prefix of the new ones. Animate — the
        // diffable data source preserves the current scroll position for
        // the unaffected existing cells on its own, no manual re-snap
        // needed (unlike the old ScrollView approach, which needed
        // scrollProxy?.scrollTo after a mid-feed insert to fix a similar
        // case — see FeedView.applyXpAndCheckGoal's history).
        let isAppend = items.count > old.count && Array(items.prefix(old.count)) == old
        coordinator.dataSource?.apply(snapshot, animatingDifferences: isAppend)
        coordinator.lastItems = items

        // Reset (load()/refresh()/filter-apply/reconcile replacing the
        // whole batch): mirrors the old `visibleCardId = items.first?.id`
        // reseed — jump to the top, no animation.
        if !isAppend, let firstId = items.first?.id {
            coordinator.scrollTo(id: firstId, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        weak var collectionView: UICollectionView?
        var dataSource: UICollectionViewDiffableDataSource<Int, FeedItem>?
        var content: ((FeedItem, Bool) -> Content)?
        var onVisibleIdChange: ((String?) -> Void)?
        var onRefresh: (() async -> Void)?
        var currentVisibleId: String?
        var lastItems: [FeedItem] = []

        @objc func handleRefresh() {
            Task { @MainActor in
                await onRefresh?()
                self.collectionView?.refreshControl?.endRefreshing()
            }
        }

        func scrollTo(id: String, animated: Bool) {
            guard let item = lastItems.first(where: { $0.id == id }),
                  let indexPath = dataSource?.indexPath(for: item)
            else { return }
            // scrollToItem silently no-ops for an index path the layout
            // hasn't measured yet (e.g. right after a snapshot apply, or
            // for a far-away index never scrolled near before) unless the
            // collection view's layout is forced up to date first.
            collectionView?.layoutIfNeeded()
            collectionView?.scrollToItem(at: indexPath, at: .top, animated: animated)
            if !animated {
                // A non-animated scrollToItem doesn't fire
                // scrollViewDidEndScrollingAnimation, so update directly.
                updateVisibleItem()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateVisibleItem()
        }

        // A drag too slow/short to trigger deceleration still settles on a
        // page and needs the same bookkeeping scrollViewDidEndDecelerating
        // would otherwise do.
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { updateVisibleItem() }
        }

        // Covers the animated branch of scrollTo(id:animated:) above.
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateVisibleItem()
        }

        private func updateVisibleItem() {
            guard let collectionView, collectionView.bounds.height > 0 else { return }
            // Exact, not an estimate: isPagingEnabled scrolls in increments
            // of collectionView.bounds.height, and FeedPagingLayout sizes
            // every cell to that exact same value, so this division always
            // lands on a whole page index.
            let index = Int((collectionView.contentOffset.y / collectionView.bounds.height).rounded())
            guard index >= 0, index < lastItems.count else { return }
            let id = lastItems[index].id
            guard id != currentVisibleId else { return }
            currentVisibleId = id
            onVisibleIdChange?(id)
            // UIHostingConfiguration's content closure is evaluated once
            // when a cell's contentConfiguration is set, not continuously —
            // reconfiguring the newly-visible item (and the one that just
            // stopped being visible, so it re-renders isVisible: false too)
            // is what actually threads the new isVisible value through to
            // CardView, the only consumer of it (its one-shot depth-
            // preference auto-apply). This must go through the diffable
            // data source's own snapshot mechanism (reconfigureItems), not
            // a raw collectionView.reloadItems(at:) call — mixing direct
            // UICollectionView mutation calls with an attached diffable
            // data source is unsupported and crashed live (twice: once
            // called synchronously, still crashed after deferring one run
            // loop tick with DispatchQueue.main.async) with
            // "-[UICollectionView reloadItemsAtIndexPaths:] ... assertion
            // failure" both times — the data source's own snapshot apply
            // was interleaving with the raw call.
            guard let dataSource else { return }
            var snapshot = dataSource.snapshot()
            // Reconfigure every currently-visible cell, not just the newly-
            // current one — the cell that just stopped being visible needs
            // to re-render with isVisible: false too.
            let visibleIds = Set(collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0)?.id })
            let idsToReconfigure = visibleIds.union([id])
            let itemsToReconfigure = idsToReconfigure.compactMap { rid in lastItems.first(where: { $0.id == rid }) }
            snapshot.reconfigureItems(itemsToReconfigure)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
}

// The direct replacement for every old `scrollProxy?.scrollTo(id, anchor:
// .top)` call site in FeedView.swift.
struct FeedPagingProxy {
    let scrollTo: (String, Bool) -> Void
}

// itemSize always equals the collection view's own bounds — this, combined
// with isPagingEnabled on the collection view itself, is what makes "one
// page" and "one swipe" the same number by construction (see the type
// comment on FeedPagingView above for why that's the whole point of this
// file).
private final class FeedPagingLayout: UICollectionViewFlowLayout {
    override init() {
        super.init()
        scrollDirection = .vertical
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepare() {
        super.prepare()
        if let bounds = collectionView?.bounds, bounds.size != itemSize {
            itemSize = bounds.size
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}
