import CoreGraphics
import Foundation

/// Pure screen-geometry for the recording overlay. No AppKit, Accessibility,
/// or display server: callers pass the frames they already resolved.
enum RecordingOverlayPlacement {
    static let nearCursorOverlayGap: CGFloat = 8

    /// Converts an Accessibility caret rect into the AppKit anchor at the
    /// bottom edge of that caret.
    ///
    /// AX bounds are top-left origin, y down, relative to the primary
    /// display. AppKit is bottom-left origin, y up. `primaryScreenHeight` is
    /// the primary display's height — not the height (or maxY) of whichever
    /// display contains the caret. A secondary display left or above the
    /// primary therefore keeps its negative AX x/y in the flip.
    static func appKitAnchor(fromAXCaretRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: rect.midX, y: primaryScreenHeight - rect.maxY)
    }

    /// First screen frame that contains `anchor`, or `fallback` when the
    /// anchor is on none of them (gap, disconnected display, empty list).
    /// Points on a rect's max edges are outside, matching `CGRect.contains`.
    static func screenFrame(containing anchor: CGPoint, screenFrames: [CGRect], fallback: CGRect) -> CGRect {
        screenFrames.first { $0.contains(anchor) } ?? fallback
    }

    /// Index in `connectedDisplayIDs` of the display a cached anchor was
    /// resolved on, or nil when nothing is cached or that display has been
    /// disconnected since. Matching is by display ID, not frame, so a
    /// rearranged display still matches and a vanished one never does.
    /// Entries that are nil (screens without an ID) never match.
    static func connectedDisplayIndex(
        of cachedDisplayID: CGDirectDisplayID?,
        in connectedDisplayIDs: [CGDirectDisplayID?]
    ) -> Int? {
        guard let cachedDisplayID else { return nil }
        return connectedDisplayIDs.firstIndex { $0 == cachedDisplayID }
    }

    /// Pins `frame` inside `visibleFrame`. A frame larger than the visible
    /// area is centered on it instead of shoved against a corner — including
    /// when that visible area sits left of or below the primary display.
    static func clampedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let maxX = visibleFrame.maxX - frame.width
        let maxY = visibleFrame.maxY - frame.height

        let x: CGFloat
        if maxX >= visibleFrame.minX {
            x = min(max(frame.origin.x, visibleFrame.minX), maxX)
        } else {
            x = visibleFrame.midX - frame.width / 2
        }

        let y: CGFloat
        if maxY >= visibleFrame.minY {
            y = min(max(frame.origin.y, visibleFrame.minY), maxY)
        } else {
            y = visibleFrame.midY - frame.height / 2
        }

        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// Overlay rect just below `anchor`, then clamped to `visibleFrame`.
    /// `visibleFrame` must be the visible rect of the screen that contains
    /// the anchor so the settled frame and the entrance clamp share a display.
    static func nearCursorOverlayFrame(
        anchor: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = nearCursorOverlayGap
    ) -> CGRect {
        let proposed = CGRect(
            x: anchor.x - size.width / 2,
            y: anchor.y - gap - size.height,
            width: size.width,
            height: size.height
        )
        return clampedFrame(proposed, to: visibleFrame)
    }
}
