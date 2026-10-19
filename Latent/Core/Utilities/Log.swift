import Foundation
import os

/// 全应用统一日志（os.Logger），Token 等敏感信息一律不写日志。
enum Log {
    private static let subsystem = "app.latent.Latent"

    /// 网络：请求、重试、错误分类。
    static let network = Logger(subsystem: subsystem, category: "network")
    /// 图片管线。
    static let images = Logger(subsystem: subsystem, category: "images")
    /// 持久化：SwiftData 容器、迁移、重建。
    static let store = Logger(subsystem: subsystem, category: "store")
    /// UI 层异常（缓存清除、外观等）。
    static let ui = Logger(subsystem: subsystem, category: "ui")
    /// 导出（JSON / Markdown）。
    static let export = Logger(subsystem: subsystem, category: "export")
    /// App Intents / Shortcuts / 路由。
    static let intents = Logger(subsystem: subsystem, category: "intents")
    /// Spotlight 索引。
    static let spotlight = Logger(subsystem: subsystem, category: "spotlight")
}
