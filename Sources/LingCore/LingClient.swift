import Foundation

public struct LingConfiguration: Equatable, Sendable {
    public var baseURL: String
    public var model: String

    public init(
        baseURL: String = "https://maas-api.antdigital.com/v1",
        model: String = "Ling-3.0-flash-VL"
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    public func validate() throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LingClientError.invalidConfiguration("Enter a model name in Settings.")
        }
        _ = try LingClient.endpoint(for: baseURL)
    }
}

public struct LingCompletion: Equatable, Sendable {
    public let text: String
    public let finishReason: String?
    public var isTruncated: Bool { finishReason == "length" }

    public init(text: String, finishReason: String? = nil) {
        self.text = text
        self.finishReason = finishReason
    }
}

public enum LingClientError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case emptyInput
    case httpError(statusCode: Int, message: String)
    case invalidResponse(String)
    case timeout
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            return detail
        case .emptyInput:
            return "Enter a question or capture an image before sending."
        case .httpError(let status, let message):
            return "Ling API returned HTTP \(status): \(message)"
        case .invalidResponse(let detail):
            return "Invalid Ling API response: \(detail)"
        case .timeout:
            return "The Ling API request timed out after 90 seconds. Please try again."
        case .transport(let detail):
            return "Unable to reach the Ling API: \(detail)"
        }
    }
}

/// A stateless client. The API key is supplied for each request and is never persisted.
public struct LingClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        // Keep screenshot requests, responses and cookies off the disk cache.
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    public func complete(
        configuration: LingConfiguration,
        apiKey: String,
        question: String,
        imageData: Data? = nil
    ) async throws -> LingCompletion {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw LingClientError.invalidConfiguration("Enter your Ling API key in Settings.")
        }
        try configuration.validate()
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = try Self.endpoint(for: configuration.baseURL)
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = imageData.flatMap { $0.isEmpty ? nil : $0 }
        guard !trimmedQuestion.isEmpty || image != nil else {
            throw LingClientError.emptyInput
        }

        var content: [ContentItem] = []
        if let image {
            content.append(ContentItem(
                type: "image_url",
                imageURL: ImageURL(url: "data:image/png;base64," + image.base64EncodedString())
            ))
        }
        content.append(ContentItem(
            type: "text",
            text: trimmedQuestion.isEmpty
                ? "请描述这张图片，并指出重要信息。"
                : trimmedQuestion
        ))

        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(CompletionRequest(
            model: model,
            messages: [Message(role: "user", content: content)],
            maxCompletionTokens: 2048,
            stream: false
        ))

        let data: Data
        let response: URLResponse
        do {
            // Do not forward a credential-bearing request to a redirected endpoint.
            (data, response) = try await session.data(for: request, delegate: RedirectBlocker())
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw LingClientError.timeout
            }
            throw LingClientError.transport(Self.redactedDetail(error.localizedDescription, key: key))
        }

        guard let response = response as? HTTPURLResponse else {
            throw LingClientError.invalidResponse("The server did not return an HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw LingClientError.httpError(
                statusCode: response.statusCode,
                message: Self.errorDetail(data, statusCode: response.statusCode, key: key)
            )
        }

        let completion: CompletionResponse
        do {
            completion = try JSONDecoder().decode(CompletionResponse.self, from: data)
        } catch {
            throw LingClientError.invalidResponse("Expected JSON containing choices[0].message.content.")
        }
        guard let answer = completion.choices.first?.message.content?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
            throw LingClientError.invalidResponse("The server returned no answer text.")
        }
        return LingCompletion(text: answer, finishReason: completion.choices.first?.finishReason)
    }

    public func testConnection(configuration: LingConfiguration, apiKey: String) async throws -> String {
        let result = try await complete(
            configuration: configuration,
            apiKey: apiKey,
            question: "Reply with OK."
        )
        return result.text
    }

    fileprivate static func endpoint(for baseURL: String) throws -> URL {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw LingClientError.invalidConfiguration("Enter a valid API base URL without credentials, a query, or a fragment.")
        }
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw LingClientError.invalidConfiguration("The API base URL must use HTTPS (HTTP is allowed only for localhost).")
        }
        components.scheme = scheme
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty {
            path = "/v1/chat/completions"
        } else if !path.hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }
        components.path = path
        guard let url = components.url else {
            throw LingClientError.invalidConfiguration("The API base URL is invalid.")
        }
        return url
    }

    private static func errorDetail(_ data: Data, statusCode: Int, key: String) -> String {
        var detail: String?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any] {
                detail = error["message"] as? String
            } else if let error = object["error"] as? String {
                detail = error
            }
            detail = detail ?? object["message"] as? String
        }
        detail = detail ?? String(data: data, encoding: .utf8)
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return redactedDetail(
            trimmed.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: statusCode) : trimmed,
            key: key
        )
    }

    private static func redactedDetail(_ detail: String, key: String) -> String {
        let safe = detail.replacingOccurrences(of: key, with: "[redacted]")
        return safe.count > 1_400 ? String(safe.prefix(1_400)) + "…" : safe
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct CompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxCompletionTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct Message: Encodable {
    let role: String
    let content: [ContentItem]
}

private struct ContentItem: Encodable {
    let type: String
    var text: String? = nil
    var imageURL: ImageURL? = nil

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

private struct ImageURL: Encodable {
    let url: String
}

private struct CompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: AssistantMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct AssistantMessage: Decodable {
        let content: AssistantContent?
    }

    enum AssistantContent: Decodable {
        case string(String)
        case parts([Part])

        struct Part: Decodable {
            let type: String?
            let text: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .parts(try container.decode([Part].self))
            }
        }

        var text: String {
            switch self {
            case .string(let text): return text
            case .parts(let parts):
                return parts.filter { $0.type == nil || $0.type == "text" }
                    .compactMap(\.text).joined(separator: "\n")
            }
        }
    }
}
