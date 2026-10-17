import Foundation

/// URLProtocol stub：用 fixture 或自定义响应驱动 TMDBClient（集成测试）。
///
/// 通过 `URLSessionConfiguration.ephemeral` + `protocolClasses` 注入，不改动生产代码签名。
final class URLProtocolStub: URLProtocol {
    struct Response {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var body: Data
    }

    /// 按请求路径返回响应；nil → 404。
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response?)?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static func reset() {
        lock.lock()
        _requestCount = 0
        lock.unlock()
        handler = nil
    }

    static func bumpCount() {
        lock.lock()
        _requestCount += 1
        lock.unlock()
    }

    /// 构造注入 stub 的会话。
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.bumpCount()
        guard let response = Self.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLProtocolStub.Response {
    /// 按 fixture 内容构造 200 响应。
    static func fixture(_ name: String) -> URLProtocolStub.Response {
        URLProtocolStub.Response(body: Fixtures.data(name))
    }

    static func status(_ code: Int, headers: [String: String] = [:]) -> URLProtocolStub.Response {
        URLProtocolStub.Response(statusCode: code, headers: headers, body: Data())
    }

    static func json(_ text: String) -> URLProtocolStub.Response {
        URLProtocolStub.Response(body: Data(text.utf8))
    }

    static func malformed() -> URLProtocolStub.Response {
        URLProtocolStub.Response(body: Data("这不是 JSON".utf8))
    }
}
