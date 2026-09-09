import Foundation
import SwiftUI
import LingCore

@MainActor
final class SettingsEditorModel: ObservableObject {
    typealias ConnectionTest = @Sendable (LingConfiguration, String) async throws -> LingCompletion

    @Published var configuration: LingConfiguration {
        didSet { cancelTest() }
    }
    @Published var apiKey: String {
        didSet { cancelTest() }
    }
    @Published private(set) var testing = false
    @Published private(set) var message = ""
    @Published private(set) var failed = false
    let settings: SettingsStore
    private(set) var testTask: Task<Void, Never>?
    private var testID = UUID()
    private let connect: ConnectionTest

    init(settings: SettingsStore, connect: @escaping ConnectionTest = { configuration, key in
        try await LingClient().complete(configuration: configuration, apiKey: key, question: "只回复 OK。")
    }) {
        self.settings = settings
        self.connect = connect
        configuration = settings.configuration
        apiKey = settings.apiKey
    }

    func cancelTest() {
        testID = UUID()
        testTask?.cancel()
        testTask = nil
        testing = false
        message = ""
        failed = false
    }

    func test() {
        cancelTest()
        testing = true
        let id = testID
        let configuration = configuration
        let key = apiKey
        let connect = connect
        testTask = Task { [weak self] in
            do {
                let result = try await connect(configuration, key)
                guard !Task.isCancelled, let self, self.testID == id else { return }
                self.failed = result.isTruncated
                self.message = result.isTruncated
                    ? "接口已响应，但回答达到长度上限。请检查模型配置。\n\(result.text)"
                    : "连接成功 · \(configuration.model.trimmingCharacters(in: .whitespacesAndNewlines))\n\(result.text)"
                self.testing = false
                self.testTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.testID == id else { return }
                self.failed = true
                self.message = error.localizedDescription
                self.testing = false
                self.testTask = nil
            }
        }
    }

    func save() -> Bool {
        cancelTest()
        do {
            try settings.save(configuration: configuration, apiKey: apiKey)
            return true
        } catch {
            message = error.localizedDescription
            failed = true
            return false
        }
    }
}
