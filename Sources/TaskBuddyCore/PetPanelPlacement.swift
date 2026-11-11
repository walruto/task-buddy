import Foundation

public enum BubblePlacementSide: Equatable, Sendable {
    case left
    case right
}

public enum PetPanelPlacement {
    public static func bubbleSide(
        for buddyFrame: CGRect,
        openWidth: CGFloat,
        in visibleFrame: CGRect
    ) -> BubblePlacementSide {
        let extraWidth = max(0, openWidth - buddyFrame.width)
        let leftSpace = buddyFrame.minX - visibleFrame.minX
        let rightSpace = visibleFrame.maxX - buddyFrame.maxX
        if leftSpace >= extraWidth { return .left }
        if rightSpace >= extraWidth { return .right }
        return rightSpace > leftSpace ? .right : .left
    }

    public static func openFrame(
        around buddyFrame: CGRect,
        openSize: CGSize,
        side: BubblePlacementSide
    ) -> CGRect {
        CGRect(
            x: side == .right ? buddyFrame.minX : buddyFrame.maxX - openSize.width,
            y: buddyFrame.minY,
            width: openSize.width,
            height: openSize.height
        )
    }

    public static func buddyFrame(
        inside openFrame: CGRect,
        closedSize: CGSize,
        side: BubblePlacementSide
    ) -> CGRect {
        CGRect(
            x: side == .right ? openFrame.minX : openFrame.maxX - closedSize.width,
            y: openFrame.minY,
            width: closedSize.width,
            height: closedSize.height
        )
    }
}
