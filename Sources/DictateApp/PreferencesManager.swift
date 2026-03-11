import Foundation
import Combine

// MARK: - Notification

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("com.dictateapp.hotkeyDidChange")
}

// MARK: - ModifierKey

enum ModifierKey: String, Codable, Hashable, CaseIterable {
    case command
    case control
    case option
    case shift

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }
}

// MARK: - HotkeyPreference

struct HotkeyPreference: Codable, Equatable {
    let keyCode: Int64
    let modifiers: Set<ModifierKey>

    var displayString: String {
        // Sort modifiers in standard macOS order: Control, Option, Shift, Command
        let orderedModifiers: [ModifierKey] = [.control, .option, .shift, .command]
        let symbols = orderedModifiers
            .filter { modifiers.contains($0) }
            .map { $0.symbol }
            .joined()

        // Get the key character representation
        let keyChar = Self.keyCodeToChar(keyCode)
        return symbols + keyChar
    }

    static let `default` = HotkeyPreference(
        keyCode: 50,  // kVK_ANSI_Grave (0x32) — top-left key, consistent across keyboard layouts
        modifiers: [.command]
    )

    // Convert key code to displayable character
    private static func keyCodeToChar(_ keyCode: Int64) -> String {
        // Common special keys
        switch keyCode {
        case 36: return "⏎"  // Return
        case 48: return "⇥"  // Tab
        case 49: return "Space"
        case 51: return "⌫"  // Delete
        case 53: return "⎋"  // Escape
        case 50: return "\\"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // For letter/number keys, try to get the character
            return keyCodeToCharacterFallback(keyCode)
        }
    }

    private static func keyCodeToCharacterFallback(_ keyCode: Int64) -> String {
        // Simple mapping for common keys
        let charMap: [Int64: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
            46: "M", 47: ".", 50: "\\"
        ]
        return charMap[keyCode] ?? "Key\(keyCode)"
    }

    // MARK: - Codable Conformance

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(keyCode: Int64, modifiers: Set<ModifierKey>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try to decode as Int64 first (new format), fall back to UInt16 (old format) for backward compatibility
        if let int64KeyCode = try? container.decode(Int64.self, forKey: .keyCode) {
            keyCode = int64KeyCode
        } else {
            let uint16KeyCode = try container.decode(UInt16.self, forKey: .keyCode)
            keyCode = Int64(uint16KeyCode)
        }

        // Decode Set<ModifierKey> from array
        let modifierArray = try container.decode([ModifierKey].self, forKey: .modifiers)
        modifiers = Set(modifierArray)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)

        // Encode Set<ModifierKey> as sorted array for consistency
        let modifierArray = Array(modifiers).sorted { $0.rawValue < $1.rawValue }
        try container.encode(modifierArray, forKey: .modifiers)
    }
}

// MARK: - ValidationResult

enum ValidationResult: Equatable {
    case valid
    case requiresModifier
    case systemShortcut
    case invalid(String)

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .requiresModifier:
            return "Shortcut must include at least one modifier key (⌘, ⌃, ⌥, or ⇧)"
        case .systemShortcut:
            return "This shortcut conflicts with a system shortcut"
        case .invalid(let message):
            return message
        }
    }
}

// MARK: - PreferencesManager

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private let userDefaultsKey = "com.dictateapp.hotkey"

    @Published var currentHotkey: HotkeyPreference {
        didSet {
            saveToUserDefaults()
            NotificationCenter.default.post(name: .hotkeyDidChange, object: self)
        }
    }

    private init() {
        // Load from UserDefaults, fall back to default if invalid
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(HotkeyPreference.self, from: data) {
            self.currentHotkey = decoded
            NSLog("[PreferencesManager] Loaded hotkey from UserDefaults: \(decoded.displayString)")
        } else {
            self.currentHotkey = .default
            NSLog("[PreferencesManager] Using default hotkey: \(HotkeyPreference.default.displayString)")
        }
    }

    private func saveToUserDefaults() {
        if let encoded = try? JSONEncoder().encode(currentHotkey) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            NSLog("[PreferencesManager] Saved hotkey to UserDefaults: \(currentHotkey.displayString)")
        } else {
            NSLog("[PreferencesManager] Failed to encode hotkey preference")
        }
    }

    // MARK: - Validation

    func validate(_ preference: HotkeyPreference) -> ValidationResult {
        // Require at least one modifier
        if preference.modifiers.isEmpty {
            return .requiresModifier
        }

        // Check for common system shortcuts
        if isSystemShortcut(preference) {
            return .systemShortcut
        }

        return .valid
    }

    private func isSystemShortcut(_ preference: HotkeyPreference) -> Bool {
        // Common system shortcuts to avoid
        // Cmd+Q (Quit), Cmd+W (Close), Cmd+Tab, Cmd+Space, etc.

        if preference.modifiers == [.command] {
            switch preference.keyCode {
            case 12: return true  // Q - Quit
            case 13: return true  // W - Close Window
            case 48: return true  // Tab - Switch Apps
            case 49: return true  // Space - Spotlight
            case 6: return true   // Z - Undo
            case 7: return true   // X - Cut
            case 8: return true   // C - Copy
            case 9: return true   // V - Paste
            default: break
            }
        }

        // Cmd+Shift+Q (Log out)
        if preference.modifiers == [.command, .shift] && preference.keyCode == 12 {
            return true
        }

        // Cmd+Option+Esc (Force Quit)
        if preference.modifiers == [.command, .option] && preference.keyCode == 53 {
            return true
        }

        return false
    }

    // MARK: - Public Methods

    func updateHotkey(_ preference: HotkeyPreference) -> ValidationResult {
        let result = validate(preference)
        if result.isValid {
            currentHotkey = preference
        }
        return result
    }

    func resetToDefault() {
        currentHotkey = .default
    }
}
