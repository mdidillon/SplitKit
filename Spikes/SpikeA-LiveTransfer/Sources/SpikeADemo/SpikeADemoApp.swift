import AppKit
import SpikeACore

/// Two windows. A: Counter + 3D Spinner. B: two empty panes + one locked pane (invalid drop target).
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = TransferCoordinator()
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.logger = { print("[SpikeA] " + $0) }
        do {
            let windowA = WindowID(), windowB = WindowID()
            let a1 = try coordinator.makePane(in: windowA)
            let a2 = try coordinator.makePane(in: windowA)
            let b1 = try coordinator.makePane(in: windowB)
            let b2 = try coordinator.makePane(in: windowB)
            let locked = try coordinator.makePane(in: windowB, acceptsDrops: false)
            try coordinator.add(CounterContent(), to: a1.hostID)
            try coordinator.add(SpinnerContent(), to: a2.hostID)
            windows = [
                SpikeWindow.make(title: "Spike A — Window A", panes: [a1, a2], origin: NSPoint(x: 80, y: 420)),
                SpikeWindow.make(title: "Spike A — Window B", panes: [b1, b2, locked], origin: NSPoint(x: 260, y: 60)),
            ]
        } catch {
            fatalError("demo setup failed: \(error)")
        }
        NSApp.mainMenu = makeMenu()
        windows.reversed().forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate()
        printResidue(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Commands

    @objc func moveToOtherWindow(_ sender: Any?) {
        guard let key = NSApp.keyWindow else { return NSSound.beep() }
        let panes = coordinator.allPanes.filter { $0.window === key && $0.hostedContent != nil }
        guard let pane = panes.first(where: { $0.containsFirstResponder() }) ?? panes.first,
              let content = pane.hostedContent else { return NSSound.beep() }
        do {
            try coordinator.moveToOtherWindow(content.id)
        } catch {
            print("[SpikeA] move to other window failed: \(error)")
            NSSound.beep()
        }
    }

    @objc func printResidue(_ sender: Any?) {
        let report = coordinator.residue(windows: windows)
        print("[SpikeA] residue report\n\(report)")
        guard sender != nil else { return }
        let alert = NSAlert()
        alert.messageText = "Residue report"
        alert.informativeText = report.windows.map(\.description).joined(separator: "\n\n")
            + "\n\nledger: \(report.ledger.count) claims; attachmentCounts: \(report.attachmentCounts)"
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        submenu("SpikeADemo", [NSMenuItem(title: "Quit SpikeADemo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")])
        submenu("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        let move = NSMenuItem(title: "Move to Other Window", action: #selector(moveToOtherWindow(_:)), keyEquivalent: "m")
        move.keyEquivalentModifierMask = [.command, .option]
        move.target = self
        let residue = NSMenuItem(title: "Residue Report…", action: #selector(printResidue(_:)), keyEquivalent: "r")
        residue.keyEquivalentModifierMask = [.command, .option]
        residue.target = self
        submenu("Pane", [move, residue])
        submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
        return main
    }
}

@main
enum SpikeADemoMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
