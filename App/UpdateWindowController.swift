import AppKit
import SwiftUI

/// Presents the native Software Update window reliably on cold start and manual checks,
/// including when the app runs as an `LSUIElement` menu-bar-only utility.
@MainActor
public final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    public func present(updater: UpdateManager, isColdStart: Bool) {
        let rootView = UpdatePromptView(
            updater: updater,
            isColdStart: isColdStart,
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        if let existing = window {
            existing.contentViewController = NSHostingController(rootView: rootView)
            existing.center()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Software Update"
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.moveToActiveSpace]
        newWindow.backgroundColor = .clear
        newWindow.delegate = self
        newWindow.center()

        self.window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.orderOut(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
