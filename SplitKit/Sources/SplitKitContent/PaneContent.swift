import Foundation
import Observation
import SwiftUI
import SplitKitModel

// Content contract (§5, §6.4, §6.5). Content products implement `PaneContent`; the SplitKit UI target
// hosts it. This target never imports the UI target (§3).

@MainActor public protocol PaneContent: AnyObject, Observable {
    static var type: ContentType { get }
    static var displayName: String { get }
    static var systemImage: String { get }
    static var minimumSize: CGSize { get }                   // points
    static var stateVersion: Int { get }
    /// `url` is the file to open, validated here (throw `.unsupportedFile` / `.unreadable`); nil for restore and new empty content.
    init(id: ContentID, url: URL?, restoring state: Data?, stateVersion: Int?) throws(ContentError)
    var title: String { get }
    var toolbarItems: [PaneToolbarItem] { get }              // observed; changes re-render the header
    func makeView() -> AnyView                               // may be called again after re-hosting
    func encodeState() throws -> Data
    func shouldClose() async -> Bool                         // must not touch the layout
    func willRelease()                                       // after commit; tear down resources
}

public enum ContentError: Error, Sendable {
    case unsupportedFile(URL, reason: String), unreadable(URL), stateIncompatible(version: Int), other(String)
}
