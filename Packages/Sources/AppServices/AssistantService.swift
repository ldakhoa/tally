import BudgetKit
import ClaudeKit
import Foundation
import Observation
import TallyCore

public struct ChatEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: ClaudeMessage.Role
    public var text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: ClaudeMessage.Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

/// Streaming Claude assistant with live household budget context.
@MainActor
@Observable
public final class AssistantService {
    public private(set) var messages: [ChatEntry] = []
    public private(set) var isStreaming = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private var activeTask: Task<Void, Never>?

    public init() {}

    public func send(_ text: String, settings: AppSettings, store: BudgetStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        guard let client = settings.makeAIClient() else {
            errorMessage = ClaudeError.missingAPIKey.localizedMessage(in: settings.language)
            return
        }

        errorMessage = nil
        messages.append(ChatEntry(role: .user, text: trimmed))
        let assistantID = UUID()
        messages.append(ChatEntry(role: .assistant, text: ""))
        isStreaming = true

        let systemPrompt = BudgetAssistantPrompt.systemPrompt(
            snapshot: store.snapshot,
            goals: store.activeGoals,
            currency: settings.currency,
            language: settings.language
        )
        let wireMessages = messages.dropLast().map { ClaudeMessage(role: $0.role, content: $0.text) }
        let request = ClaudeRequest(
            system: systemPrompt,
            messages: wireMessages,
            maxTokens: 2_048,
            effort: .low,
            cacheConversation: true
        )
        let lang = settings.language

        activeTask?.cancel()
        activeTask = Task {
            defer { self.isStreaming = false }
            do {
                for try await event in client.stream(request) {
                    if case .text(let chunk) = event,
                       let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                        self.messages[idx].text += chunk
                    }
                }
            } catch is CancellationError {
                return
            } catch let err as ClaudeError {
                self.errorMessage = err.localizedMessage(in: lang)
                self.dropEmptyAssistant(id: assistantID)
            } catch {
                self.errorMessage = error.localizedDescription
                self.dropEmptyAssistant(id: assistantID)
            }
        }
    }

    public func clear() {
        activeTask?.cancel()
        isStreaming = false
        errorMessage = nil
        messages.removeAll()
    }

    private func dropEmptyAssistant(id: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == id }), messages[idx].text.isEmpty {
            messages.remove(at: idx)
        }
    }
}
