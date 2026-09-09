import XCTest
import LingCore
@testable import LingDesktop

final class SettingsTests: XCTestCase {
    @MainActor
    private func makeStore(saveKey: @escaping (String) throws -> Void = { _ in }) -> (SettingsStore, UserDefaults) {
        let suite = "LingDesktopTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        defaults.set("https://saved.example/v1", forKey: "lingBaseURL")
        defaults.set("saved-model", forKey: "lingModel")
        return (SettingsStore(defaults: defaults, readKey: { "saved-key" }, saveKey: saveKey), defaults)
    }

    @MainActor
    func testDraftDoesNotChangeActiveOrPersistedSettings() async {
        var writes: [String] = []
        let (store, defaults) = makeStore { writes.append($0) }
        let saved = store.configuration
        let editor = SettingsEditorModel(settings: store)
        editor.configuration = LingConfiguration(baseURL: "https://draft.example/v1", model: "draft-model")
        editor.apiKey = "draft-key"
        editor.cancelTest()

        XCTAssertEqual(store.configuration, saved)
        XCTAssertEqual(store.apiKey, "saved-key")
        XCTAssertEqual(defaults.string(forKey: "lingBaseURL"), saved.baseURL)
        XCTAssertEqual(defaults.string(forKey: "lingModel"), saved.model)
        XCTAssertTrue(writes.isEmpty)
        let reopened = SettingsEditorModel(settings: store)
        XCTAssertEqual(reopened.configuration, saved)
        XCTAssertEqual(reopened.apiKey, "saved-key")
    }

    @MainActor
    func testSuccessfulSaveNormalizesAndAppliesDraft() async {
        var writes: [String] = []
        let (store, defaults) = makeStore { writes.append($0) }
        let editor = SettingsEditorModel(settings: store)
        editor.configuration = LingConfiguration(baseURL: " https://new.example/v1 \n", model: " new-model ")
        editor.apiKey = " new-key \n"

        XCTAssertTrue(editor.save())
        XCTAssertEqual(store.configuration, LingConfiguration(baseURL: "https://new.example/v1", model: "new-model"))
        XCTAssertEqual(store.apiKey, "new-key")
        XCTAssertEqual(writes, ["new-key"])
        XCTAssertEqual(defaults.string(forKey: "lingBaseURL"), store.baseURL)
        XCTAssertEqual(defaults.string(forKey: "lingModel"), store.model)
    }

    @MainActor
    func testInvalidDraftCannotWriteCredentialsOrSettings() async {
        var writes: [String] = []
        let (store, defaults) = makeStore { writes.append($0) }
        let saved = store.configuration
        let editor = SettingsEditorModel(settings: store)
        editor.configuration.baseURL = "http://remote.example/v1"
        editor.apiKey = "new-key"

        XCTAssertFalse(editor.save())
        XCTAssertTrue(editor.failed)
        XCTAssertFalse(editor.message.isEmpty)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(store.configuration, saved)
        XCTAssertEqual(store.apiKey, "saved-key")
        XCTAssertEqual(defaults.string(forKey: "lingBaseURL"), saved.baseURL)
        XCTAssertEqual(defaults.string(forKey: "lingModel"), saved.model)
    }

    @MainActor
    func testKeychainFailureLeavesActiveAndPersistedSettingsUnchanged() async {
        struct SaveFailure: Error {}
        let (store, defaults) = makeStore { _ in throw SaveFailure() }
        let saved = store.configuration
        let editor = SettingsEditorModel(settings: store)
        editor.configuration = LingConfiguration(baseURL: "https://new.example/v1", model: "new-model")
        editor.apiKey = "new-key"

        XCTAssertFalse(editor.save())
        XCTAssertTrue(editor.failed)
        XCTAssertEqual(store.configuration, saved)
        XCTAssertEqual(store.apiKey, "saved-key")
        XCTAssertEqual(defaults.string(forKey: "lingBaseURL"), saved.baseURL)
        XCTAssertEqual(defaults.string(forKey: "lingModel"), saved.model)
    }

