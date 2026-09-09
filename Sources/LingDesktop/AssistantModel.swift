import AppKit
import SwiftUI
import LingCore

@MainActor
final class AssistantModel: ObservableObject {
    @Published var imageData: Data?
    @Published var question = ""
    @Published var answer = ""
    @Published var answerIsTruncated = false
    @Published var error: String?
    @Published var isLoading = false
    @Published var elapsed: Double?
    let settings: SettingsStore
    private let client = LingClient()
    private var request: Task<Void, Never>?
    private var requestID = UUID()

    init(settings: SettingsStore) { self.settings = settings }

    func setCapture(_ data: Data) {
        cancel()
        imageData = data
        question = ""
        answer = ""
        answerIsTruncated = false
        error = nil
        elapsed = nil
    }

    func cancel() {
        requestID = UUID()
        request?.cancel()
        request = nil
        isLoading = false
    }

    func submit() {
        guard !isLoading else { return }
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || imageData != nil else { return }
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "请先在设置中填写百灵 API Key。"
            return
        }
        answer = ""
        answerIsTruncated = false
        error = nil
        elapsed = nil
        isLoading = true
        let id = UUID()
        requestID = id
        let config = settings.configuration
        let key = settings.apiKey
        let image = imageData
        request = Task {
            let start = Date()
            do {
                let result = try await client.complete(configuration: config, apiKey: key,
                                                       question: prompt, imageData: image)
                guard !Task.isCancelled, requestID == id else { return }
                answer = result.text
                answerIsTruncated = result.isTruncated
                elapsed = Date().timeIntervalSince(start)
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                self.error = error.localizedDescription
            }
            if requestID == id { isLoading = false; request = nil }
        }
    }
}
