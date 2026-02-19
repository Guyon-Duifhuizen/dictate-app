import AppKit
import SwiftUI

/// Observable state shared between the app logic and the SwiftUI indicator.
final class ListeningState: ObservableObject {
    @Published var isListening: Bool = false
    @Published var audioLevel: Double = 0.0
    @Published var transcript: String = ""
}

/// A panel subclass that never steals keyboard focus from other apps.
private class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Manages the floating indicator panel.
///
/// The panel floats above all windows, never steals focus, and follows
/// the user across Spaces and full-screen apps. It auto-sizes vertically
/// as transcript text grows.
final class IndicatorWindow {
    private var panel: NSPanel?
    private let state: ListeningState
    var onCancel: (() -> Void)?

    init(state: ListeningState) {
        self.state = state
    }

    func show() {
        guard panel == nil else { return }
        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = min(420, screen.frame.width - 40)
        let initialHeight: CGFloat = 200

        let panelRect = NSRect(
            x: (screen.frame.width - panelWidth) / 2,
            y: 100,
            width: panelWidth,
            height: initialHeight
        )

        let newPanel = NonActivatingPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false // SwiftUI handles its own shadow
        newPanel.ignoresMouseEvents = false
        newPanel.isMovableByWindowBackground = false
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hostingView = NSHostingView(rootView: MicIndicatorView(state: state, onCancel: { [weak self] in
            self?.onCancel?()
        }))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: initialHeight)
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView

        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        self.panel = newPanel
    }

    func hide() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
        })
    }
}
