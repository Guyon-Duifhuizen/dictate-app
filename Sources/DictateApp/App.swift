import AppKit
import AVFoundation
import SwiftUI

func appLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) \(msg)\n"
    NSLog("[DictateApp] %@", msg)

    let logPath = NSHomeDirectory() + "/Library/Logs/DictateApp.log"
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

@main
struct DictateApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// AppDelegate must be a class (NSApplicationDelegate protocol requirement).
class AppDelegate: NSObject, NSApplicationDelegate {
    private var cleanupHotkey: (() -> Void)?
    private var indicatorWindow: IndicatorWindow!
    private var speechBridge: SpeechBridge!
    private let listeningState = ListeningState()
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("App launched (PID \(ProcessInfo.processInfo.processIdentifier))")
        appLog("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        indicatorWindow = IndicatorWindow(state: listeningState)
        indicatorWindow.onCancel = { [weak self] in
            self?.stopListening()
        }

        speechBridge = SpeechBridge { [weak self] event in
            self?.handleWorkerEvent(event)
        }

        // Request microphone permission from Swift so macOS shows the prompt.
        // The Python subprocess inherits this grant via the app bundle identity.
        requestMicrophoneAccess {
            self.speechBridge.launch()
        }

        if AXIsProcessTrusted() {
            startHotkeyListener()
        } else {
            appLog("Accessibility NOT granted — prompting user…")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    appLog("Accessibility granted!")
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                    self?.startHotkeyListener()
                }
            }
        }
    }

    private func requestMicrophoneAccess(completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            appLog("Microphone already authorized")
            completion()
        case .notDetermined:
            appLog("Requesting microphone access…")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    appLog("Microphone access \(granted ? "granted" : "denied")")
                    completion()
                }
            }
        case .denied, .restricted:
            appLog("Microphone access denied/restricted — open System Settings to grant")
            completion()
        @unknown default:
            completion()
        }
    }

    private func startHotkeyListener() {
        cleanupHotkey = installHotkeyListener { [weak self] action in
            self?.handleHotkeyAction(action)
        }
        appLog("Ready — Cmd+\\ to start dictation, Cmd+\\ again to stop.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupHotkey?()
        speechBridge?.terminate()
    }

    // MARK: - Hotkey handling

    private func handleHotkeyAction(_ action: HotkeyAction) {
        DispatchQueue.main.async { [self] in
            switch action {
            case .toggle:
                if listeningState.isListening {
                    stopListening()
                } else {
                    startListening()
                }
            }
        }
    }

    private func startListening() {
        appLog("Starting dictation…")
        NSSound(named: "Tink")?.play()
        listeningState.isListening = true
        listeningState.audioLevel = 0.0
        listeningState.transcript = ""
        indicatorWindow.show()
        speechBridge.startRecognition()
    }

    private func stopListening() {
        appLog("Stopping dictation…")
        speechBridge.stopRecognition()
    }

    // MARK: - Worker events

    private func handleWorkerEvent(_ event: WorkerEvent) {
        DispatchQueue.main.async { [self] in
            switch event {
            case .ready:
                appLog("Speech worker ready")

            case .interim(let text, let audioLevel):
                listeningState.audioLevel = audioLevel
                listeningState.transcript = text

            case .finalResult(let text):
                appLog("Final: \(text.prefix(80))")
                listeningState.transcript = ""
                KeystrokeSimulator.insertText(text)

            case .error(let message):
                appLog("Worker error: \(message)")

            case .stopped:
                listeningState.isListening = false
                listeningState.audioLevel = 0.0
                listeningState.transcript = ""
                indicatorWindow.hide()
                NSSound(named: "Tink")?.play()
            }
        }
    }
}
