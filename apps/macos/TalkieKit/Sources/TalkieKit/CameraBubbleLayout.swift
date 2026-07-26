import Foundation

public enum CameraBubbleLayout {
    public static let screenMargin: CGFloat = 24

    public static func origin(
        for placement: CameraBubblePlacement,
        requested: CGPoint?,
        size: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = screenMargin
    ) -> CGPoint {
        switch placement {
        case .topLeading:
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - size.height - margin)
        case .topTrailing:
            CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.maxY - size.height - margin)
        case .bottomLeading:
            CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .bottomTrailing:
            CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.minY + margin)
        case .custom:
            clamped(
                requested ?? CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.minY + margin),
                size: size,
                to: visibleFrame,
                margin: margin
            )
        }
    }

    public static func clamped(
        _ origin: CGPoint,
        size: CGSize,
        to frame: CGRect,
        margin: CGFloat = screenMargin
    ) -> CGPoint {
        let minimumX = frame.minX + margin
        let maximumX = max(minimumX, frame.maxX - size.width - margin)
        let minimumY = frame.minY + margin
        let maximumY = max(minimumY, frame.maxY - size.height - margin)

        return CGPoint(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY)
        )
    }
}
