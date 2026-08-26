import Foundation
import Security
import Observation
import FoundationModels

/// Where the thinking happens.
///
/// Two backends, one interface. Cerebras when a key is set — fast enough that a
/// profile is rewritten before the user has finished looking at it. Apple's
/// on-device model when there is no key, which keeps the app useful offline and
/// on the plane where half of these people get met.
///
/// Both are asked for JSON in plain prose rather than through a schema API, so
/// there is exactly one prompt to maintain per capability instead of two.
protocol Brain: Sendable {
    /// Audio in, text out. `nil` where the provider has no transcription
    /// endpoint, which is every provider but OpenAI today.
    func transcribe(_ audio: URL) async throws -> String?

    /// `json` asks the backend to constrain the output to a JSON object where it
    /// can. It is a hint, not a guarantee — callers still parse defensively.
    func reply(system: String, user: String, temperature: Double, json: Bool) async throws -> String
}

extension Brain {
    func transcribe(_ audio: URL) async throws -> String? { nil }
}

enum BrainError: Error {
    case http(Int, String)
    case empty
}

// MARK: - Providers

/// Both services speak the same OpenAI-shaped protocol, so they share one client
/// and differ only in a URL and a default model.
enum Provider: String, CaseIterable {
    case openAI, cerebras

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .cerebras: "Cerebras"
        }
    }

    var endpoint: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .cerebras: URL(string: "https://api.cerebras.ai/v1/chat/completions")!
        }
    }

    /// The cheapest model on each service that can still hold a schema in its
    /// head. Both retire models faster than an app update ships, which is why
    /// the field is editable in settings.
    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5.6-luna"
        case .cerebras: "gpt-oss-120b"
        }
    }

    /// Read off the key rather than asked for. Cerebras issues `csk-…`,
    /// OpenAI `sk-…`, so pasting a key is the whole configuration step.
    static func detect(_ key: String) -> Provider {
        key.trimmingCharacters(in: .whitespaces).hasPrefix("csk-") ? .cerebras : .openAI
    }
}

struct RemoteBrain: Brain {
    let provider: Provider
    let key: String
    let model: String

    func reply(system: String, user: String, temperature: Double, json: Bool) async throws -> String {
        do {
            return try await send(system: system, user: user, temperature: temperature, json: json)
        } catch BrainError.http(let code, let body) where code == 400 && body.lowercased().contains("temperature") {
            // reasoning models reject any temperature but their own; the request
            // is fine without it, so retry rather than surface a dead end
            return try await send(system: system, user: user, temperature: nil, json: json)
        }
    }

    private func send(system: String, user: String, temperature: Double?, json: Bool) async throws -> String {
        var req = URLRequest(url: provider.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let body = Request(
            model: model,
            temperature: temperature,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ],
            response_format: json ? .init(type: "json_object") : nil
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw BrainError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let out = try? JSONDecoder().decode(Response.self, from: data),
              let text = out.choices.first?.message.content, !text.isEmpty
        else { throw BrainError.empty }
        return text
    }

    /// Multipart upload to `/audio/transcriptions`.
    ///
    /// Better than the on-device recogniser at names and punctuation, and it
    /// works out the language on its own rather than being told — which is the
    /// whole reason the language picker can stay a fallback rather than a
    /// requirement. Cerebras has no equivalent endpoint, so this returns nil
    /// there and the on-device transcript stands.
    func transcribe(_ audio: URL) async throws -> String? {
        guard provider == .openAI else { return nil }
        let data = try Data(contentsOf: audio)
        // a few seconds of silence is not worth three tenths of a cent
        guard data.count > 8_000 else { return nil }

        let boundary = "metwho.\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", Self.transcriptionModel)
        field("response_format", "text")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"note.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (out, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw BrainError.http(code, String(data: out, encoding: .utf8) ?? "")
        }
        let text = String(data: out, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// The cheap one: $0.003 a minute, against $0.006 for the full model and for
    /// whisper-1. A thirty-second note costs a tenth of a cent.
    static let transcriptionModel = "gpt-4o-mini-transcribe"

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct Format: Encodable { let type: String }
        let model: String
        let temperature: Double?
        let messages: [Message]
        let response_format: Format?
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}

// MARK: - On device

struct OnDeviceBrain: Brain {
    func reply(system: String, user: String, temperature: Double, json: Bool) async throws -> String {
        guard #available(iOS 26.0, *) else { throw BrainError.empty }
        let session = LanguageModelSession(instructions: system)
        let out = try await session.respond(
            to: user,
            options: GenerationOptions(temperature: temperature)
        ).content
        guard !out.isEmpty else { throw BrainError.empty }
        return out
    }

    static var isAvailable: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }
}

// MARK: - Configuration

/// The key lives in the keychain, never in `Prefs` — `Prefs` is written to a
/// plain JSON file next to the notes and is meant to be readable.
@Observable
final class AIConfig {

    static let shared = AIConfig()

    private static let keyAccount = "ai.api.key"

    var key: String {
        didSet {
            Keychain.set(key, for: Self.keyAccount)
            // switching services must not carry the old service's model name
            // across, or the first request 404s on a model that never existed there
            model = Self.storedModel(for: provider)
        }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey(provider)) }
    }

    private init() {
        let stored = Keychain.get(Self.keyAccount) ?? ""
        key = stored
        model = Self.storedModel(for: Provider.detect(stored))
    }

    var provider: Provider { Provider.detect(key) }
    var hasKey: Bool { !key.trimmingCharacters(in: .whitespaces).isEmpty }

    private static func modelKey(_ p: Provider) -> String { "metwho.ai.model.\(p.rawValue)" }

    private static func storedModel(for p: Provider) -> String {
        UserDefaults.standard.string(forKey: modelKey(p)) ?? p.defaultModel
    }

    /// Remote first: it is both better and faster than the 3B on-device model.
    /// `nil` means no thinking is possible and every caller falls back to the
    /// heuristic it already had.
    var brain: Brain? {
        if hasKey {
            return RemoteBrain(provider: provider,
                               key: key.trimmingCharacters(in: .whitespaces),
                               model: model)
        }
        return OnDeviceBrain.isAvailable ? OnDeviceBrain() : nil
    }

    var status: String {
        if hasKey { return "\(provider.label) · \(model)" }
        if OnDeviceBrain.isAvailable { return "On device" }
        return "Not connected"
    }
}

// MARK: - Keychain

enum Keychain {

    static func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return remove(account) }
        var query = base(account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.metwho.app",
         kSecAttrAccount as String: account]
    }
}
