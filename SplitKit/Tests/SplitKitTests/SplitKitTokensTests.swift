import SwiftUI
import Testing
@testable import SplitKit

/// The token defaults equal the Docs/Design.md §2 table.
@Suite struct SplitKitTokensTests {
    @Test func glassDefaults() {
        let tokens = SplitKitTokens.glass
        #expect(tokens.metrics.headerHeight == 28)
        #expect(tokens.metrics.dividerThickness == 1)
        #expect(tokens.metrics.dividerHitWidth == 8)
        #expect(tokens.metrics.cornerRadius == 10)
        #expect(tokens.metrics.contentPadding == 4)
        #expect(tokens.glass.variant == .regular)
        #expect(tokens.glass.tint == nil)
        #expect(tokens.colors.activeIndicator == Color.accentColor)
        #expect(tokens.colors.dropHighlight == Color.accentColor)
    }

    @Test func plainDefaults() {
        let tokens = SplitKitTokens.plain
        #expect(tokens.metrics.headerHeight == 28)
        #expect(tokens.metrics.dividerThickness == 1)
        #expect(tokens.metrics.dividerHitWidth == 8)
        #expect(tokens.metrics.cornerRadius == 0)
        #expect(tokens.metrics.contentPadding == 0)
        #expect(tokens.colors.activeIndicator == Color.accentColor)
        #expect(tokens.colors.dropHighlight == Color.accentColor)
    }

    @Test(arguments: [SplitKitTokens.glass, .plain])
    func hitWidthCoversThickness(_ tokens: SplitKitTokens) {
        #expect(tokens.metrics.dividerHitWidth >= tokens.metrics.dividerThickness)
    }

    @Test func glassVariantAndTintMapToGlass() {
        var glass = SplitKitTokens.glass.glass
        #expect(glass.effect == Glass.regular.tint(nil))
        glass.variant = .clear
        glass.tint = .orange
        #expect(glass.effect == Glass.clear.tint(.orange))
    }

    @Test func tokensAreValueTypes() {
        var tokens = SplitKitTokens.glass
        tokens.metrics.cornerRadius = 0
        #expect(tokens != .glass)
        #expect(SplitKitTokens.glass.metrics.cornerRadius == 10)
    }
}
