import AppKit
import Foundation
import SplitKitModel

/// How a `SplitKitWorkspace` manages windows, persistence, detaching and pane sizes (§5).
public struct SplitKitConfiguration: Sendable {
    public enum WindowManagement: Sendable { case splitKit, host(makeDetachedWindow: (@MainActor (WindowID) -> NSWindow)?) }
    public enum Persistence: Sendable { case disabled, file(URL), custom(any SessionStore) }
    public enum Detach: Sendable { case enabled, commandOnly, disabled }
    public var windowManagement: WindowManagement = .splitKit
    public var persistence: Persistence = .file(.applicationSupportDefault) // App Support/<bundle id>/SplitKit/session.json
    public var detach: Detach = .enabled
    public var undockThreshold: CGFloat = 40                 // pt beyond window bounds
    public var minimumPaneSize = CGSize(width: 160, height: 100)  // per-content minimumSize wins if larger
    public var focusModeEnabled = true
    public var autosaveDebounce: Duration = .seconds(1)

    /// The memberwise initialiser the §5 declaration implies, with the §5 defaults.
    public init(windowManagement: WindowManagement = .splitKit,
                persistence: Persistence = .file(.applicationSupportDefault),
                detach: Detach = .enabled,
                undockThreshold: CGFloat = 40,
                minimumPaneSize: CGSize = CGSize(width: 160, height: 100),
                focusModeEnabled: Bool = true,
                autosaveDebounce: Duration = .seconds(1)) {
        self.windowManagement = windowManagement
        self.persistence = persistence
        self.detach = detach
        self.undockThreshold = undockThreshold
        self.minimumPaneSize = minimumPaneSize
        self.focusModeEnabled = focusModeEnabled
        self.autosaveDebounce = autosaveDebounce
    }
}

/// Where a session is loaded from and saved to when `persistence` is `.custom` (§5, §8).
public protocol SessionStore: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws                     // must be atomic for its medium
}

extension URL {
    /// `Application Support/<bundle id>/SplitKit/session.json` (§5). Without a bundle identifier (e.g. a test
    /// runner) the process name stands in.
    public static var applicationSupportDefault: URL {
        let folder = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return URL.applicationSupportDirectory
            .appending(path: folder, directoryHint: .isDirectory)
            .appending(path: "SplitKit", directoryHint: .isDirectory)
            .appending(path: "session.json", directoryHint: .notDirectory)
    }
}
