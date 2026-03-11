import SwiftUI
import AppKit

/// Manages the preferences window.
///
/// Follows the pattern from IndicatorWindow.swift: creates an NSWindow that
/// hosts a SwiftUI view. The window is persistent (not released when closed)
/// and can be shown/hidden as needed.
final class PreferencesWindow {
    private var window: NSWindow?

    init() {
        let contentView = PreferencesView()

        let hostingController = NSHostingController(rootView: contentView)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PreferencesWindowSize.width, height: PreferencesWindowSize.height),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.center()
        window?.title = "Preferences"
        window?.titlebarAppearsTransparent = true
        window?.contentView = hostingController.view
        window?.isReleasedWhenClosed = false
        window?.setFrameAutosaveName("PreferencesWindow")

        // Use standard window level (not floating like indicator)
        window?.level = .normal
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}
