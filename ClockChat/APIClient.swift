import Foundation

struct APIClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // Never forward a secret to another endpoint.
        }
    }
    static func endpoint(_ connection: Connection, path: String) throws -> URL {
        guard var parts = URLComponents(string: connection.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw AppFailure.message("Vul een basis-URL in, bijvoorbeeld https://api.openai.com/v1.")
        }
        if connection.provider == .openAI && (scheme != "https" || host.lowercased() != "api.openai.com") {
            throw AppFailure.message("Gebruik voor OpenAI https://api.openai.com/v1. Zo blijft je sleutel bij OpenAI.")
        }
        var base = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for suffix in ["/chat/completions", "/models"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
        }
        if base.isEmpty { base = "v1" }
        parts.path = "/" + base + "/" + path
        guard let url = parts.url else { throw AppFailure.message("Ongeldige URL.") }
        return url
    }
    private static func request(_ connection: Connection, key: String, path: String) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(connection, path: path))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        if connection.provider == .openAI && key.isEmpty {
            throw AppFailure.message("Vul eerst je OpenAI API-sleutel in bij Instellingen.")
        }
        return request
    }
    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw AppFailure.message("Ongeldig serverantwoord.") }
        guard (200..<300).contains(response.statusCode) else {
            let text: String
            switch response.statusCode {
            case 300..<400: text = "Omleiding geweigerd. Gebruik het definitieve API-adres."
            case 401, 403: text = "Geen toegang. Controleer de API-sleutel en modelrechten."
            case 404: text = "API-adres of model niet gevonden. Controleer de instellingen."
            case 429: text = "Limiet bereikt. Controleer je API-tegoed of probeer later opnieuw."
            default: text = "De server kon het verzoek niet verwerken."
            }
            throw AppFailure.message("HTTP \(response.statusCode): \(text)")
        }
    }
    static func models(_ connection: Connection, key: String) async throws -> [String] {
        let request = try request(connection, key: key, path: "models")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        struct ModelList: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
    }
    static func stream(_ connection: Connection, key: String, messages: [Message],
                       onChunk: @escaping @MainActor (String) -> Void) async throws {
        var request = try request(connection, key: key, path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": connection.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }, "stream": true
        ])
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Content: Decodable { let content: String? }
                let delta: Content?
                let message: Content?
            }
            struct Failure: Decodable { let message: String }
            let choices: [Choice]?
            let error: Failure?
        }
        var received = false
        func deliver(_ data: Data) async throws {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            if envelope.error != nil { throw AppFailure.message("De server meldt een fout. Controleer model, toegang en API-tegoed.") }
            if let choice = envelope.choices?.first,
               let text = choice.delta?.content ?? choice.message?.content, !text.isEmpty {
                received = true
                await onChunk(text)
            }
        }
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json") {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count > 8_000_000 { throw AppFailure.message("Serverantwoord is te groot.") }
            }
            try await deliver(data)
        } else {
            // These three providers emit one JSON object per SSE data line.
            // Parsing each data line also works with AsyncLineSequence implementations
            // that omit empty separator lines.
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                if !payload.isEmpty { try await deliver(Data(payload.utf8)) }
            }
        }
        if !received { throw AppFailure.message("Geen tekst ontvangen. Kies een model dat Chat Completions ondersteunt.") }
    }
}
