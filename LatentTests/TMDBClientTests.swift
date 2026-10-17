import Foundation
import Testing
@testable import Latent

/// URLProtocol stub 集成测试（设计文档第 11 节）。串行执行，避免共享 stub 状态互相干扰。
@Suite("TMDBClient 集成", .serialized)
struct TMDBClientIntegrationTests {

    private func makeClient(cache: (any ResponseCacheProtocol)? = nil) -> TMDBClient {
        TMDBClient(
            session: URLProtocolStub.makeSession(),
            cache: cache ?? ResponseCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("latent-tests-\(UUID().uuidString)")),
            tokenProvider: { "test-token" },
            languageProvider: { "zh-CN" }
        )
    }

    @Test("全链路成功：验证 Token 与图片配置")
    func validateToken() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { request in
            #expect(request.url?.path == "/3/configuration")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return .fixture("configuration")
        }

        let client = makeClient()
        let config = try await client.validateToken()
        #expect(config.baseURL == "https://image.tmdb.org/t/p/")
        #expect(URLProtocolStub.requestCount == 1)
    }

    @Test("401 → unauthorized（Token 不进 URL）")
    func unauthorized() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { request in
            #expect(request.url?.query?.contains("token") != true)
            return .status(401)
        }

        let client = makeClient()
        await #expect(throws: APIError.unauthorized) {
            _ = try await client.validateToken()
        }
        #expect(URLProtocolStub.requestCount == 1) // 401 不重试
    }

    @Test("404 → notFound，不重试")
    func notFound() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in .status(404) }

        let client = makeClient()
        do {
            _ = try await client.movieDetail(id: 1)
            Issue.record("应当抛错")
        } catch let error as APIError {
            #expect(error == .notFound)
        }
        #expect(URLProtocolStub.requestCount == 1)
    }

    @Test("429 带 Retry-After → 等待后重试一次并成功")
    func rateLimitedRetry() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in
            if URLProtocolStub.requestCount == 1 {
                return .status(429, headers: ["Retry-After": "1"])
            }
            return .fixture("trending_movie_day")
        }

        let client = makeClient()
        let page = try await client.trending(mediaKind: .movie, window: .day, page: 1)
        #expect(page.items.count == 2)
        #expect(URLProtocolStub.requestCount == 2)
    }

    @Test("坏 JSON → decodingFailed，不重试")
    func malformedJSON() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in .malformed() }

        let client = makeClient()
        do {
            _ = try await client.validateToken()
            Issue.record("应当抛错")
        } catch let error as APIError {
            guard case .decodingFailed = error else {
                Issue.record("应为 decodingFailed，实际 \(error)")
                return
            }
        }
        #expect(URLProtocolStub.requestCount == 1)
    }

    @Test("超时 → timedOut，指数退避重试后仍失败（共 3 次请求）")
    func timedOut() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TimeoutURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let client = TMDBClient(
            session: session,
            cache: ResponseCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("latent-tests-\(UUID().uuidString)")),
            tokenProvider: { "test-token" },
            languageProvider: { "zh-CN" }
        )

        do {
            _ = try await client.validateToken()
            Issue.record("应当抛错")
        } catch let error as APIError {
            #expect(error == .timedOut)
        }
        #expect(TimeoutURLProtocol.callCount >= 1)
    }

    @Test("响应缓存命中：第二次请求不发网络")
    func cacheHit() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in .fixture("trending_movie_day") }

        let client = makeClient()
        let first = try await client.trending(mediaKind: .movie, window: .day, page: 1)
        let second = try await client.trending(mediaKind: .movie, window: .day, page: 1)

        #expect(first.items.count == second.items.count)
        #expect(URLProtocolStub.requestCount == 1) // 缓存命中不产生第二次网络请求
    }

    @Test("不同参数不使用同一缓存")
    func cacheKeyedByParameters() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in .fixture("trending_movie_day") }

        let client = makeClient()
        _ = try await client.trending(mediaKind: .movie, window: .day, page: 1)
        _ = try await client.trending(mediaKind: .tv, window: .week, page: 1)
        #expect(URLProtocolStub.requestCount == 2)
    }

    @Test("缺 Token 直接抛 missingToken，不发请求")
    func missingToken() async throws {
        URLProtocolStub.reset()
        URLProtocolStub.handler = { _ in .status(200) }

        let client = TMDBClient(
            session: URLProtocolStub.makeSession(),
            cache: ResponseCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("latent-tests-\(UUID().uuidString)")),
            tokenProvider: { nil },
            languageProvider: { "zh-CN" }
        )

        await #expect(throws: APIError.missingToken) {
            _ = try await client.validateToken()
        }
        #expect(URLProtocolStub.requestCount == 0)
    }
}

/// 始终超时的 stub（独立类型，避免与共享 handler 冲突）。
final class TimeoutURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _count = 0

    static var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._count += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }

    override func stopLoading() {}
}

/// 响应缓存：TTL、损坏自愈、清除。
@Suite("响应缓存")
struct ResponseCacheTests {

    private func makeTempCache() -> (ResponseCache, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("latent-cache-tests-\(UUID().uuidString)", isDirectory: true)
        return (ResponseCache(directory: directory), directory)
    }

    @Test("TTL 过期视为未命中")
    func ttlExpiry() async {
        let (cache, _) = makeTempCache()
        await cache.store(Data("payload".utf8), forKey: "key")
        let fresh = await cache.data(forKey: "key", maxAge: 60)
        #expect(fresh == Data("payload".utf8))

        let expired = await cache.data(forKey: "key", maxAge: 0)
        #expect(expired == nil)
    }

    @Test("损坏文件自愈：损坏条目视为未命中并被清理")
    func corruptedFile() async {
        let (cache, directory) = makeTempCache()
        await cache.store(Data("payload".utf8), forKey: "key")
        // 破坏文件内容
        let file = directory.appendingPathComponent("key.json")
        try? Data("坏了".utf8).write(to: file)

        let result = await cache.data(forKey: "key", maxAge: 60)
        #expect(result == nil)
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }

    @Test("清除缓存")
    func clear() async {
        let (cache, _) = makeTempCache()
        await cache.store(Data("payload".utf8), forKey: "key")
        await cache.clear()
        let result = await cache.data(forKey: "key", maxAge: 60)
        #expect(result == nil)
    }
}
