import Foundation
import CFNetwork

/// 网络代理配置（设计文档第 4 节「网络代理」）。
///
/// 背景：国内直连 `api.themoviedb.org` 会被拦，而 `export https_proxy=…` 只对 shell 生效，
/// 从 Finder / 双击启动的 App 读不到，因此需要应用内设置。
///
/// - `跟随系统`：不动 `connectionProxyDictionary`（用系统网络设置里的代理）。
/// - `手动`：HTTP(S) 或 SOCKS5 + 主机 + 端口。
/// - 存 UserDefaults（非敏感，不含凭据）；v1 不支持代理认证与 PAC。
struct ProxyConfiguration: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable, Identifiable {
        case system
        case manual

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "跟随系统"
            case .manual: return "手动"
            }
        }
    }

    enum Kind: String, CaseIterable, Sendable, Identifiable {
        case http
        case socks5

        var id: String { rawValue }

        var label: String {
            switch self {
            case .http: return "HTTP(S)"
            case .socks5: return "SOCKS5"
            }
        }
    }

    var mode: Mode = .system
    var kind: Kind = .http
    var host: String = "127.0.0.1"
    var port: Int = 7890

    /// 参与会话重建判断的签名（只含影响连接方式的字段）。
    var signature: String {
        guard mode == .manual else { return Mode.system.rawValue }
        return "\(mode.rawValue)|\(kind.rawValue)|\(host.trimmingCharacters(in: .whitespaces).lowercased())|\(port)"
    }

    var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 手动模式下的配置是否可用（主机非空、端口合法）。
    var isUsable: Bool {
        mode == .manual && !trimmedHost.isEmpty && (1...65535).contains(port)
    }

    /// `URLSessionConfiguration.connectionProxyDictionary`；nil = 跟随系统。
    var connectionProxyDictionary: [AnyHashable: Any]? {
        guard isUsable else { return nil }
        let host = trimmedHost
        switch kind {
        case .http:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        case .socks5:
            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port,
            ]
        }
    }

    /// 说明文案（设置页）。
    var summary: String {
        switch mode {
        case .system: return "使用系统网络设置里的代理；未配置代理时直连。"
        case .manual:
            guard isUsable else { return "请填写主机与 1–65535 的端口。" }
            return "\(kind.label) · \(trimmedHost):\(port)"
        }
    }
}

// MARK: - 持久化（UserDefaults；网络层任意上下文可直接读取）

extension ProxyConfiguration {
    enum Keys {
        static let mode = "settings.proxy.mode"
        static let kind = "settings.proxy.kind"
        static let host = "settings.proxy.host"
        static let port = "settings.proxy.port"
    }

    /// 当前配置（线程安全；网络层按此构造会话）。
    static var current: ProxyConfiguration {
        read(from: .standard)
    }

    static func read(from defaults: UserDefaults) -> ProxyConfiguration {
        let mode = Mode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .system
        let kind = Kind(rawValue: defaults.string(forKey: Keys.kind) ?? "") ?? .http
        let host = defaults.string(forKey: Keys.host) ?? "127.0.0.1"
        let port = defaults.object(forKey: Keys.port) as? Int ?? 7890
        return ProxyConfiguration(mode: mode, kind: kind, host: host, port: port)
    }

    /// 读取已保存配置；nil = 从未设置过（用于首次启动的预填判断）。
    static func readIfPresent(from defaults: UserDefaults) -> ProxyConfiguration? {
        guard defaults.string(forKey: Keys.mode) != nil else { return nil }
        return read(from: defaults)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(kind.rawValue, forKey: Keys.kind)
        defaults.set(host, forKey: Keys.host)
        defaults.set(port, forKey: Keys.port)
    }

    /// 从环境变量探测代理（`https_proxy` / `http_proxy` / `all_proxy`，形如 `http://127.0.0.1:7890`）。
    ///
    /// 只在「从未设置过代理」时用于预填：从终端 / Xcode 启动时能读到这些变量，从 Finder 双击启动读不到。
    /// 仅是省一次手填，不做隐式网络行为；不写日志。
    static func detectFromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ProxyConfiguration? {
        for key in ["https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY", "all_proxy", "ALL_PROXY"] {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let parsed = parseEnvironmentValue(raw) { return parsed }
        }
        return nil
    }

    private static func parseEnvironmentValue(_ raw: String) -> ProxyConfiguration? {
        let candidate = raw.contains("://") ? raw : "http://\(raw)"
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { return nil }
        let kind: Kind = url.scheme?.lowercased().hasPrefix("socks") == true ? .socks5 : .http
        let port = url.port ?? (kind == .socks5 ? 1080 : 7890)
        guard (1...65535).contains(port) else { return nil }
        return ProxyConfiguration(mode: .manual, kind: kind, host: host, port: port)
    }
}
