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
    let exports = ExportCenter()
    /// 追更提醒调度（v1.25）：真实实现走 `UNUserNotificationCenter`，单测可换假实现。
    let reminders: any EpisodeReminderScheduling
    /// 上映日提醒调度（v1.34 上映日历）。
    let releaseReminders: any ReleaseReminderScheduling

    /// TMDB 连接状态（侧边栏底部状态点）。
    var connectionState: ConnectionState = .unknown

    @ObservationIgnored private var spotlightTask: Task<Void, Never>?
    @ObservationIgnored private var backfillTask: Task<Void, Never>?

    enum ConnectionState: Sendable, Equatable {
        case unknown
        case connected
        case failed(String)
    }

    init(
        container: ModelContainer,
        client: (any TMDBClientProtocol)? = nil,
        reminders: (any EpisodeReminderScheduling)? = nil,
        releaseReminders: (any ReleaseReminderScheduling)? = nil
    ) {
        self.modelContainer = container
        self.reminders = reminders ?? LiveEpisodeReminderScheduler.shared
        self.releaseReminders = releaseReminders ?? LiveReleaseReminderScheduler.shared
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

        library.onChange = { [weak self] in
            self?.refreshSpotlightIndex()
        }
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

    /// 准备导出（设计文档第 8.9 节）。范围由调用方决定，数据来自本地 Store。
    func export(_ scope: ExportScope, as format: ExportFormat) {
        exports.prepare(
            scope: scope,
            format: format,
            favorites: library.favoriteItems,
            watchlist: library.watchlistItems,
            history: history.items,
            language: settings.language
        )
    }

    /// 后台补齐片库条目缺失的详情字段（v1.9）。
    ///
    /// 只在应用运行时进行（沙盒没有后台定时执行能力）；一次最多处理 40 条，
    /// 断网或 Token 未配置时立即停止，下次启动继续，不会把条目误标为已富化。
    func enrichLibraryInBackground(limit: Int = 40) {
        guard backfillTask == nil, library.pendingEnrichmentCount > 0 else { return }
        let client = self.client
        backfillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.library.backfillDetails(limit: limit) { kind, id in
                do {
                    switch kind {
                    case .movie:
                        let detail = try await client.movieDetail(id: id)
                        return .found(LibraryDetails(movie: detail))
                    case .tv:
                        let detail = try await client.tvDetail(id: id)
                        return .found(LibraryDetails(tv: detail))
                    default:
                        return .gone
                    }
                } catch let error as APIError {
                    if case .notFound = error { return .gone }
                    return .failed
                } catch {
                    return .failed
                }
            }
            self.backfillTask = nil
        }
    }

    /// 重建 Spotlight 索引。`immediately` 用于启动；库变更时做 350ms 防抖。
    func refreshSpotlightIndex(immediately: Bool = false) {
        spotlightTask?.cancel()
        let favorites = library.favoriteItems
        let watchlist = library.watchlistItems
        spotlightTask = Task { @MainActor in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await SpotlightIndexer.shared.reindex(favorites: favorites, watchlist: watchlist)
        }
    }
}
