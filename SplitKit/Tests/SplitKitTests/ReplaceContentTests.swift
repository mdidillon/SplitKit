import Foundation
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// Pane ▸ Replace Content… (spec §6.3.6): create first, then the two-stage close, then `commitReplace`.
@MainActor @Suite struct ReplaceContentTests {
    let workspace: SplitKitWorkspace
    var main: WindowID { workspace.mainLayout.id }

    init() throws {
        workspace = try makePersistentWorkspace(.disabled, types: [OtherContent.self, FailingContent.self, PickyContent.self])
        _ = workspace.restoreOrOpenDefault()
    }

    /// A TestContent in the main window next to an empty pane: H[pane, empty].
    func addTest() async throws -> (pane: PaneID, content: ContentID, object: TestContent) {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let (pane, content) = try #require(workspace.mainLeaves.first)
        try await workspace.perform(.split(pane, edge: .right))
        return (pane, try #require(content), try #require(workspace.store[content!] as? TestContent))
    }

    /// Runs `replace` while answering the placeholder confirmation it shows with `confirmed`.
    func replacingPlaceholder(_ pane: PaneID, confirmed: Bool) async throws -> (replaced: Bool, prompt: ClosePrompt?) {
        let task = Task { try await workspace.replaceContent(pane, with: OtherContent.type, url: nil) }
        await waitUntil("the placeholder confirmation") { workspace.closePrompt != nil }
        let prompt = workspace.closePrompt
        if let prompt { workspace.answer(prompt, confirmed: confirmed) }
        return (try await task.value, prompt)
    }

    func state() throws -> (Data, WorkspaceRuntime) { (try Migrator.encode(workspace.session), workspace.runtime) }

    @Test func acceptedKeepsPanePositionAndFractionAndReleasesTheOldContent() async throws {
        let (pane, old, oldObject) = try await addTest()
        try await workspace.perform(.resize(splitID: try #require(workspace.mainLayout.root?.splitID), fractions: [0.7, 0.3]))
        let replaced = try await workspace.replaceContent(pane, with: OtherContent.type, url: nil)

        #expect(replaced)
        let leaves = workspace.mainLeaves
        #expect(leaves.count == 2 && leaves[0].pane == pane && leaves[1].content == nil)
        let new = try #require(leaves[0].content)
        #expect(new != old)
        #expect(workspace.mainLayout.root?.shape == "H(p,p)" && workspace.mainLayout.root?.splitFractions == [0.7, 0.3])
        #expect(oldObject.shouldCloseCalls == 1 && oldObject.willReleaseCalls == 1)
        #expect(workspace.store[old] == nil && workspace.store[new] is OtherContent)
        #expect(workspace.session.contents.map(\.id) == [new])
        #expect(workspace.session.contents.first?.type == OtherContent.type)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func declinedDropsTheNewObjectAndChangesNothing() async throws {
        let (pane, _, oldObject) = try await addTest()
        oldObject.acceptsClose = false
        let before = try state()
        let replaced = try await workspace.replaceContent(pane, with: OtherContent.type, url: nil)

        #expect(!replaced)
        #expect(oldObject.shouldCloseCalls == 1 && oldObject.willReleaseCalls == 0)
        #expect(workspace.store.objects.count == 1, "the new object was never hosted")
        let after = try state()
        #expect(after.0 == before.0 && after.1 == before.1, "session and runtime, pending closes included, are as before")
    }

    @Test func aCreationFailureChangesNothingAndAsksNobody() async throws {
        let (pane, _, oldObject) = try await addTest()
        let before = try state()
        for (type, url) in [(FailingContent.type, URL?.none), (PickyContent.type, URL(filePath: "/tmp/file.txt"))] {
            await #expect(throws: RegistryError.self) { try await workspace.replaceContent(pane, with: type, url: url) }
        }
        await #expect(throws: RegistryError.self) { try await workspace.replaceContent(pane, with: ContentType(raw: "unregistered"), url: nil) }
        #expect(oldObject.shouldCloseCalls == 0 && oldObject.willReleaseCalls == 0)
        let after = try state()
        #expect(after.0 == before.0 && after.1 == before.1)
    }

    @Test func anEmptyOrUnknownPaneChangesNothing() async throws {
        let (_, _, oldObject) = try await addTest()
        let empty = workspace.mainLeaves[1].pane
        let before = try state()
        await #expect(throws: RegistryError.self) { try await workspace.replaceContent(empty, with: OtherContent.type, url: nil) }
        await #expect(throws: RegistryError.self) { try await workspace.replaceContent(PaneID(raw: UUID()), with: OtherContent.type, url: nil) }
        #expect(oldObject.shouldCloseCalls == 0)
        let after = try state()
        #expect(after.0 == before.0 && after.1 == before.1)
    }

    @Test func aPaneInAPendingCloseCannotBeReplaced() async throws {
        let (pane, _, oldObject) = try await addTest()
        try workspace.commit(.beginClose(pane))
        let before = try state()
        await #expect(throws: RegistryError.self) { try await workspace.replaceContent(pane, with: OtherContent.type, url: nil) }
        #expect(oldObject.shouldCloseCalls == 0)
        let after = try state()
        #expect(after.0 == before.0 && after.1 == before.1)
    }

    @Test func aPlaceholderIsReplacedAfterSplitKitsOwnConfirmation() async throws {
        let (pane, old) = try workspace.addPlaceholder()
        let (replaced, prompt) = try await replacingPlaceholder(pane, confirmed: true)

        #expect(replaced && prompt?.kind == .placeholder(typeName: "test.missing"))
        let new = try #require(workspace.mainLeaves.first?.content)
        #expect(workspace.mainLeaves.first?.pane == pane && new != old)
        #expect(workspace.session.contents.map(\.id) == [new] && workspace.record(new)?.availability == .hosted)
        #expect(workspace.store[new] is OtherContent)
        #expect(workspace.runtime == WorkspaceRuntime())
    }

    @Test func aDeclinedPlaceholderConfirmationKeepsThePlaceholder() async throws {
        let (pane, old) = try workspace.addPlaceholder()
        let before = try state()
        let (replaced, prompt) = try await replacingPlaceholder(pane, confirmed: false)

        #expect(!replaced && prompt != nil)
        #expect(workspace.mainLeaves.first?.content == old && workspace.store.objects.isEmpty)
        let after = try state()
        #expect(after.0 == before.0 && after.1 == before.1)
    }

    // MARK: The picker's replace mode (same component as Add Content)

    @Test func theMenuItemOpensThePickerInReplaceModeAndChoosingReplaces() async throws {
        let (pane, old, oldObject) = try await addTest()
        let model = workspace.paneMenuModel(for: pane, content: old)
        #expect(model.isEnabled(.replaceContent) && model.title(.replaceContent) == "Replace Content…")
        await model.run(.replaceContent, in: workspace)
        #expect(workspace.addContentRequest == main && workspace.replaceContentRequest == pane)
        #expect(workspace.addContentTarget(in: main) == .replacing(pane))
        #expect(workspace.contentPicker(for: .replacing(pane)).isEnabled)

        await workspace.chooseRequestedContent(OtherContent.type, in: main)
        #expect(workspace.addContentRequest == nil && workspace.replaceContentRequest == nil)
        #expect(workspace.mainLeaves.first?.pane == pane && oldObject.willReleaseCalls == 1)
        #expect(workspace.mainLeaves.first?.content.flatMap { workspace.store[$0] } is OtherContent)
    }

    @Test func cancellingThePickerLeavesNothingBehindAndTheNextAddIsAnAdd() async throws {
        let (pane, old, _) = try await addTest()
        workspace.requestReplaceContent(of: pane)
        workspace.cancelAddContent(in: main)
        #expect(workspace.replaceContentRequest == nil)
        workspace.requestReplaceContent(of: pane)
        workspace.requestAddContent(in: main)
        #expect(workspace.replaceContentRequest == nil && workspace.addContentTarget(in: main) != .replacing(pane))
        #expect(workspace.mainLeaves.first?.content == old)
    }

    @Test func aPendingCloseDisablesReplaceInThePicker() async throws {
        let (pane, _, _) = try await addTest()
        try workspace.commit(.beginClose(pane))
        #expect(!workspace.contentPicker(for: .replacing(pane)).isEnabled)
    }
}

private extension LayoutNode {
    var splitID: SplitID? {
        if case let .split(id, _, _, _) = self { id } else { nil }
    }
    var splitFractions: [Double]? {
        if case let .split(_, _, _, fractions) = self { fractions } else { nil }
    }
}
