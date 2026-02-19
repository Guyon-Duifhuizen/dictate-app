import Foundation

/// Manages the Python speech worker subprocess and communicates
/// via JSON lines over stdin/stdout.
final class SpeechBridge {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let eventHandler: (WorkerEvent) -> Void
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var outputBuffer = Data()
    private let writeQueue = DispatchQueue(label: "com.dictate-app.stdin-write")

    init(eventHandler: @escaping (WorkerEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    func launch() {
        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        let (pythonPath, args) = resolveWorker()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = args

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutputData(data)
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return }
            NSLog("[Worker] %@", text)
        }

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        do {
            try proc.run()
            NSLog("[DictateApp] Worker launched: %@ %@", pythonPath, args.joined(separator: " "))
        } catch {
            NSLog("[DictateApp] Failed to launch worker: %@", error.localizedDescription)
        }
    }

    func startRecognition(language: String = "en-US", project: String? = nil) {
        sendCommand(StartCommand(language: language, project: project))
    }

    func stopRecognition() {
        sendCommand(StopCommand())
    }

    func sendAudio(_ pcmData: Data) {
        let base64 = pcmData.base64EncodedString()
        sendCommand(AudioCommand(data: base64))
    }

    func terminate() {
        process?.terminate()
        process = nil
    }

    // MARK: - Private

    private func handleOutputData(_ data: Data) {
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = outputBuffer[outputBuffer.startIndex..<newlineIndex]
            outputBuffer = Data(outputBuffer[outputBuffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            do {
                if let raw = String(data: Data(lineData), encoding: .utf8) {
                    appLog("Worker event: \(raw)")
                }
                let event = try decoder.decode(WorkerEvent.self, from: Data(lineData))
                eventHandler(event)
            } catch {
                if let text = String(data: Data(lineData), encoding: .utf8) {
                    appLog("Failed to decode: \(text) — \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendCommand<T: Encodable>(_ command: T) {
        guard let pipe = stdinPipe else { return }
        do {
            var data = try encoder.encode(command)
            data.append(UInt8(ascii: "\n"))
            writeQueue.async {
                pipe.fileHandleForWriting.write(data)
            }
        } catch {
            NSLog("[DictateApp] Failed to encode command: %@", error.localizedDescription)
        }
    }

    /// Resolve the Python interpreter and arguments to launch the worker.
    ///
    /// Search order:
    /// 1. `DICTATE_APP_WORKER` environment variable (direct script path)
    /// 2. Inside the .app bundle's Resources/venv
    /// 3. `.venv` relative to the current directory
    /// 4. Fallback to `/usr/bin/env python3`
    private func resolveWorker() -> (String, [String]) {
        let fm = FileManager.default

        if let envPath = ProcessInfo.processInfo.environment["DICTATE_APP_WORKER"],
           fm.isExecutableFile(atPath: envPath) {
            return (envPath, [])
        }

        if let bundlePath = Bundle.main.resourcePath {
            let bundlePython = "\(bundlePath)/venv/bin/python3"
            if fm.isExecutableFile(atPath: bundlePython) {
                return (bundlePython, ["-m", "dictate_app.speech_worker"])
            }
        }

        let cwd = fm.currentDirectoryPath
        let venvPython = "\(cwd)/.venv/bin/python3"
        if fm.isExecutableFile(atPath: venvPython) {
            return (venvPython, ["-m", "dictate_app.speech_worker"])
        }

        return ("/usr/bin/env", ["python3", "-m", "dictate_app.speech_worker"])
    }
}
