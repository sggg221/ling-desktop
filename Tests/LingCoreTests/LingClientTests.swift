import Foundation
import LingCore

final class LingClientTests {
    private var session: URLSession!
    private var client: LingClient!
    private let key = "test-key-do-not-use"

    func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = LingClient(session: session)
    }

    func tearDown() {
        session.invalidateAndCancel()
        MockURLProtocol.setHandler(nil)
        client = nil
        session = nil
    }

    func testImageAndQuestionWireFormatAndAnswer() async throws {
        let expectedKey = key
        let image = Data([0x89, 0x50, 0x4e, 0x47])
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.absoluteString, "https://maas-api.antdigital.com/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + expectedKey)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.timeoutInterval, 90)
            let body = try Self.body(of: request)
            XCTAssertEqual(body["model"] as? String, "Ling-3.0-flash-VL")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 2048)
            XCTAssertEqual(body["stream"] as? Bool, false)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages[0]["role"] as? String, "user")
            let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[0]["type"] as? String, "image_url")
            XCTAssertEqual((content[0]["image_url"] as? [String: String])?["url"],
                           "data:image/png;base64," + image.base64EncodedString())
            XCTAssertEqual(content[1]["type"] as? String, "text")
            XCTAssertEqual(content[1]["text"] as? String, "What is on screen?")
            return Self.response(request, body: #"{"choices":[{"message":{"content":"  An editor.\n"}}]}"#)
        }
        let result = try await client.complete(
            configuration: LingConfiguration(), apiKey: key,
            question: "  What is on screen?  ", imageData: image
        )
        XCTAssertEqual(result.text, "An editor.")
        XCTAssertNil(result.finishReason)
        XCTAssertFalse(result.isTruncated)
    }

    func testTextOnlyUsesConfiguredModelWithoutImage() async throws {
        MockURLProtocol.setHandler { request in
            let body = try Self.body(of: request)
            XCTAssertEqual(body["model"] as? String, "custom-model")
            let content = try Self.content(of: body)
            XCTAssertEqual(content.count, 1)
            XCTAssertEqual(content[0]["type"] as? String, "text")
            XCTAssertEqual(content[0]["text"] as? String, "Hello")
            XCTAssertNil(content[0]["image_url"])
            return Self.response(request)
        }
        _ = try await client.complete(
            configuration: LingConfiguration(model: "custom-model"),
            apiKey: key, question: "Hello"
        )
    }

    func testImageOnlyAddsDescribePrompt() async throws {
        MockURLProtocol.setHandler { request in
            let content = try Self.content(of: Self.body(of: request))
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[0]["type"] as? String, "image_url")
            XCTAssertFalse(try XCTUnwrap(content[1]["text"] as? String).isEmpty)
            return Self.response(request)
        }
        _ = try await client.complete(
            configuration: LingConfiguration(), apiKey: key,
            question: " \n", imageData: Data([1])
        )
    }

    func testRejectsEmptyInputBeforeNetworking() async {
        MockURLProtocol.setHandler { request in
            XCTFail("Empty input must not make a network request.")
            return Self.response(request)
        }
        do {
            _ = try await client.complete(
                configuration: LingConfiguration(), apiKey: key,
                question: " \n", imageData: Data()
            )
            XCTFail("Expected empty input error.")
        } catch {
            XCTAssertEqual(error as? LingClientError, .emptyInput)
        }
    }

    func testBaseURLNormalization() async throws {
        let cases: [(String, String)] = [
            ("https://maas-api.antdigital.com/v1", "https://maas-api.antdigital.com/v1/chat/completions"),
            ("https://maas-api.antdigital.com/v1/chat/completions", "https://maas-api.antdigital.com/v1/chat/completions"),
            ("https://example.com", "https://example.com/v1/chat/completions"),
            ("https://example.com/", "https://example.com/v1/chat/completions"),
            ("https://example.com/v1/", "https://example.com/v1/chat/completions"),
            ("https://example.com/v1/chat/completions", "https://example.com/v1/chat/completions"),
            ("https://example.com/v1/chat/completions/", "https://example.com/v1/chat/completions"),
            (" https://example.com/chat/completions \n", "https://example.com/chat/completions"),
            ("https://example.com/proxy/v1", "https://example.com/proxy/v1/chat/completions"),
            ("http://localhost:8080/v1", "http://localhost:8080/v1/chat/completions"),
            ("http://127.0.0.1:8080", "http://127.0.0.1:8080/v1/chat/completions")
        ]
        for (base, expected) in cases {
            MockURLProtocol.setHandler { request in
                XCTAssertEqual(request.url?.absoluteString, expected)
                return Self.response(request)
            }
            _ = try await client.complete(
                configuration: LingConfiguration(baseURL: base), apiKey: key, question: "Hi"
            )
        }
    }

    func testRejectsInsecureAndInvalidConfigurationBeforeNetworking() async {
        MockURLProtocol.setHandler { request in
            XCTFail("Invalid configuration must not make a request.")
            return Self.response(request)
        }
        let configurations = [
            LingConfiguration(baseURL: "http://example.com/v1"),
            LingConfiguration(baseURL: "file:///v1"),
            LingConfiguration(baseURL: "example.com"),
            LingConfiguration(baseURL: "https://user:secret@example.com/v1"),
            LingConfiguration(baseURL: "https://example.com/v1?key=secret"),
            LingConfiguration(baseURL: "https://example.com/v1#section"),
            LingConfiguration(model: " \n")
        ]
        for configuration in configurations {
            do {
                _ = try await client.complete(configuration: configuration, apiKey: key, question: "Hi")
                XCTFail("Expected invalid configuration error.")
            } catch {
                guard case .invalidConfiguration = error as? LingClientError else {
                    XCTFail("Unexpected error: \(error)")
                    continue
                }
            }
        }
        do {
            _ = try await client.complete(configuration: LingConfiguration(), apiKey: "  ", question: "Hi")
            XCTFail("Expected empty key to be rejected.")
        } catch {
            guard case .invalidConfiguration = error as? LingClientError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testHTTP401PreservesStatusAndRedactsReflectedKey() async {
        let reflectedKey = key
        MockURLProtocol.setHandler { request in
            Self.response(request, status: 401,
                          body: "{\"error\":{\"message\":\"Invalid API key: \(reflectedKey)\"}}")
        }
        do {
            _ = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
            XCTFail("Expected HTTP error.")
        } catch {
            XCTAssertEqual(error as? LingClientError,
                           .httpError(statusCode: 401, message: "Invalid API key: [redacted]"))
            XCTAssertFalse(error.localizedDescription.contains(key))
        }
    }

    func testHTTP404IncludesPlainResponseBody() async {
        MockURLProtocol.setHandler { request in
            Self.response(request, status: 404, body: "Requested model not found")
        }
        do {
            _ = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
            XCTFail("Expected HTTP error.")
        } catch {
            XCTAssertEqual(error as? LingClientError,
                           .httpError(statusCode: 404, message: "Requested model not found"))
        }
    }

    func testMalformedAndEmptyResponsesFailClearly() async {
        for body in [
            "not JSON", "{}", #"{"choices":[]}"#,
            #"{"choices":[{"message":{"content":null}}]}"#,
            #"{"choices":[{"message":{"content":" \n"}}]}"#,
            #"{"choices":[{"message":{"content":42}}]}"#
        ] {
            MockURLProtocol.setHandler { request in Self.response(request, body: body) }
            do {
                _ = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
                XCTFail("Expected invalid response error for \(body).")
            } catch {
                guard case .invalidResponse = error as? LingClientError else {
                    XCTFail("Unexpected error: \(error)")
                    continue
                }
            }
        }
    }

    func testTextContentArrayIsSupported() async throws {
        MockURLProtocol.setHandler { request in
            Self.response(request, body: #"{"choices":[{"message":{"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]}}]}"#)
        }
        let answer = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
        XCTAssertEqual(answer.text, "First\nSecond")
    }

    func testFinishReasonDistinguishesTruncatedAnswers() async throws {
        let cases: [(String, String?, Bool)] = [
            (#"{"choices":[{"finish_reason":"length","message":{"content":"  Partial answer  "}}]}"#, "length", true),
            (#"{"choices":[{"finish_reason":"stop","message":{"content":"  Partial answer  "}}]}"#, "stop", false),
            (#"{"choices":[{"finish_reason":null,"message":{"content":"  Partial answer  "}}]}"#, nil, false),
            (#"{"choices":[{"message":{"content":"  Partial answer  "}}]}"#, nil, false),
            (#"{"choices":[{"finish_reason":"custom","message":{"content":"  Partial answer  "}}]}"#, "custom", false)
        ]
        for (body, finishReason, truncated) in cases {
            MockURLProtocol.setHandler { request in Self.response(request, body: body) }
            let result = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
            XCTAssertEqual(result.text, "Partial answer")
            XCTAssertEqual(result.finishReason, finishReason)
            XCTAssertEqual(result.isTruncated, truncated)
        }
    }

    func testTruncatedTextArrayPreservesPartialAnswer() async throws {
        MockURLProtocol.setHandler { request in
            Self.response(request, body: #"{"choices":[{"finish_reason":"length","message":{"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]}},{"finish_reason":"stop","message":{"content":"Ignored choice"}}]}"#)
        }
        let result = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
        XCTAssertEqual(result.text, "First\nSecond")
        XCTAssertEqual(result.finishReason, "length")
        XCTAssertEqual(result.isTruncated, true)
    }

    func testConfigurationValidationDoesNotRequireCredentialsOrNetwork() throws {
        MockURLProtocol.setHandler { request in
            XCTFail("Saving configuration must not make a network request.")
            return Self.response(request)
        }
        try LingConfiguration().validate()
        try LingConfiguration(baseURL: " https://example.com/v1/chat/completions ", model: " custom ").validate()
        try LingConfiguration(baseURL: "http://localhost:8080/v1").validate()
        for configuration in [
            LingConfiguration(baseURL: "http://example.com/v1"),
            LingConfiguration(baseURL: "https://user:secret@example.com/v1"),
            LingConfiguration(baseURL: "https://example.com/v1?key=secret"),
            LingConfiguration(baseURL: "https://example.com/v1#section"),
            LingConfiguration(baseURL: ""),
            LingConfiguration(model: " \n")
        ] {
            do {
                try configuration.validate()
                XCTFail("Expected invalid configuration to be rejected before saving.")
            } catch {
                guard case .invalidConfiguration = error as? LingClientError else {
                    XCTFail("Unexpected error: \(error)")
                    continue
                }
            }
        }
    }

    func testTimeoutIsReportedDistinctly() async {
        MockURLProtocol.setHandler { _ in throw URLError(.timedOut) }
        do {
            _ = try await client.complete(configuration: LingConfiguration(), apiKey: key, question: "Hi")
            XCTFail("Expected timeout.")
        } catch {
            XCTAssertEqual(error as? LingClientError, .timeout)
        }
    }

    func testConnectionUsesRealCompletionPath() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let content = try Self.content(of: Self.body(of: request))
            XCTAssertEqual(content[0]["text"] as? String, "Reply with OK.")
            return Self.response(request)
        }
        let answer = try await client.testConnection(configuration: LingConfiguration(), apiKey: key)
        XCTAssertEqual(answer, "OK")
    }

    private static func body(of request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var received = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                received.append(buffer, count: count)
            }
            data = received
        } else {
            throw XCTUnwrapError.missingBody
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func content(of body: [String: Any]) throws -> [[String: Any]] {
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let message = try XCTUnwrap(messages.first)
        return try XCTUnwrap(message["content"] as? [[String: Any]])
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        body: String = #"{"choices":[{"message":{"content":"OK"}}]}"#
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                         headerFields: ["Content-Type": "application/json"])!, Data(body.utf8))
    }

    private enum XCTUnwrapError: Error { case missingBody }
}

private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    private static var handler: Handler?

    static func setHandler(_ newHandler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        handler = newHandler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
