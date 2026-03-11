import SwiftUI
import AppKit

/// Custom keyboard shortcut recorder view with real-time validation.
///
/// Features:
/// - Display current shortcut with monospace font
/// - Record button to start/stop capture
/// - NSEvent monitoring for key capture
/// - Real-time validation with error messages
/// - Liquid glass design matching MicIndicatorView
struct ShortcutRecorderView: View {
    @Binding var preference: HotkeyPreference
    @State private var isRecording = false
    @State private var validationError: String?
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            // Display area
            HStack {
                Text(preference.displayString)
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Material.ultraThickMaterial)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
            }

            // Record button
            Button(action: {
                isRecording ? stopRecording() : startRecording()
            }) {
                Label(
                    isRecording ? "Stop Recording" : "Record Shortcut",
                    systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                )
                .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .scaleEffect(isRecording ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)

            // Validation error
            if let error = validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                }
                .foregroundColor(.orange)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Helper text
            if isRecording {
                Text("Press your desired key combination...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: validationError)
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Recording

    func startRecording() {
        isRecording = true
        validationError = nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            let keyCode = event.keyCode
            let modifiers = extractModifiers(from: event.modifierFlags)

            // Validate
            if modifiers.isEmpty {
                validationError = "Requires at least one modifier key (⌘, ⌃, ⌥, or ⇧)"
                return nil
            }

            // Create new shortcut
            let newShortcut = HotkeyPreference(
                keyCode: Int64(keyCode),
                modifiers: modifiers
            )

            // Validate using PreferencesManager
            let result = PreferencesManager.shared.validate(newShortcut)
            if let errorMsg = result.errorMessage {
                validationError = errorMsg
            } else {
                validationError = nil
                preference = newShortcut
                stopRecording()
            }

            return nil // Consume event
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Helpers

    /// Extract modifier keys from NSEvent.ModifierFlags.
    func extractModifiers(from flags: NSEvent.ModifierFlags) -> Set<ModifierKey> {
        var mods: Set<ModifierKey> = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        return mods
    }
}
