import CoreGraphics

enum SetupWindowLayoutTests {
    static func run() {
        // Roomy screens keep the original onboarding size.
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: 1_000), 680)
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: 680), 680)
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: nil), 680)

        // Short or scaled screens shrink the window to the visible frame so the
        // Continue button stays on screen (#342).
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: 600.5), 600)
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: 300), SetupWindowLayout.minimumContentHeight)
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: 0), 680)
        TestSupport.expectEqual(SetupWindowLayout.contentHeight(forVisibleScreenHeight: .infinity), 680)

        // The provider sheet must fit inside the onboarding window.
        TestSupport.expect(
            SetupWindowLayout.providerSheetWidth < SetupWindowLayout.contentWidth,
            "Provider sheet must be narrower than the onboarding window"
        )
        TestSupport.expectEqual(SetupWindowLayout.providerSheetHeight(forParentContentHeight: 680), 520)
        TestSupport.expectEqual(SetupWindowLayout.providerSheetHeight(forParentContentHeight: 500), 420)
        TestSupport.expectEqual(SetupWindowLayout.providerSheetHeight(forParentContentHeight: 100), SetupWindowLayout.providerSheetMinimumHeight)

        for visible in stride(from: CGFloat(500), through: 1_200, by: 10) {
            let window = SetupWindowLayout.contentHeight(forVisibleScreenHeight: visible)
            TestSupport.expect(window <= visible, "Onboarding window must fit a \(visible)pt screen")
            let sheet = SetupWindowLayout.providerSheetHeight(forParentContentHeight: window)
            TestSupport.expect(
                sheet + SetupWindowLayout.providerSheetVerticalAllowance <= window,
                "Provider sheet must fit inside a \(window)pt onboarding window"
            )
        }
    }
}
