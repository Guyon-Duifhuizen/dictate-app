import Cocoa
import Carbon.HIToolbox

/// Inserts text into the frontmost application using CGEvent.
enum KeystrokeSimulator {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func insertText(_ text: String) {
        for char in text + " " {
            var utf16 = Array(String(char).utf16)

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)

            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}
