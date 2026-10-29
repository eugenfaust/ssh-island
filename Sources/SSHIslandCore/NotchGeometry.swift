import Foundation
import CoreGraphics

public struct NotchGeometry: Equatable, Sendable {
    public let centerX: CGFloat
    public let top: CGFloat
    public let width: CGFloat
    public let depth: CGFloat
    public static func detect(frame: CGRect, builtIn: Bool, topInset: CGFloat, left: CGRect?, right: CGRect?) -> Self? {
        guard builtIn, topInset > 0, topInset < 100, let left, let right,
              abs(left.maxY - frame.maxY) < 2, abs(right.maxY - frame.maxY) < 2,
              left.maxX < right.minX else { return nil }
        let width = right.minX - left.maxX
        let center = (left.maxX + right.minX) / 2
        guard width > 40, width < 400, abs(center - frame.midX) < 10 else { return nil }
        return Self(centerX: center, top: frame.maxY, width: width, depth: topInset)
    }
    public func panelFrame(width: CGFloat, contentHeight: CGFloat) -> CGRect {
        // One silhouette from the display top in every state; the view reserves
        // `depth` above its controls so only the black surface covers the menu bar.
        CGRect(x: centerX - width / 2, y: top - depth - contentHeight,
               width: width, height: depth + contentHeight)
    }
}
