import Observation
import SplitKitContent
import SplitKitModel

/// The live content objects of a workspace (§4, §6.4): `ContentID` → `PaneContent`, and which windows
/// currently host each object's view. Objects survive move, swap, detach and dock because only the
/// `Session` changes; they leave the store only when a transaction releases them.
@MainActor @Observable
final class ContentStore {
    private(set) var objects: [ContentID: any PaneContent] = [:]
    /// Live `makeView()` hosts per content and window. Counted, so a pane view that appears before the
    /// old one disappears (same window) is no double host.
    @ObservationIgnored private var hosts: [ContentID: [WindowID: Int]] = [:]

    subscript(id: ContentID) -> (any PaneContent)? { objects[id] }

    func insert(_ object: any PaneContent, for id: ContentID) {
        precondition(objects[id] == nil, "content \(id) already has a live object")
        objects[id] = object
    }

    /// §6.3.2: the host calls `willRelease()`, then drops the object. Unknown IDs (e.g. an unavailable
    /// placeholder, which has no object) are ignored.
    func release(_ id: ContentID) {
        guard let object = objects.removeValue(forKey: id) else { return }
        object.willRelease()
        hosts[id] = nil
    }

    /// Records that `window` shows the view of `id`. Returns `false`, and records nothing, if another
    /// window already hosts it: one `ContentID` is never hosted in two windows at once (§6.4).
    @discardableResult
    func beginHosting(_ id: ContentID, in window: WindowID) -> Bool {
        let windows = hosts[id, default: [:]]
        guard windows.keys.allSatisfy({ $0 == window }) else { return false }
        hosts[id, default: [:]][window, default: 0] += 1
        return true
    }

    func endHosting(_ id: ContentID, in window: WindowID) {
        guard let count = hosts[id]?[window] else { return }
        hosts[id]?[window] = count > 1 ? count - 1 : nil
        if hosts[id]?.isEmpty == true { hosts[id] = nil }
    }

    /// The windows hosting the view of `id` right now.
    func hostingWindows(of id: ContentID) -> Set<WindowID> { Set(hosts[id, default: [:]].keys) }
}
