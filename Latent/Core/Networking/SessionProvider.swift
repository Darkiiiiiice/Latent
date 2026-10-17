import Foundation

/// 会话提供者：按当前代理配置构造 `URLSession`，并按「配置签名」缓存。
///
/// 网络层每次请求都经此取会话，因此设置页改完代理后 **下一次请求即生效**，
/// 无需重启或重建 `TMDBClient` / `ImagePipeline`。
final class SessionProvider: @unchecked Sendable {
    typealias SessionFactory = @Sendable (URLSessionConfiguration) -> URLSession

    private let lock = NSLock()
    private let proxyProvider: @Sendable () -> ProxyConfiguration
    private let makeConfiguration: @Sendable (ProxyConfiguration) -> URLSessionConfiguration
    private let makeSession: SessionFactory

    private var cached: (signature: String, session: URLSession)?

    init(
        proxy: @escaping @Sendable () -> ProxyConfiguration = { ProxyConfiguration.current },
        configuration: @escaping @Sendable (ProxyConfiguration) -> URLSessionConfiguration,
        session: @escaping SessionFactory = { URLSession(configuration: $0) }
    ) {
        self.proxyProvider = proxy
        self.makeConfiguration = configuration
        self.makeSession = session
    }

    /// 固定会话（测试注入 / 自定义）——代理变化不影响它。
    init(fixed session: URLSession) {
        self.proxyProvider = { ProxyConfiguration() }
        self.makeConfiguration = { _ in session.configuration }
        self.makeSession = { _ in session }
    }

    func session() -> URLSession {
        let configuration = proxyProvider()
        let signature = configuration.signature

        lock.lock()
        defer { lock.unlock() }

        if let cached, cached.signature == signature {
            return cached.session
        }
        // 代理变化：旧会话收尾后释放（在途请求自然结束，不主动取消）
        cached?.session.finishTasksAndInvalidate()
        let created = makeSession(makeConfiguration(configuration))
        cached = (signature, created)
        return created
    }
}
