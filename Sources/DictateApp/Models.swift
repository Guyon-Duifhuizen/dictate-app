import Foundation

// MARK: - Commands (Swift → Python)

struct StartCommand: Encodable {
    let type = "start"
    let language: String
    let project: String?
}

struct StopCommand: Encodable {
    let type = "stop"
}

// MARK: - Events (Python → Swift)

enum WorkerEvent {
    case ready
    case interim(text: String, audioLevel: Double)
    case finalResult(text: String)
    case error(message: String)
    case stopped
}

extension WorkerEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case audioLevel = "audio_level"
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "ready":
            self = .ready
        case "interim":
            let text = try container.decode(String.self, forKey: .text)
            let level = try container.decodeIfPresent(Double.self, forKey: .audioLevel) ?? 0.0
            self = .interim(text: text, audioLevel: level)
        case "final":
            let text = try container.decode(String.self, forKey: .text)
            self = .finalResult(text: text)
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message: message)
        case "stopped":
            self = .stopped
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath,
                      debugDescription: "Unknown event type: \(type)")
            )
        }
    }
}
