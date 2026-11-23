import CoreGraphics

/// Sizes for the onboarding window and its Advanced Provider Settings sheet.
///
/// The onboarding window used to be a fixed 520x680 and its provider sheet a
/// fixed 560x520. On short or scaled displays the window extended past the
/// screen and the sheet could not fit inside it, which hid both the sheet's
/// Done button and onboarding's Continue button (#342). These helpers keep both
/// within the space that is actually available.
enum SetupWindowLayout {
    static let contentWidth: CGFloat = 520
    static let preferredContentHeight: CGFloat = 680
    static let minimumContentHeight: CGFloat = 420

    static let providerSheetWidth: CGFloat = 480
    static let providerSheetPreferredHeight: CGFloat = 520
    static let providerSheetMinimumHeight: CGFloat = 260
    /// Space kept between the sheet and the onboarding window's edges,
    /// including the transparent title bar that overlaps the content.
    static let providerSheetVerticalAllowance: CGFloat = 80

    /// Height for the onboarding window's content, given the height of the
    /// screen's visible frame (excluding the menu bar and Dock).
    static func contentHeight(forVisibleScreenHeight available: CGFloat?) -> CGFloat {
        guard let available, available.isFinite, available > 0 else {
            return preferredContentHeight
        }
        return max(minimumContentHeight, min(preferredContentHeight, available.rounded(.down)))
    }

    /// Height for the provider sheet so it fits inside an onboarding window of
    /// the given content height.
    static func providerSheetHeight(forParentContentHeight parentHeight: CGFloat) -> CGFloat {
        guard parentHeight.isFinite, parentHeight > 0 else {
            return providerSheetPreferredHeight
        }
        let available = (parentHeight - providerSheetVerticalAllowance).rounded(.down)
        return max(providerSheetMinimumHeight, min(providerSheetPreferredHeight, available))
    }
}
