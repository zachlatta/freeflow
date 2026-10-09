import CoreGraphics
import Foundation

enum RecordingOverlayPlacementTests {
    static func run() {
        testSecondaryDisplayLeftOfPrimary()
        testSecondaryDisplayAbovePrimary()
        testDisplayBelowLeftWithNegativeOrigin()
        testCaretNearEachEdgeClampedInsideVisibleFrame()
        testFrameLargerThanVisibleFrame()
        testAnchorOutsideAllScreensFallsBack()
        testAXToAppKitFlipUsesPrimaryScreenHeight()
        testEntranceUsesTheAnchorScreen()
        testCachedDisplayStillConnected()
        testCachedDisplayDisconnected()
        testCachedDisplayRearranged()
    }

    /// Secondary display to the left of the primary (negative x). A caret
    /// near that display's right edge must clamp inside it, not get pulled
    /// to x = 0 on the primary.
    private static func testSecondaryDisplayLeftOfPrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let anchor = CGPoint(x: -20, y: 400)

        let chosen = RecordingOverlayPlacement.screenFrame(
            containing: anchor,
            screenFrames: [primary, left],
            fallback: primary
        )
        TestSupport.expectEqual(chosen, left)

        let frame = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: anchor,
            size: CGSize(width: 200, height: 40),
            visibleFrame: left
        )
        // proposed x = -120, which would cross maxX 0; clamp origin to -200.
        TestSupport.expectEqual(frame, CGRect(x: -200, y: 352, width: 200, height: 40))
        TestSupport.expect(frame.maxX <= left.maxX, "left-screen overlay crossed onto the primary display")
        TestSupport.expect(frame.minX >= left.minX, "left-screen overlay left its display")

        let nearLeftEdge = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: -1910, y: 500),
            size: CGSize(width: 100, height: 40),
            visibleFrame: left
        )
        TestSupport.expectEqual(nearLeftEdge, CGRect(x: -1920, y: 452, width: 100, height: 40))
    }

    /// Secondary display above the primary: its AppKit origin y is >= the
    /// primary height. Clamping must stay in that upper band.
    private static func testSecondaryDisplayAbovePrimary() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let above = CGRect(x: 0, y: 900, width: 1512, height: 1200)
        TestSupport.expect(above.minY >= primary.height, "fixture must sit at or above the primary top")

        let anchor = CGPoint(x: 200, y: 2088)
        let chosen = RecordingOverlayPlacement.screenFrame(
            containing: anchor,
            screenFrames: [primary, above],
            fallback: primary
        )
        TestSupport.expectEqual(chosen, above)

        // Menu-bar inset: visible area starts at the screen origin and stops
        // 24pt below the top of this display.
        let visible = CGRect(x: 0, y: 900, width: 1512, height: 1176)
        let frame = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: anchor,
            size: CGSize(width: 160, height: 40),
            visibleFrame: visible
        )
        TestSupport.expectEqual(frame, CGRect(x: 120, y: 2036, width: 160, height: 40))
        TestSupport.expect(frame.minY >= primary.height, "above-screen overlay was clamped down onto the primary")
        TestSupport.expect(frame.maxY <= visible.maxY, "above-screen overlay escaped the visible frame")
    }

    /// Display below and left of the primary, so both origin components are
    /// negative. Bottom-edge clamp stays on that display.
    private static func testDisplayBelowLeftWithNegativeOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let belowLeft = CGRect(x: -1600, y: -1200, width: 1600, height: 1000)
        TestSupport.expect(belowLeft.minX < 0 && belowLeft.minY < 0, "fixture origin must be negative in both axes")

        let anchor = CGPoint(x: -80, y: -1180)
        let chosen = RecordingOverlayPlacement.screenFrame(
            containing: anchor,
            screenFrames: [primary, belowLeft],
            fallback: primary
        )
        TestSupport.expectEqual(chosen, belowLeft)

        let frame = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: anchor,
            size: CGSize(width: 120, height: 36),
            visibleFrame: belowLeft
        )
        TestSupport.expectEqual(frame, CGRect(x: -140, y: -1200, width: 120, height: 36))
        TestSupport.expect(frame.maxY <= belowLeft.maxY, "below-screen overlay climbed out of its display")
        TestSupport.expect(frame.minY >= belowLeft.minY, "below-screen overlay left its display")
    }

    private static func testCaretNearEachEdgeClampedInsideVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 40)

        let left = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: 10, y: 400),
            size: size,
            visibleFrame: visible
        )
        TestSupport.expectEqual(left, CGRect(x: 0, y: 352, width: 200, height: 40))

        let right = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: 990, y: 400),
            size: size,
            visibleFrame: visible
        )
        TestSupport.expectEqual(right, CGRect(x: 800, y: 352, width: 200, height: 40))

        let bottom = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: 500, y: 20),
            size: size,
            visibleFrame: visible
        )
        TestSupport.expectEqual(bottom, CGRect(x: 400, y: 0, width: 200, height: 40))

        // Caret in the strip just above the visible frame (menu bar). The
        // overlay is placed below the caret and still has to be pulled back
        // inside the visible frame.
        let top = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: 500, y: 810),
            size: size,
            visibleFrame: visible
        )
        TestSupport.expectEqual(top, CGRect(x: 400, y: 760, width: 200, height: 40))

        for edge in [left, right, bottom, top] {
            TestSupport.expect(edge.minX >= visible.minX && edge.maxX <= visible.maxX, "horizontal clamp failed: \(edge)")
            TestSupport.expect(edge.minY >= visible.minY && edge.maxY <= visible.maxY, "vertical clamp failed: \(edge)")
        }
    }

    private static func testFrameLargerThanVisibleFrame() {
        let visible = CGRect(x: 10, y: 20, width: 100, height: 80)
        let centered = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: 60, y: 60),
            size: CGSize(width: 180, height: 120),
            visibleFrame: visible
        )
        // Too wide and too tall: center on the visible frame rather than
        // pinning the origin to minX/minY.
        TestSupport.expectEqual(centered, CGRect(x: -30, y: 0, width: 180, height: 120))

        let negativeVisible = CGRect(x: -200, y: -100, width: 50, height: 40)
        let negativeCentered = RecordingOverlayPlacement.clampedFrame(
            CGRect(x: 0, y: 0, width: 80, height: 100),
            to: negativeVisible
        )
        TestSupport.expectEqual(negativeCentered, CGRect(x: -215, y: -130, width: 80, height: 100))
    }

    private static func testAnchorOutsideAllScreensFallsBack() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let chosen = RecordingOverlayPlacement.screenFrame(
            containing: CGPoint(x: 5000, y: -5000),
            screenFrames: [primary, left],
            fallback: primary
        )
        TestSupport.expectEqual(chosen, primary)

        let empty = RecordingOverlayPlacement.screenFrame(
            containing: CGPoint(x: 10, y: 10),
            screenFrames: [],
            fallback: primary
        )
        TestSupport.expectEqual(empty, primary)
    }

    /// The y-flip uses the primary display height. The caret in this case
    /// sits on a taller display above the primary (height 1200, origin y
    /// 900); using that display's height or maxY would yield a different y.
    private static func testAXToAppKitFlipUsesPrimaryScreenHeight() {
        let primaryScreenHeight: CGFloat = 900
        let aboveScreenHeight: CGFloat = 1200
        let rect = CGRect(x: 100, y: -420, width: 20, height: 16)
        let anchor = RecordingOverlayPlacement.appKitAnchor(
            fromAXCaretRect: rect,
            primaryScreenHeight: primaryScreenHeight
        )
        TestSupport.expectEqual(anchor, CGPoint(x: 110, y: 1304))

        let usingAboveHeight = aboveScreenHeight - rect.maxY
        let usingAboveMaxY = (primaryScreenHeight + aboveScreenHeight) - rect.maxY
        TestSupport.expect(anchor.y != usingAboveHeight, "y-flip used the secondary screen height")
        TestSupport.expect(anchor.y != usingAboveMaxY, "y-flip used the secondary screen maxY")

        let onPrimary = RecordingOverlayPlacement.appKitAnchor(
            fromAXCaretRect: CGRect(x: 40, y: 10, width: 8, height: 12),
            primaryScreenHeight: primaryScreenHeight
        )
        TestSupport.expectEqual(onPrimary, CGPoint(x: 44, y: 878))

        // Caret on a display to the left keeps its negative x; y still flips
        // against the primary height only.
        let onLeft = RecordingOverlayPlacement.appKitAnchor(
            fromAXCaretRect: CGRect(x: -1500, y: 300, width: 10, height: 20),
            primaryScreenHeight: primaryScreenHeight
        )
        TestSupport.expectEqual(onLeft, CGPoint(x: -1495, y: 580))
    }

    /// Settled frame and the lifted entrance frame are both clamped to the
    /// anchor's visible frame. Clamping that same entrance rect to the
    /// primary display is what slides a left-display overlay across monitors.
    private static func testEntranceUsesTheAnchorScreen() {
        let primaryVisible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let leftVisible = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        let settled = RecordingOverlayPlacement.nearCursorOverlayFrame(
            anchor: CGPoint(x: -400, y: 500),
            size: CGSize(width: 200, height: 40),
            visibleFrame: leftVisible
        )
        let lifted = CGRect(
            x: settled.origin.x,
            y: settled.origin.y + settled.height,
            width: settled.width,
            height: settled.height
        )
        let entrance = RecordingOverlayPlacement.clampedFrame(lifted, to: leftVisible)
        let clampedToPrimary = RecordingOverlayPlacement.clampedFrame(lifted, to: primaryVisible)

        TestSupport.expectEqual(settled, CGRect(x: -500, y: 452, width: 200, height: 40))
        TestSupport.expectEqual(entrance, CGRect(x: -500, y: 492, width: 200, height: 40))
        TestSupport.expect(entrance.minX < 0, "entrance left the anchor display")
        TestSupport.expect(clampedToPrimary.minX >= 0, "fixture: primary clamp should pull a left-display frame across")
        TestSupport.expect(entrance.minX != clampedToPrimary.minX, "entrance matched the primary-screen clamp")
    }

    /// The cached anchor's display is still connected: it is found by ID,
    /// wherever it sits in the screen list.
    private static func testCachedDisplayStillConnected() {
        let connected: [CGDirectDisplayID?] = [1, 7, 42]
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: connected),
            2
        )
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 1, in: connected),
            0
        )
    }

    /// The cached display was unplugged mid-show. It must not be reused, so
    /// the caller re-anchors on a live screen instead of placing the overlay
    /// on the vanished display's coordinates.
    private static func testCachedDisplayDisconnected() {
        let afterDisconnect: [CGDirectDisplayID?] = [1]
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: afterDisconnect),
            nil
        )
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: []),
            nil
        )
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: nil, in: [1, 42]),
            nil
        )
        // A screen without an ID never stands in for the cached display.
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: [nil, 1]),
            nil
        )
    }

    /// Rearranging displays changes frames and list order but not IDs; the
    /// cached display still resolves, at its new index.
    private static func testCachedDisplayRearranged() {
        let before: [CGDirectDisplayID?] = [1, 42]
        let after: [CGDirectDisplayID?] = [42, 1]
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: before),
            1
        )
        TestSupport.expectEqual(
            RecordingOverlayPlacement.connectedDisplayIndex(of: 42, in: after),
            0
        )
    }
}
