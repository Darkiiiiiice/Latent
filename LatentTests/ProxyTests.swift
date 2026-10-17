import Foundation
import Testing
@testable import Latent

/// 代理配置（设计文档第 4 节「网络代理」）。
@Suite("代理配置")
struct ProxyConfigurationTests {

    @Test("跟随系统：不注入代理字典（用系统网络设置）")
    func systemMode() {
        let configuration = ProxyConfiguration(mode: .system, host: "127.0.0.1", port: 7890)
        #expect(configuration.connectionProxyDictionary == nil)
        #expect(configuration.signature == "system")
    }

    @Test("手动 HTTP(S)：写入 HTTP 与 HTTPS 两组键")
    func manualHTTP() throws {
        let configuration = ProxyConfiguration(mode: .manual, kind: .http, host: " 127.0.0.1 ", port: 7890)
        let dictionary = try #require(configuration.connectionProxyDictionary)

        #expect(dictionary["HTTPEnable"] as? Int == 1)
        #expect(dictionary["HTTPProxy"] as? String == "127.0.0.1") // 两端空白已裁剪
        #expect(dictionary["HTTPPort"] as? Int == 7890)
        #expect(dictionary["HTTPSEnable"] as? Int == 1)
        #expect(dictionary["HTTPSProxy"] as? String == "127.0.0.1")
        #expect(dictionary["HTTPSPort"] as? Int == 7890)
    }

    @Test("手动 SOCKS5：只写 SOCKS 键")
    func manualSOCKS() throws {
        let configuration = ProxyConfiguration(mode: .manual, kind: .socks5, host: "127.0.0.1", port: 7890)
        let dictionary = try #require(configuration.connectionProxyDictionary)

        #expect(dictionary["SOCKSEnable"] as? Int == 1)
        #expect(dictionary["SOCKSProxy"] as? String == "127.0.0.1")
        #expect(dictionary["SOCKSPort"] as? Int == 7890)
        #expect(dictionary["HTTPEnable"] == nil)
    }

    @Test("手动模式但主机为空 / 端口非法：不给字典（回退跟随系统）")
    func unusableManualFallsBack() {
        #expect(ProxyConfiguration(mode: .manual, host: "   ", port: 7890).connectionProxyDictionary == nil)
        #expect(ProxyConfiguration(mode: .manual, host: "127.0.0.1", port: 0).connectionProxyDictionary == nil)
        #expect(ProxyConfiguration(mode: .manual, host: "127.0.0.1", port: 70000).connectionProxyDictionary == nil)
        #expect(ProxyConfiguration(mode: .manual, host: "127.0.0.1", port: 7890).isUsable)
    }

    @Test("签名：只随影响连接的字段变化（主机大小写与空白归一）")
    func signature() {
        let base = ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 7890)
        let spaced = ProxyConfiguration(mode: .manual, kind: .http, host: " 127.0.0.1 ", port: 7890)
        let upper = ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 7890)

        #expect(base.signature == spaced.signature)
        #expect(base.signature == upper.signature)

        let changedPort = ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 1080)
        let changedKind = ProxyConfiguration(mode: .manual, kind: .socks5, host: "127.0.0.1", port: 7890)
        let changedHost = ProxyConfiguration(mode: .manual, kind: .http, host: "10.0.0.2", port: 7890)

        #expect(base.signature != changedPort.signature)
        #expect(base.signature != changedKind.signature)
        #expect(base.signature != changedHost.signature)
    }

    @Test("读写往返：UserDefaults 持久化")
    func roundTrip() {
        let defaults = UserDefaults(suiteName: "latent-proxy-tests-\(UUID().uuidString)")!
        #expect(ProxyConfiguration.read(from: defaults) == ProxyConfiguration()) // 默认跟随系统

        let configuration = ProxyConfiguration(mode: .manual, kind: .socks5, host: "10.0.0.5", port: 1080)
        configuration.save(to: defaults)
        #expect(ProxyConfiguration.read(from: defaults) == configuration)
    }

    @Test("环境变量探测：https_proxy / all_proxy / 裸 host:port")
    func detectFromEnvironment() {
        let http = ProxyConfiguration.detectFromEnvironment(["https_proxy": "http://127.0.0.1:7890"])
        #expect(http == ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 7890))

        // 优先 https_proxy；大小写变体也认
        let preferred = ProxyConfiguration.detectFromEnvironment([
            "HTTP_PROXY": "http://10.0.0.9:8888",
            "https_proxy": "http://127.0.0.1:7777",
        ])
        #expect(preferred?.port == 7777)

        let socks = ProxyConfiguration.detectFromEnvironment(["all_proxy": "socks5://127.0.0.1:1080"])
        #expect(socks?.kind == .socks5)
        #expect(socks?.port == 1080)

        // 无协议前缀按 http 处理
        let bare = ProxyConfiguration.detectFromEnvironment(["http_proxy": "127.0.0.1:8888"])
        #expect(bare?.kind == .http)
        #expect(bare?.port == 8888)

        #expect(ProxyConfiguration.detectFromEnvironment([:]) == nil)
        #expect(ProxyConfiguration.detectFromEnvironment(["https_proxy": "   "]) == nil)
        #expect(ProxyConfiguration.detectFromEnvironment(["https_proxy": "http://:7890"]) == nil) // 无主机
    }
}

/// 会话提供者：代理变化后自动重建会话（改动即时生效）。
@Suite("会话提供者")
struct SessionProviderTests {

    /// 可在任意隔离域读写的代理配置盒。
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ProxyConfiguration

        init(_ value: ProxyConfiguration) { self.value = value }

        func set(_ newValue: ProxyConfiguration) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        var current: ProxyConfiguration {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func makeProvider(_ box: Box) -> SessionProvider {
        SessionProvider(
            proxy: { box.current },
            configuration: { proxy in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
                return configuration
            }
        )
    }

    @Test("同一签名复用同一会话；签名变化即重建")
    func rebuildOnChange() {
        let box = Box(ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 7890))
        let provider = makeProvider(box)

        let first = provider.session()
        #expect(provider.session() === first) // 签名不变 → 复用

        box.set(ProxyConfiguration(mode: .manual, kind: .http, host: "127.0.0.1", port: 1080))
        let second = provider.session()
        #expect(second !== first) // 端口变化 → 新会话
        #expect(second.configuration.connectionProxyDictionary?["HTTPPort"] as? Int == 1080)

        // 用同类配置再次取值：仍复用 second（不因已重建过而反复重建）
        box.set(box.current)
        #expect(provider.session() === second)
    }

    @Test("固定会话：始终返回注入的实例，不受代理影响")
    func fixedSession() {
        let session = URLProtocolStub.makeSession()
        let provider = SessionProvider(fixed: session)
        #expect(provider.session() === session)
        #expect(provider.session() === session)
    }
}
