import Cocoa
import Carbon.HIToolbox

enum HotkeyAction {
    case toggle // Cmd+\
}

/// Installs a global CGEvent tap that calls `callback` on Cmd+\.
/// Returns a cleanup function that disables the tap.
///
/// Requires Accessibility permissions.
func installHotkeyListener(callback: @escaping (HotkeyAction) -> Void) -> (() -> Void)? {
    let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

    let boxed = Unmanaged.passRetained(CallbackBox(callback)).toOpaque()

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: hotkeyEventCallback,
        userInfo: boxed
    ) else {
        NSLog("[DictateApp] Failed to create event tap — grant Accessibility access in System Settings.")
        Unmanaged<CallbackBox>.fromOpaque(boxed).release()
        return nil
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    return {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
}

// MARK: - Private

private final class CallbackBox {
    let fn: (HotkeyAction) -> Void
    init(_ fn: @escaping (HotkeyAction) -> Void) { self.fn = fn }
}

private func hotkeyEventCallback(
    _: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Cmd+\
        if keyCode == Int64(kVK_ANSI_Backslash) {
            let cmd = flags.contains(.maskCommand)
            let ctrl = flags.contains(.maskControl)
            let option = flags.contains(.maskAlternate)
            let shift = flags.contains(.maskShift)

            if cmd && !ctrl && !option && !shift {
                NSLog("[DictateApp] Hotkey Cmd+\\ detected")
                box.fn(.toggle)
                return nil
            }
        }
    }

    return Unmanaged.passUnretained(event)
}
