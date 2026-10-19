import Foundation
import SwiftData
import SwiftUI

/// 共享依赖容器：客户端、图片管线、设置与两个 Store。
///
/// 由 `LatentApp` 构造一次并注入环境；Store 依赖主上下文（@MainActor）。
@MainActor
@Observable
final class AppEnvironment {
    let settings: AppSettings
    let client: any TMDBClientProtocol
    let imagePipeline: ImagePipeline
    let library: LibraryStore
    let history: HistoryStore
    let apiCache: ResponseCache
    let modelContainer: ModelContainer

    /// TMDB 连接状态（侧边栏底部状态点）。
    var connectionState: ConnectionState = .unknown

    enum ConnectionState: Sendable, Equatable {
        case unknown
        case connected
        case failed(String)
    }

    init(container: ModelContainer, client: (any TMDBClientProtocol)? = nil) {
        self.modelContainer = container
        let settings = AppSettings()
        self.settings = settings
        self.apiCache = ResponseCache()
        // 全应用共用同一实例：设置页「清除图片缓存」清的就是视图实际使用的内存/磁盘缓存。
        self.imagePipeline = .shared

        if let client {
            self.client = client
        } else {
            // 语言从非隔离镜像读取（actor 安全）；写入只发生在主 actor
            let settings = self.settings
            self.client = TMDBClient(languageProvider: { @Sendable in settings.languageCode })
        }

        self.library = LibraryStore(container: container)
        self.history = HistoryStore(container: container)
    }

    /// 启动 / 设置页保存后的连接验证（GET /3/configuration）。
    func checkConnection() async {
        do {
            _ = try await client.validateToken()
            connectionState = .connected
        } catch let error as APIError {
            connectionState = .failed(error.errorDescription)
        } catch {
            connectionState = .failed(APIError.offline.errorDescription)
        }
    }

    /// 把作品写入浏览历史（详情页打开时调用）。
    func recordView(_ summary: MediaSummary) {
        history.record(summary)
    }
}
