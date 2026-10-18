import AppKit
import SwiftUI
import SplitKitContent
import SplitKitModel

// The two dummy contents of the P2 test app (spec §11 P2). Both keep their state in the object (§6.4) and
// encode it as JSON with stateVersion 1; a state they can't read throws `stateIncompatible`.

/// Decodes a dummy's saved state, or nil for a new content.
private func decodeState<State: Decodable>(_ type: State.Type, from data: Data?, stateVersion: Int?) throws(ContentError) -> State? {
    guard let data else { return nil }
    guard stateVersion == 1, let state = try? JSONDecoder().decode(State.self, from: data) else {
        throw .stateIncompatible(version: stateVersion ?? 0)
    }
    return state
}

/// A pane filled with one system colour, picked at random when the content is new; the toolbar changes it
/// (Next Colour, or Choose Colour ▸). State: the colour's name; the header title shows it.
@MainActor @Observable
final class ColorContent: PaneContent {
    static let type = ContentType(raw: "com.mdidillon.SplitKitTestApp.color")
    static let displayName = "Colour"
    static let systemImage = "paintpalette"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    /// The palette: system colours only, so light/dark and Increase Contrast adapt them.
    enum Swatch: String, CaseIterable, Codable {
        case blue, green, orange, pink, purple, teal, yellow

        var color: Color {
            switch self {
            case .blue: .blue
            case .green: .green
            case .orange: .orange
            case .pink: .pink
            case .purple: .purple
            case .teal: .teal
            case .yellow: .yellow
            }
        }

        var name: String { rawValue.capitalized }
    }

    private struct State: Codable { var swatch: Swatch }

    var swatch: Swatch

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        swatch = try decodeState(State.self, from: state, stateVersion: stateVersion)?.swatch ?? Swatch.allCases.randomElement()!
    }

    var title: String { swatch.name }

    var toolbarItems: [PaneToolbarItem] {
        [
            PaneToolbarItem(id: "next", title: "Next Colour", systemImage: "arrow.trianglehead.2.clockwise",
                            kind: .button { [self] in
                                let all = Swatch.allCases
                                swatch = all[(all.firstIndex(of: swatch)! + 1) % all.count]
                            }),
            PaneToolbarItem(id: "choose", title: "Choose Colour", systemImage: "paintpalette",
                            kind: .menu(items: Swatch.allCases.map { swatch in
                                PaneToolbarItem(id: swatch.rawValue, title: swatch.name, kind: .button { [self] in self.swatch = swatch })
                            }), priority: .low),
        ]
    }

    func makeView() -> AnyView { AnyView(ColorView(content: self)) }
    func encodeState() throws -> Data { try JSONEncoder().encode(State(swatch: swatch)) }
    func shouldClose() async -> Bool { true }
    func willRelease() {}
}

private struct ColorView: View {
    let content: ColorContent

    var body: some View {
        Rectangle().fill(content.swatch.color)
    }
}

/// A count with − and + in the toolbar (⌘- and ⌘=, while the pane is active). Closing it while the count
/// isn't 0 asks first, so a two-stage close can be declined. State: the count.
@MainActor @Observable
final class CounterContent: PaneContent {
    static let type = ContentType(raw: "com.mdidillon.SplitKitTestApp.counter")
    static let displayName = "Counter"
    static let systemImage = "number"
    static let minimumSize = CGSize.zero
    static let stateVersion = 1

    private struct State: Codable { var count: Int }

    var count: Int

    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError) {
        count = try decodeState(State.self, from: state, stateVersion: stateVersion)?.count ?? 0
    }

    var title: String { "Counter" }

    var toolbarItems: [PaneToolbarItem] {
        [
            PaneToolbarItem(id: "decrement", title: "Decrement", systemImage: "minus",
                            kind: .button { [self] in count -= 1 }, priority: .high,
                            keyboardShortcut: KeyboardShortcut("-", modifiers: .command)),
            PaneToolbarItem(id: "increment", title: "Increment", systemImage: "plus",
                            kind: .button { [self] in count += 1 }, priority: .high,
                            keyboardShortcut: KeyboardShortcut("=", modifiers: .command)),
        ]
    }

    func makeView() -> AnyView { AnyView(CounterView(content: self)) }
    func encodeState() throws -> Data { try JSONEncoder().encode(State(count: count)) }

    /// Asks before closing a count other than 0: a sheet on the key window, or an app-modal alert without one.
    func shouldClose() async -> Bool {
        guard count != 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "Close the counter at \(count)?"
        alert.informativeText = "Its count will be lost."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        let response = if let window = NSApp.keyWindow { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        return response == .alertFirstButtonReturn
    }

    func willRelease() {}
}

private struct CounterView: View {
    let content: CounterContent

    var body: some View {
        Text(content.count, format: .number)
            .font(.largeTitle)
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
