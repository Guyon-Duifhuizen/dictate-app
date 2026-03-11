import AppKit
import AVFoundation
import SwiftUI

func appLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) \(msg)\n"
    NSLog("[DictateApp] %@", msg)

    guard let data = line.data(using: .utf8) else { return }
    let logPath = NSHomeDirectory() + "/Library/Logs/DictateApp.log"
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(data)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

@main
struct DictateApp {
    static func main() {
        // Ignore SIGPIPE so we don't crash if the Python worker dies mid-stream
        signal(SIGPIPE, SIG_IGN)

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
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var maxDurationTimer: Timer?
    private let maxListeningDuration: TimeInterval = 15 * 60  // 15 minutes

    var statusItem: NSStatusItem?
    let preferencesManager = PreferencesManager.shared
    var preferencesWindow: PreferencesWindow?
    private var hotkeyReloadWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("App launched (PID \(ProcessInfo.processInfo.processIdentifier))")
        appLog("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        // Create menu bar status item
        setupMenuBar()

        indicatorWindow = IndicatorWindow(state: listeningState)
        indicatorWindow.onCancel = { [weak self] in
            self?.stopListening()
        }
        indicatorWindow.onSettings = { [weak self] in
            self?.openPreferences()
        }

        speechBridge = SpeechBridge { [weak self] event in
            self?.handleWorkerEvent(event)
        }

        // Request microphone permission from Swift so macOS shows the prompt.
        // The Python subprocess inherits this grant via the app bundle identity.
        requestMicrophoneAccess {
            self.speechBridge.launch()
        }

        // Show preferences on launch so the user sees something
        openPreferences()

        // Listen for hotkey preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadHotkey),
            name: .hotkeyDidChange,
            object: nil
        )

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

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "DictateApp")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow()
        }
        preferencesWindow?.showWindow()
    }

    @objc func reloadHotkey() {
        // Debounce rapid-fire reload requests to prevent duplicate event tap creation
        hotkeyReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            appLog("Reloading hotkey with new preference: \(self.preferencesManager.currentHotkey.displayString)")

            // Create new event tap before destroying the old one
            let newCleanup = installHotkeyListener(preference: self.preferencesManager.currentHotkey) { [weak self] action in
                self?.handleHotkeyAction(action)
            }

            if newCleanup == nil {
                appLog("❌ Failed to create new event tap - keeping old hotkey")
                // Don't destroy the old event tap if we failed to create a new one
            } else {
                // Only cleanup old tap after successfully creating the new one
                self.cleanupHotkey?()
                self.cleanupHotkey = newCleanup
                appLog("Ready — \(self.preferencesManager.currentHotkey.displayString) to start dictation, \(self.preferencesManager.currentHotkey.displayString) again to stop.")
            }
        }
        hotkeyReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func startHotkeyListener() {
        let newCleanup = installHotkeyListener(preference: preferencesManager.currentHotkey) { [weak self] action in
            self?.handleHotkeyAction(action)
        }

        if newCleanup == nil {
            appLog("❌ Failed to create event tap - accessibility may have been revoked")
            // Keep old cleanup or handle error appropriately
        } else {
            cleanupHotkey = newCleanup
            appLog("Ready — \(preferencesManager.currentHotkey.displayString) to start dictation, \(preferencesManager.currentHotkey.displayString) again to stop.")
        }
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
        NSSound(named: "Pop")?.play()
        listeningState.isListening = true
        listeningState.audioLevel = 0.0
        listeningState.transcript = ""
        indicatorWindow.show()
        speechBridge.startRecognition()
        startAudioCapture()

        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxListeningDuration, repeats: false) { [weak self] _ in
            appLog("Max listening duration reached — stopping automatically")
            self?.stopListening()
        }
    }

    private func stopListening() {
        appLog("Stopping dictation…")
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        stopAudioCapture()
        speechBridge.stopRecognition()
    }

    // MARK: - Audio capture

    private func startAudioCapture() {
        let inputNode = audioEngine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        appLog("Mic hardware format: \(hwFormat)")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            appLog("Failed to create target audio format")
            return
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            appLog("Failed to create AVAudioConverter")
            return
        }
        self.audioConverter = converter

        let requestedFrames: AVAudioFrameCount = 1600  // 100ms at 16kHz

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hwFormat.sampleRate * 0.1),
                             format: hwFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter,
                                     targetFormat: targetFormat,
                                     requestedFrames: requestedFrames)
        }

        do {
            try audioEngine.start()
            appLog("Audio engine started")
        } catch {
            appLog("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
        }
    }

    private func stopAudioCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioConverter = nil
        appLog("Audio engine stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer,
                                    converter: AVAudioConverter,
                                    targetFormat: AVAudioFormat,
                                    requestedFrames: AVAudioFrameCount) {
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: requestedFrames) else { return }

        var hasProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, let floatData = outputBuffer.floatChannelData else { return }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0 else { return }

        let floatPtr = floatData[0]

        // Compute RMS for the audio level indicator
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let s = floatPtr[i]
            sumSquares += s * s
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        // Normalize: map RMS to 0..1 range (typical speech RMS ~0.01-0.1)
        let level = Double(min(1.0, rms * 10.0))
        DispatchQueue.main.async { [weak self] in
            self?.listeningState.audioLevel = level
        }

        // Convert Float32 → Int16 PCM
        var int16Data = Data(count: frameCount * 2)
        int16Data.withUnsafeMutableBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let clamped = max(-1.0, min(1.0, floatPtr[i]))
                int16Ptr[i] = Int16(clamped * Float(Int16.max))
            }
        }

        speechBridge.sendAudio(int16Data)
    }

    // MARK: - Worker events

    private func handleWorkerEvent(_ event: WorkerEvent) {
        DispatchQueue.main.async { [self] in
            switch event {
            case .ready:
                appLog("Speech worker ready")

            case .interim(let text):
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
                NSSound(named: "Pop")?.play()
            }
        }
    }
}
