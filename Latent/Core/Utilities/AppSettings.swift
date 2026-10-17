import Foundation
import SwiftUI

/// 应用设置（UserDefaults / 设计文档第 6 节）。
///
/// - 语言：TMDB 元数据语言（默认 zh-CN）。
/// - 外观：跟随系统 / 浅色 / 深色。
/// - 最近搜索：最多 10 条。
@MainActor
@Observable
final class AppSettings {
    struct Keys {
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let maxImageCacheMB = "settings.maxImageCacheMB"
        static let recentSearches = "settings.recentSearches"
    }

    static let availableLanguages = ["zh-CN", "en-US"]
    static let recentSearchesLimit = 10

    private let defaults: UserDefaults

    /// 线程安全的语言镜像：TMDBClient（actor）在任意隔离域安全读取；写入始终在主 actor。
    private final class LanguageStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value = "zh-CN"

        func read() -> String {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func write(_ newValue: String) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private let languageStorage = LanguageStorage()

    var language: String {
        didSet {
            languageStorage.write(language)
            defaults.set(language, forKey: Keys.language)
        }
    }

    /// 非隔离读取（供网络层构造 language 参数）。
    nonisolated var languageCode: String { languageStorage.read() }

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }

    /// 网络代理（设计文档第 4 节）：改动即写入 UserDefaults，网络层按签名重建会话。
    var proxy: ProxyConfiguration { didSet { proxy.save(to: defaults) } }

    private(set) var recentSearches: [String]

    init(defaults: UserDefaults = .standard, environment: [String: String]? = nil) {
        self.defaults = defaults
        let storedLanguage = defaults.string(forKey: Keys.language) ?? "zh-CN"
        let resolved = AppSettings.availableLanguages.contains(storedLanguage) ? storedLanguage : "zh-CN"
        self.language = resolved
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        // 代理：已存过就用存的；从未设置过才尝试从环境变量预填（终端 / Xcode 启动时）。
        if let storedProxy = ProxyConfiguration.readIfPresent(from: defaults) {
            self.proxy = storedProxy
        } else if let detected = ProxyConfiguration.detectFromEnvironment(environment ?? ProcessInfo.processInfo.environment) {
            self.proxy = detected
            detected.save(to: defaults)
        } else {
            self.proxy = ProxyConfiguration()
        }
        self.recentSearches = defaults.stringArray(forKey: Keys.recentSearches) ?? []
        self.languageStorage.write(resolved)
    }

    // MARK: - 外观

    enum AppearanceMode: String, CaseIterable, Sendable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // MARK: - 最近搜索

    func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > Self.recentSearchesLimit {
            list = Array(list.prefix(Self.recentSearchesLimit))
        }
        recentSearches = list
        defaults.set(list, forKey: Keys.recentSearches)
    }

    func clearRecentSearches() {
        recentSearches = []
        defaults.removeObject(forKey: Keys.recentSearches)
    }
}
