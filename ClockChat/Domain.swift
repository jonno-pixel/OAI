import Foundation

struct Message: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: String
    var content: String
    var interrupted = false
}
struct Conversation: Identifiable, Codable {
    var id = UUID()
    var title = "Nieuw gesprek"
    var updated = Date()
    var messages: [Message] = []
}
enum Provider: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI", ollama = "Ollama", lmStudio = "LM Studio"
    var id: String { rawValue }
    var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .ollama: "http://192.168.1.100:11434/v1"
        case .lmStudio: "http://192.168.1.100:1234/v1"
        }
    }
}
struct Connection: Codable {
    var provider: Provider = .openAI
    var url = Provider.openAI.baseURL
    var model = ""
}
struct SavedState: Codable {
    var connections: [String: Connection] = [:]
    var selectedProvider: Provider = .openAI
    var conversations: [Conversation] = []
}
enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