    @MainActor
    func testSavingEmptyKeyStillAllowsCredentialRemoval() async {
        var writes: [String] = []
        let (store, _) = makeStore { writes.append($0) }
        let editor = SettingsEditorModel(settings: store)
        editor.apiKey = " \n"
        XCTAssertTrue(editor.save())
        XCTAssertEqual(writes, [""])
        XCTAssertEqual(store.apiKey, "")
    }

    @MainActor
    func testConnectionUsesDraftWithoutSavingAndClearsStaleSuccess() async throws {
        let (store, _) = makeStore()
        let expected = LingConfiguration(baseURL: "https://draft.example/v1", model: "draft-model")
        let editor = SettingsEditorModel(settings: store) { configuration, key in
            XCTAssertEqual(configuration, expected)
            XCTAssertEqual(key, "draft-key")
            return LingCompletion(text: "OK", finishReason: "stop")
        }
        editor.configuration = expected
        editor.apiKey = "draft-key"
        editor.test()
        let task = try XCTUnwrap(editor.testTask)
        await task.value

        XCTAssertFalse(editor.testing)
        XCTAssertFalse(editor.failed)
        XCTAssertTrue(editor.message.contains("draft-model"))
        XCTAssertEqual(store.model, "saved-model")
        XCTAssertEqual(store.apiKey, "saved-key")
        editor.configuration.model = "changed-model"
        XCTAssertEqual(editor.message, "")
    }

    @MainActor
    func testEditsCloseAndSaveIgnoreLateConnectionResults() async throws {
        for action in 0..<5 {
            let (store, _) = makeStore()
            let started = expectation(description: "Connection started for action \(action)")
            let pending = PendingConnection(started: started)
            let editor = SettingsEditorModel(settings: store) { _, _ in await pending.run() }
            editor.test()
            let task = try XCTUnwrap(editor.testTask)
            await fulfillment(of: [started], timeout: 2)
            switch action {
            case 0: editor.configuration.baseURL = "https://changed.example/v1"
            case 1: editor.configuration.model = "changed-model"
            case 2: editor.apiKey = "changed-key"
            case 3: editor.cancelTest()
            default: XCTAssertTrue(editor.save())
            }
            await pending.finish()
            await task.value

            XCTAssertFalse(editor.testing)
            XCTAssertEqual(editor.message, "")
            XCTAssertFalse(editor.failed)
        }
    }

    @MainActor
    func testOldConnectionCannotOverwriteNewConnectionState() async throws {
        let (store, _) = makeStore()
        let oldStarted = expectation(description: "Old connection started")
        let newStarted = expectation(description: "New connection started")
        let oldConnection = PendingConnection(started: oldStarted)
        let newConnection = PendingConnection(started: newStarted)
        let editor = SettingsEditorModel(settings: store) { configuration, _ in
            if configuration.model == "new-model" { return await newConnection.run() }
            return await oldConnection.run()
        }
        editor.test()
        let oldTask = try XCTUnwrap(editor.testTask)
        await fulfillment(of: [oldStarted], timeout: 2)
        editor.configuration.model = "new-model"
        editor.test()
        let newTask = try XCTUnwrap(editor.testTask)
        await fulfillment(of: [newStarted], timeout: 2)

        await oldConnection.finish()
        await oldTask.value
        XCTAssertTrue(editor.testing)
        XCTAssertEqual(editor.message, "")

        await newConnection.finish()
        await newTask.value
        XCTAssertFalse(editor.testing)
        XCTAssertTrue(editor.message.contains("new-model"))
    }
}

private actor PendingConnection {
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<LingCompletion, Never>?
    private var finished = false

    init(started: XCTestExpectation) { self.started = started }

    func run() async -> LingCompletion {
        started.fulfill()
        if finished { return LingCompletion(text: "OK") }
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        finished = true
        continuation?.resume(returning: LingCompletion(text: "OK"))
        continuation = nil
    }
}
