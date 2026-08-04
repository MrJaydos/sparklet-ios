import SwiftUI
import UIKit

// Thin UICollectionViewCell wrapper — UIHostingConfiguration (iOS 16+) does
// the actual SwiftUI-content-in-a-cell work, including handling reuse
// identity correctly, so there's no bespoke UIHostingController child-VC
// lifecycle to manage here.
final class FeedPagingCell: UICollectionViewCell {
    static let reuseIdentifier = "FeedPagingCell"

    func configure<V: View>(@ViewBuilder content: () -> V) {
        contentConfiguration = UIHostingConfiguration {
            content()
        }
        // Default UIHostingConfiguration margins would inset the content
        // away from the cell's edges — every item kind here is meant to
        // fill its page exactly (each already applies its own internal
        // padding), so those margins would just double up.
        .margins(.all, 0)
    }
}
