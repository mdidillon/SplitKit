import SwiftUI
import Testing
import SplitKitContent
import SplitKitModel
@testable import SplitKit

/// The one content picker behind every Add Content (spec §7.1): its entries and what choosing does for each
/// target (empty window, empty pane, beside an occupied pane).
@MainActor @Suite struct ContentPickerTests {
    let workspace: SplitKitWorkspace

    init() throws {
        workspace = try makeWorkspace()
        try workspace.registry.register(OtherContent.self)
    }

    func object(_ content: ContentID?) -> (any PaneContent)? { content.flatMap { workspace.store[$0] } }

    @Test func listsRegisteredTypesInRegistryOrder() {
        let entries = workspace.contentPicker(for: .emptyWindow).entries
        #expect(entries.map(\.type) == [TestContent.type, FailingContent.type, OtherContent.type])
        #expect(entries.map(\.displayName) == ["Test", "Failing", "Other"])
        #expect(entries.map(\.systemImage) == ["square", "xmark.octagon", "circle"])
    }

    @Test func choosingInsertsTheTypeIntoTheEmptyWindow() async {
        await workspace.contentPicker(for: .emptyWindow).choose(OtherContent.type, in: workspace)
        #expect(workspace.mainLeaves.count == 1)
        #expect(object(workspace.mainLeaves.first?.content) is OtherContent)
    }

    @Test func choosingInsertsTheTypeIntoTheEmptyPane() async throws {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let first = try #require(workspace.mainLeaves.first)
        try await workspace.perform(.split(first.pane, edge: .right))
        let empty = try #require(workspace.mainLeaves.first { $0.content == nil }?.pane)
        await workspace.contentPicker(for: .emptyPane(empty)).choose(OtherContent.type, in: workspace)
        #expect(workspace.mainLeaves.map(\.pane) == [first.pane, empty])
        #expect(workspace.mainLeaves.first?.content == first.content)
        #expect(object(workspace.mainLeaves.last?.content) is OtherContent)
    }

    @Test func choosingInsertsTheTypeBesideAnOccupiedPane() async throws {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let first = try #require(workspace.mainLeaves.first)
        await workspace.contentPicker(for: .besides(first.pane, .right)).choose(OtherContent.type, in: workspace)
        #expect(workspace.mainLeaves.count == 2)
        #expect(workspace.mainLeaves.first?.pane == first.pane && workspace.mainLeaves.first?.content == first.content)
        #expect(object(first.content) is TestContent)
        #expect(object(workspace.mainLeaves.last?.content) is OtherContent)
    }

    @Test func aTypeThatFailsToCreateLeavesTheWorkspaceUnchanged() async throws {
        let before = try Migrator.encode(workspace.session)
        await workspace.contentPicker(for: .emptyWindow).choose(FailingContent.type, in: workspace)
        #expect(try Migrator.encode(workspace.session) == before)
        #expect(workspace.store.objects.isEmpty)
    }

    @Test func isDisabledWithoutTypesAndWhileTheTargetIsClosing() async throws {
        let bare = SplitKitWorkspace(registry: ContentRegistry(), configuration: SplitKitConfiguration(persistence: .disabled),
                                     ids: SeededIDGenerator(seed: 1))
        _ = bare.restoreOrOpenDefault()
        #expect(!bare.contentPicker(for: .emptyWindow).isEnabled)

        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let pane = try #require(workspace.mainLeaves.first?.pane)
        #expect(workspace.contentPicker(for: .besides(pane, .right)).isEnabled)
        try workspace.commit(.beginClose(pane))
        let picker = workspace.contentPicker(for: .besides(pane, .right))
        #expect(picker.isPending && !picker.isEnabled)
        let before = try Migrator.encode(workspace.session)
        await picker.choose(OtherContent.type, in: workspace)
        #expect(try Migrator.encode(workspace.session) == before)
    }

    @Test func theEmptyStatesAndThePaneMenuUseTheSamePicker() async throws {
        #expect(workspace.paneMenuModel(for: PaneID(raw: UUID()), content: nil).picker.entries
                == workspace.contentPicker(for: .emptyWindow).entries)
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let pane = try #require(workspace.mainLeaves.first?.pane)
        #expect(workspace.paneMenuModel(for: pane, content: workspace.mainLeaves.first?.content).picker.target
                == .besides(pane, .right))
        try await workspace.perform(.split(pane, edge: .right))
        let empty = try #require(workspace.mainLeaves.first { $0.content == nil }?.pane)
        #expect(workspace.paneMenuModel(for: empty, content: nil).picker.target == .emptyPane(empty))
    }

    @Test func emptyStatesRender() async throws {
        let view = SplitKitView(workspace: workspace, window: workspace.mainLayout.id)
        host(view)
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let pane = try #require(workspace.mainLeaves.first?.pane)
        try await workspace.perform(.split(pane, edge: .right))
        host(view)
    }
}
