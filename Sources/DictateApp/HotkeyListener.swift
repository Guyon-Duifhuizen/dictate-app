import Cocoa
import Carbon.HIToolbox

enum HotkeyAction {
    case toggle // Cmd+\
}

/// Installs a global CGEvent tap that calls `callback` when the specified hotkey is pressed.
/// Returns a cleanup function that disables the tap.
///
/// Requires Accessibility permissions.
func installHotkeyListener(preference: HotkeyPreference, callback: @escaping (HotkeyAction) -> Void) -> (() -> Void)? {
    let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

    let boxed = Unmanaged.passRetained(CallbackBoxWithPreference(preference, callback)).toOpaque()

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: hotkeyEventCallback,
        userInfo: boxed
    ) else {
        NSLog("[DictateApp] ❌ CRITICAL: Failed to create event tap")
        NSLog("[DictateApp] Grant Accessibility access in System Settings > Privacy & Security > Accessibility")
        Unmanaged<CallbackBoxWithPreference>.fromOpaque(boxed).release()
        return nil
    }

    NSLog("[DictateApp] ✅ Event tap created successfully for hotkey: \(preference.displayString)")

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    return {
        CGEvent.tapEnable(tap: tap, enable: false)
        // Release the retained callback box to prevent memory leak
        Unmanaged<CallbackBoxWithPreference>.fromOpaque(boxed).release()
    }
}

// MARK: - Private

private final class CallbackBoxWithPreference {
    let preference: HotkeyPreference
    let fn: (HotkeyAction) -> Void
    init(_ preference: HotkeyPreference, _ fn: @escaping (HotkeyAction) -> Void) {
        self.preference = preference
        self.fn = fn
    }
}

private func hotkeyEventCallback(
    _: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<CallbackBoxWithPreference>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Extract actual modifiers from the event
        var actualModifiers: Set<ModifierKey> = []
        if flags.contains(.maskCommand) { actualModifiers.insert(.command) }
        if flags.contains(.maskControl) { actualModifiers.insert(.control) }
        if flags.contains(.maskAlternate) { actualModifiers.insert(.option) }
        if flags.contains(.maskShift) { actualModifiers.insert(.shift) }

        // DEBUG: Log every keypress to see what's being captured
        NSLog("[DEBUG] Global key event: keyCode=\(keyCode), flags=\(flags.rawValue)")
        NSLog("[DEBUG] Looking for: keyCode=\(box.preference.keyCode), modifiers=\(box.preference.modifiers)")
        NSLog("[DEBUG] Actual modifiers: \(actualModifiers)")

        // Check if the key code and modifiers match the preference
        if keyCode == box.preference.keyCode && actualModifiers == box.preference.modifiers {
            NSLog("[DictateApp] Hotkey \(box.preference.displayString) detected")
            box.fn(.toggle)
            return nil
        } else if keyCode == box.preference.keyCode {
            NSLog("[DEBUG] KeyCode matched but modifiers didn't: expected \(box.preference.modifiers), got \(actualModifiers)")
        }
    }

    return Unmanaged.passUnretained(event)
}
