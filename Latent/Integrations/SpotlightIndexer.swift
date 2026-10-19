import AppIntents
import CoreSpotlight
import Foundation

/// 收藏 / 观看清单 → Spotlight（设计文档第 8.9 节）。
///
/// macOS 27 实测：`CSSearchableItem` 写入的条目不出现在 Spotlight；
/// 使用 `IndexedEntity` + `indexAppEntities` 才能被系统检索，并在点击时
/// 匹配 `OpenTitleIntent`。索引失败不影响应用主流程。
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    nonisolated static let indexName = "app.latent.library"

    // CSSearchableIndex 的异步方法在 SDK 中未标注 Sendable；实例本身线程安全，且本类限定 MainActor。
    nonisolated(unsafe) private let index = CSSearchableIndex(name: indexName)
    private var lastSignature: String?

    /// 重建索引；数据未变化时直接返回。
    func reindex(favorites: [LibrarySnapshot], watchlist: [LibrarySnapshot]) async {
        let buckets = TitleEntity.buckets(favorites: favorites, watchlist: watchlist)
        let signature = (buckets.favorites + buckets.watchlist)
            .map { "\($0.id)|\($0.title)|\($0.originalTitle ?? "")|\($0.year ?? 0)|\($0.voteAverage ?? 0)|\($0.posterPath ?? "")" }
            .joined(separator: ";")
        guard signature != lastSignature else { return }

        do {
            try await index.deleteAppEntities(ofType: TitleEntity.self)
            if !buckets.favorites.isEmpty {
                try await index.indexAppEntities(buckets.favorites, priority: 10)
            }
            if !buckets.watchlist.isEmpty {
                try await index.indexAppEntities(buckets.watchlist, priority: 0)
            }
            lastSignature = signature
            Log.spotlight.debug("Spotlight 索引已更新：\(buckets.favorites.count) 收藏 / \(buckets.watchlist.count) 清单")
        } catch {
            Log.spotlight.error("Spotlight 索引失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
