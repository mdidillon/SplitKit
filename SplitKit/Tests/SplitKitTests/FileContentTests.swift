import SwiftUI
import Testing
import UniformTypeIdentifiers
import SplitKitContent
import SplitKitModel
import SplitKitWindows
@testable import SplitKit

/// File-based contents (spec §7.1, §9): the picker's file panel, Finder drops on panes and the empty
/// window, and the inline message when the file can't be opened. `FileContent` stands in for ImageViewer.
@MainActor @Suite struct FileContentTests {
    let workspace: SplitKitWorkspace
    let png = URL(filePath: "/nonexistent/photo.png")
    let broken = URL(filePath: "/nonexistent/broken.png")
    var controller: PaneDragController { workspace.dragController }

    init() throws {
        workspace = try makeWorkspace()
        try workspace.registry.register(FileContent.self, accepts: [.png])
    }

    var main: WindowID { workspace.mainWindow! }

    func object(_ content: ContentID?) -> (any PaneContent)? { content.flatMap { workspace.store[$0] } }

    /// Waits for a drop's insert, which runs after `fileDropPerform` returns.
    func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// One `TestContent` pane with its cells registered; the point `dx`/`dy` off the card's centre.
    func occupiedPane() async throws -> (pane: PaneID, content: ContentID?, card: CGRect) {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let cells = workspace.registerPaneCells(of: main)
        let leaf = try #require(workspace.mainLeaves.first)
        return (leaf.pane, leaf.content, cells.card(of: try #require(cells.cells.first { $0.pane == leaf.pane })))
    }

    // MARK: Picker

    @Test func aFileBasedTypeAsksForAFileFilteredToItsTypesAndOpensIt() async {
        var asked: [[UTType]] = []
        workspace.chooseFile = { types in asked.append(types); return png }
        await workspace.contentPicker(for: .emptyWindow).choose(FileContent.type, in: workspace)
        #expect(asked == [[.png]])
        let opened = object(workspace.mainLeaves.first?.content) as? FileContent
        #expect(opened?.receivedURL == png)
        #expect(workspace.creationFailure == nil)
    }

    @Test func cancellingTheFilePanelChangesNothing() async throws {
        workspace.chooseFile = { _ in nil }
        let before = try Migrator.encode(workspace.session)
        await workspace.contentPicker(for: .emptyWindow).choose(FileContent.type, in: workspace)
        #expect(try Migrator.encode(workspace.session) == before)
        #expect(workspace.creationFailure == nil)
    }

    @Test func aTypeWithoutAcceptsSkipsTheFilePanel() async {
        workspace.chooseFile = { _ in
            Issue.record("the file panel must not open for a type without accepts")
            return nil
        }
        await workspace.contentPicker(for: .emptyWindow).choose(TestContent.type, in: workspace)
        #expect(workspace.mainLeaves.count == 1)
    }

    @Test func aFileThatFailsInInitShowsInlineAndLeavesTheLayout() async throws {
        workspace.chooseFile = { _ in broken }
        let before = try Migrator.encode(workspace.session)
        await workspace.contentPicker(for: .emptyWindow).choose(FileContent.type, in: workspace)
        #expect(try Migrator.encode(workspace.session) == before)
        let failure = try #require(workspace.creationFailure)
        #expect(failure.site == .window(main))
        #expect(failure.message == "“broken.png” couldn't be read.")
    }

    @Test func aFailedAddBesideAPaneRemovesTheNewEmptyPane() async throws {
        let (pane, content, _) = try await occupiedPane()
        let before = try Migrator.encode(workspace.session)
        workspace.chooseFile = { _ in broken }
        await workspace.contentPicker(for: .besides(pane, .right)).choose(FileContent.type, in: workspace)
        #expect(workspace.mainLeaves.map(\.pane) == [pane] && workspace.mainLeaves.first?.content == content)
        #expect(try Migrator.encode(workspace.session) == before)
        #expect(workspace.creationFailure?.site == .pane(pane))
    }

    @Test func aFailedReplaceKeepsTheOldContentAndANewAttemptClearsTheMessage() async throws {
        let (pane, content, _) = try await occupiedPane()
        workspace.chooseFile = { _ in broken }
        await workspace.contentPicker(for: .replacing(pane)).choose(FileContent.type, in: workspace)
        #expect(workspace.mainLeaves.first?.content == content)
        #expect(workspace.creationFailure?.site == .pane(pane))
        workspace.chooseFile = { _ in png }
        await workspace.contentPicker(for: .replacing(pane)).choose(FileContent.type, in: workspace)
        #expect(workspace.creationFailure == nil)
        #expect(object(workspace.mainLeaves.first?.content) is FileContent)
    }

    @Test(arguments: [
        (ContentError.unsupportedFile(URL(filePath: "/x/notes.txt"), reason: "not an image file"), "“notes.txt” can't be opened: not an image file."),
        (.other("boom"), "boom"),
        (.stateIncompatible(version: 3), "The saved state (version 3) isn't compatible."),
    ] as [(ContentError, String)])
    func theMessageNamesTheFileAndTheReason(error: ContentError, message: String) {
        #expect(ChromeText.creationFailed(.creationFailed(FileContent.type, error)) == message)
    }

    // MARK: Finder drops

    @Test func aFileOverTheEmptyWindowOpensIntoIt() async throws {
        #expect(controller.fileDropHover(png, in: main, at: .zero))
        #expect(workspace.dockTarget == .emptyWindow(main))
        #expect(controller.fileDropPerform(png, in: main, at: .zero))
        try await eventually { !workspace.mainLeaves.isEmpty }
        #expect((object(workspace.mainLeaves.first?.content) as? FileContent)?.receivedURL == png)
        #expect(workspace.dockTarget == nil)
    }

    @Test func aFileOverTheCentreOfAnEmptyPaneFillsIt() async throws {
        try await workspace.addContent(TestContent.type, url: nil, into: nil)
        let first = try #require(workspace.mainLeaves.first)
        try await workspace.perform(.split(first.pane, edge: .right))
        let cells = workspace.registerPaneCells(of: main)
        let empty = try #require(workspace.mainLeaves.first { $0.content == nil }?.pane)
        let card = cells.card(of: try #require(cells.cells.first { $0.pane == empty }))
        let centre = CGPoint(x: card.midX, y: card.midY)
        #expect(controller.fileDropHover(png, in: main, at: centre))
        #expect(workspace.dockTarget == .pane(empty, .center))
        #expect(controller.fileDropPerform(png, in: main, at: centre))
        try await eventually { workspace.mainLeaves.allSatisfy { $0.content != nil } }
        #expect(workspace.mainLeaves.map(\.pane) == [first.pane, empty])
        #expect(workspace.mainLeaves.first?.content == first.content)
        #expect(object(workspace.mainLeaves.last?.content) is FileContent)
    }

    @Test func aFileOverTheCentreOfAnOccupiedPaneReplacesItsContent() async throws {
        let (pane, content, card) = try await occupiedPane()
        let centre = CGPoint(x: card.midX, y: card.midY)
        #expect(controller.fileDropHover(png, in: main, at: centre))
        #expect(controller.fileDropPerform(png, in: main, at: centre))
        try await eventually { workspace.mainLeaves.first?.content != content }
        #expect(workspace.mainLeaves.map(\.pane) == [pane])
        #expect(object(workspace.mainLeaves.first?.content) is FileContent)
        #expect(workspace.store[content!] == nil)
    }

    @Test func aFileOverAnEdgeSplitsBesideThePane() async throws {
        let (pane, content, card) = try await occupiedPane()
        let edge = CGPoint(x: card.minX + 4, y: card.midY)
        #expect(controller.fileDropHover(png, in: main, at: edge))
        #expect(workspace.dockTarget == .pane(pane, .left))
        #expect(controller.fileDropPerform(png, in: main, at: edge))
        try await eventually { workspace.mainLeaves.count == 2 && workspace.mainLeaves.allSatisfy { $0.content != nil } }
        #expect(workspace.mainLeaves.map(\.pane).contains(pane))
        #expect(workspace.mainLeaves.first { $0.pane == pane }?.content == content)
        #expect(workspace.mainLeaves.first?.pane != pane, "dropped on the left edge: the new pane is first")
    }

    @Test func aFileNoTypeOpensIsNotAValidDrop() async throws {
        let (_, _, card) = try await occupiedPane()
        let centre = CGPoint(x: card.midX, y: card.midY)
        let text = URL(filePath: "/nonexistent/notes.txt")
        #expect(!controller.fileDropHover(text, in: main, at: centre))
        #expect(workspace.dockTarget == nil)
        #expect(!controller.fileDropPerform(text, in: main, at: centre))
        #expect(!controller.fileDropHover(png, in: main, at: CGPoint(x: -50, y: -50)), "outside every pane")
    }

    @Test func leavingTheWindowClearsTheDropZone() async throws {
        let (_, _, card) = try await occupiedPane()
        #expect(controller.fileDropHover(png, in: main, at: CGPoint(x: card.midX, y: card.midY)))
        #expect(workspace.dockTarget != nil)
        controller.fileDropExited(window: main)
        #expect(workspace.dockTarget == nil)
    }

    @Test func aDroppedFileThatFailsShowsInlineAndKeepsTheOldContent() async throws {
        let (pane, content, card) = try await occupiedPane()
        let centre = CGPoint(x: card.midX, y: card.midY)
        #expect(controller.fileDropPerform(broken, in: main, at: centre))
        try await eventually { workspace.creationFailure != nil }
        #expect(workspace.creationFailure?.site == .pane(pane))
        #expect(workspace.mainLeaves.first?.content == content)
    }

    @Test func aClosingPaneTakesNoFile() async throws {
        let (pane, _, card) = try await occupiedPane()
        try workspace.commit(.beginClose(pane))
        #expect(!controller.fileDropHover(png, in: main, at: CGPoint(x: card.midX, y: card.midY)))
    }
}
