import Foundation

private final class StubLLMURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing test handler") }
        Self.requests.append(request)
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func bodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 4096)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

enum LLMAPITransportTests {
    static func run() async {
        func perform(_ replies: [(Int, String)], body payload: [String: Any] = ["model": "fixture", "temperature": 0, "messages": []], endpoint: String = UUID().uuidString, cache: TemperatureCapabilityCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-\(UUID().uuidString)")!)) async throws -> [URLRequest] {
            StubLLMURLProtocol.requests = []
            var remaining = replies
            StubLLMURLProtocol.handler = { _ in
                let next = remaining.removeFirst()
                return (next.0, Data(next.1.utf8))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubLLMURLProtocol.self]
            let session = URLSession(configuration: configuration)
            let body = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: URL(string: "https://provider.invalid/\(endpoint)/chat")!)
            request.httpMethod = "POST"
            request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (_, response) = try await LLMAPITransport.data(for: request, using: session, cache: cache)
            session.invalidateAndCancel()
            _ = response
            return StubLLMURLProtocol.requests
        }

        let rejected = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":\"temperature\",\"message\":\"temperature is unsupported\"}}"
        let accepted = "{\"choices\":[]}"
        let retry = try! await perform([(400, rejected), (200, accepted)])
        TestSupport.expect(retry.count == 2, "Unsupported temperature should retry once")
        let original = try! JSONSerialization.jsonObject(with: bodyData(retry[0])!) as! [String: Any]
        let retried = try! JSONSerialization.jsonObject(with: bodyData(retry[1])!) as! [String: Any]
        TestSupport.expect(original["temperature"] != nil, "Initial body retains temperature")
        TestSupport.expect(retried["temperature"] == nil && retried["model"] as? String == "fixture" && retried["messages"] != nil, "Retry removes only temperature")
        TestSupport.expect(retry.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token" && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" }, "Retry preserves authorization and content type")

        let openAIStyle = "{\"error\":{\"code\":\"unsupported_value\",\"param\":\"temperature\",\"message\":\"Unsupported value: 'temperature' does not support 0 with this model. Only the default (1) value is supported.\"}}"
        let openAIRetry = try! await perform([(400, openAIStyle), (200, accepted)])
        TestSupport.expect(openAIRetry.count == 2, "OpenAI unsupported_value response retries once")

        let otherParameter = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":\"max_tokens\",\"message\":\"Unsupported parameter\"}}"
        let wrongParam = try! await perform([(400, otherParameter)])
        TestSupport.expect(wrongParam.count == 1, "Unsupported parameter other than temperature does not retry")

        let nullParam = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":null,\"message\":\"temperature is not supported with this model\"}}"
        let nullParamRetry = try! await perform([(400, nullParam), (200, accepted)])
        TestSupport.expect(nullParamRetry.count == 2, "Temperature message fallback retries when param is null")

        let success = try! await perform([(200, accepted)])
        TestSupport.expect(success.count == 1, "Successful call does not retry")
        let retained = try! JSONSerialization.jsonObject(with: bodyData(success[0])!) as! [String: Any]
        TestSupport.expect(retained["temperature"] != nil, "Compatible call retains temperature")

        let unrelated = try! await perform([(400, "{\"error\":{\"code\":\"invalid_api_key\",\"message\":\"bad key\"}}")])
        TestSupport.expect(unrelated.count == 1, "Unrelated 400 does not retry")
        let noTemperature = try! await perform([(400, rejected)], body: ["model": "fixture", "messages": []])
        TestSupport.expect(noTemperature.count == 1, "Request without temperature does not retry")

        let rejectedAgain = try! await perform([(400, rejected), (400, rejected)])
        TestSupport.expect(rejectedAgain.count == 2, "Second rejection stops after one retry")

        let persistentCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-persistent-\(UUID().uuidString)")!)
        let endpoint = UUID().uuidString
        let first = try! await perform([(400, rejected), (200, accepted)], endpoint: endpoint, cache: persistentCache)
        let subsequent = try! await perform([(200, accepted)], endpoint: endpoint, cache: persistentCache)
        let omittedBody = try! JSONSerialization.jsonObject(with: bodyData(subsequent[0])!) as! [String: Any]
        TestSupport.expect(first.count == 2 && subsequent.count == 1 && omittedBody["temperature"] == nil, "Runtime rejection is cached and subsequent call omits temperature")

        let sharedEndpoint = UUID().uuidString
        var sharedRequest = URLRequest(url: URL(string: "https://provider.invalid/\(sharedEndpoint)/chat")!)
        sharedRequest.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
        sharedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sharedRequest.httpBody = try! JSONSerialization.data(withJSONObject: ["model": "fixture", "temperature": 0, "messages": []])
        let lateProbeObservation = TemperatureCapabilityCache.shared.beginObservation(for: sharedRequest)
        _ = try! await perform([(400, rejected), (200, accepted)], endpoint: sharedEndpoint, cache: TemperatureCapabilityCache.shared)
        TemperatureCapabilityCache.shared.record(.supported, for: sharedRequest, observation: lateProbeObservation)
        TestSupport.expect(TemperatureCapabilityCache.shared.capability(for: sharedRequest) == .unsupported, "Shared production cache ignores late successful probe after newer runtime rejection")

        let supportedCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-supported-\(UUID().uuidString)")!)
        let supportedEndpoint = UUID().uuidString
        let validCompletion = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"OK\"}}]}"
        _ = try! await perform([(200, validCompletion)], endpoint: supportedEndpoint, cache: supportedCache)
        let supportedCall = try! await perform([(200, validCompletion)], endpoint: supportedEndpoint, cache: supportedCache)
        let supportedBody = try! JSONSerialization.jsonObject(with: bodyData(supportedCall[0])!) as! [String: Any]
        TestSupport.expect(supportedCall.count == 1 && supportedBody["temperature"] != nil, "Successful supported response preserves temperature on later calls")

        for (status, body, label) in [
            (401, "{\"error\":{\"code\":\"invalid_api_key\",\"message\":\"bad key\"}}", "auth"),
            (429, "{\"error\":{\"code\":\"rate_limit_exceeded\"}}", "rate limit"),
            (400, "{\"error\":{\"code\":\"invalid_request\",\"message\":\"bad request\"}}", "unrelated 400")
        ] {
            let isolated = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-\(label)-\(UUID().uuidString)")!)
            let isolatedEndpoint = UUID().uuidString
            _ = try! await perform([(status, body)], endpoint: isolatedEndpoint, cache: isolated)
            let next = try! await perform([(200, validCompletion)], endpoint: isolatedEndpoint, cache: isolated)
            let nextBody = try! JSONSerialization.jsonObject(with: bodyData(next[0])!) as! [String: Any]
            TestSupport.expect(next.count == 1 && nextBody["temperature"] != nil, "\(label) errors do not poison capability cache")
        }
    }
}
