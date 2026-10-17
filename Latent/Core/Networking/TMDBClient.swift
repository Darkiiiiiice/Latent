import Foundation

/// 请求节流：单 actor 串行，最小请求间隔 ~100ms（设计文档第 4 节）。
enum RequestThrottle {
    static let minimumInterval: TimeInterval = 0.1

    /// 若距上次请求不足最小间隔，则睡满差额；返回本次请求时间（调用方存回）。
    static func waitIfNeeded(lastRequestAt: Date?) async throws -> Date {
        let now = Date()
        if let last = lastRequestAt {
            let elapsed = now.timeIntervalSince(last)
            let remaining = minimumInterval - elapsed
            if remaining > 0 {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        return Date()
    }
}

/// 重试策略：429 读 Retry-After 等待一次；超时 / 5xx 指数退避最多 2 次（设计文档第 4 节）。
enum RetryPolicy {
    static let maxAttempts = 3 // 首次 + 2 次重试

    /// 返回下一次尝试前需要等待的秒数；nil 表示不再重试。
    static func delayAfter(error: APIError, retryAfterHeader: Int?, attempt: Int) -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }
        switch error {
        case .rateLimited:
            // 仅重试一次 429（设计文档：等待后重试一次）
            guard attempt == 1 else { return nil }
            return Double(retryAfterHeader ?? 2)
        case .timedOut, .offline:
            return exponentialBackoff(attempt: attempt)
        case .serverError(let status) where status >= 500:
            return exponentialBackoff(attempt: attempt)
        default:
            return nil
        }
    }

    private static func exponentialBackoff(attempt: Int) -> TimeInterval {
        // 0.5s、1s …… 加 0~200ms 抖动
        let base = 0.5 * pow(2.0, Double(attempt - 1))
        return base + Double.random(in: 0...0.2)
    }
}

/// TMDB 客户端（actor）：认证、节流、重试、响应缓存、错误分类。
///
/// - 认证：v4 Read Access Token（Bearer 头），Token 不进 URL、不进日志。
/// - 缓存：GET 请求命中未过期缓存即返回，不产生网络请求。
actor TMDBClient: TMDBClientProtocol {
    private let sessions: SessionProvider
    private let cache: any ResponseCacheProtocol
    private let tokenProvider: @Sendable () async -> String?
    private let languageProvider: @Sendable () async -> String

    private var lastRequestAt: Date?

    /// 最近一次实际发生的请求统计（侧边栏状态点呼吸用）。
    private(set) var lastRequestFinishedAt: Date?
    private(set) var isRequestInFlight = false

    init(
        session: URLSession? = nil,
        sessions: SessionProvider? = nil,
        cache: (any ResponseCacheProtocol)? = nil,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        languageProvider: (@Sendable () async -> String)? = nil
    ) {
        if let sessions {
            self.sessions = sessions
        } else if let session {
            self.sessions = SessionProvider(fixed: session)
        } else {
            self.sessions = SessionProvider(configuration: Self.makeConfiguration)
        }
        self.cache = cache ?? ResponseCache()
        self.tokenProvider = tokenProvider ?? {
            (try? await KeychainStore.shared.readToken()) ?? nil
        }
        self.languageProvider = languageProvider ?? { "zh-CN" }
    }

    /// 基础会话配置（代理由 `SessionProvider` 按当前设置注入）。
    nonisolated static func makeConfiguration(proxy: ProxyConfiguration) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        return configuration
    }

    // MARK: - 上层接口

    func validateToken() async throws -> APIConfiguration {
        try await fetch(.configuration)
    }

    func trending(mediaKind: MediaKind, window: Endpoint.TrendingWindow, page: Int) async throws -> Paged<MediaSummary> {
        try await fetch(.trending(mediaKind: mediaKind, window: window))
    }

    func searchMulti(query: String, page: Int) async throws -> Paged<SearchResult> {
        try await fetch(.searchMulti(query: query, page: page))
    }

    func movieDetail(id: Int) async throws -> MovieDetail {
        try await fetch(.movieDetail(id: id))
    }

    func tvDetail(id: Int) async throws -> TVShowDetail {
        try await fetch(.tvDetail(id: id))
    }

    func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetail {
        try await fetch(.tvSeason(id: id, seasonNumber: seasonNumber))
    }

    func personDetail(id: Int) async throws -> PersonDetail {
        try await fetch(.personDetail(id: id))
    }

    func discover(mediaKind: MediaKind, query: DiscoverQuery, page: Int) async throws -> Paged<MediaSummary> {
        try await fetch(.discover(mediaKind: mediaKind, query: query, page: page))
    }

    func genreList(mediaKind: MediaKind) async throws -> [Genre] {
        let response: GenreListResponse = try await fetch(.genreList(mediaKind: mediaKind))
        return response.genres
    }

    // MARK: - 请求管线

    private func fetch<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let language = await languageProvider()
        let token = await tokenProvider()
        guard let token, !token.isEmpty else { throw APIError.missingToken }

        let url = EndpointURLBuilder.url(for: endpoint, language: language)
        let key = CacheKey.responseKey(for: url)

        // 响应缓存命中 → 不产生网络请求
        if let cached = await cache.data(forKey: key, maxAge: endpoint.cacheMaxAge) {
            do {
                return try JSONDecoder().decode(T.self, from: cached)
            } catch {
                Log.network.warning("缓存解码失败，改为重新请求：\(endpoint.path, privacy: .public)")
            }
        }

        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                lastRequestAt = try await RequestThrottle.waitIfNeeded(lastRequestAt: lastRequestAt)
                isRequestInFlight = true
                let (data, response) = try await sessions.session().data(for: request)
                isRequestInFlight = false
                lastRequestFinishedAt = Date()

                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                let retryAfter = Self.retryAfter(from: http)
                guard status == 200 else {
                    throw PendingRetry(error: Self.classify(status: status, retryAfter: retryAfter), retryAfter: retryAfter)
                }

                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    await cache.store(data, forKey: key)
                    return decoded
                } catch {
                    Log.network.error("解码失败 \(endpoint.path, privacy: .public)：\(String(describing: error), privacy: .public)")
                    throw APIError.decodingFailed(String(describing: error))
                }
            } catch let pending as PendingRetry {
                if let delay = RetryPolicy.delayAfter(error: pending.error, retryAfterHeader: pending.retryAfter, attempt: attempt) {
                    Log.network.info("第 \(attempt) 次请求失败（\(endpoint.path, privacy: .public)），\(delay) 秒后重试")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                    continue
                }
                throw pending.error
            } catch let error as APIError {
                if let delay = RetryPolicy.delayAfter(error: error, retryAfterHeader: nil, attempt: attempt) {
                    Log.network.info("第 \(attempt) 次请求失败（\(endpoint.path, privacy: .public)），\(delay) 秒后重试")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attempt += 1
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIError(transportError: error)
            }
        }
    }

    /// 携带 Retry-After 的内部错误包装（仅在 fetch 内使用）。
    private struct PendingRetry: Error {
        let error: APIError
        let retryAfter: Int?
    }

    /// HTTP 状态码 → APIError 分类。
    private static func classify(status: Int, retryAfter: Int?) -> APIError {
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited(retryAfter: retryAfter)
        default: return .serverError(status: status)
        }
    }

    private static func retryAfter(from response: HTTPURLResponse?) -> Int? {
        guard let raw = response?.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }
}
