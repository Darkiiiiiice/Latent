import Foundation
import SwiftData
import OSLog

/// 收藏与观看清单（SwiftData 本地持久化）。
///
/// 去重键 = `(mediaType, tmdbID)`；同键重复写入只保留一条（设计文档第 6 节）。
///
/// 注意：Store 必须持有 `ModelContainer`。`ModelContext` 不会让容器存活，
/// 容器一旦释放，后续 fetch 会在 SwiftData 内部直接 trap（SIGTRAP，无日志）。
@MainActor
@Observable
final class LibraryStore {
    private let container: ModelContainer
    private let context: ModelContext

    private(set) var favoriteItems: [LibrarySnapshot] = []
    private(set) var watchlistItems: [LibrarySnapshot] = []

    private var favoriteIDs: Set<String>
    private var watchlistIDs: Set<String>

    init(container: ModelContainer) {
        self.container = container
        let context = container.mainContext
        self.context = context
        let favorites = Self.loadSnapshots(from: context, type: FavoriteItem.self)
        let watchlist = Self.loadSnapshots(from: context, type: WatchlistItem.self)
        self.favoriteItems = favorites
        self.watchlistItems = watchlist
        self.favoriteIDs = Set(favorites.map(\.id))
        self.watchlistIDs = Set(watchlist.map(\.id))
    }

    // MARK: - 收藏

    func isFavorite(_ summary: MediaSummary) -> Bool {
        favoriteIDs.contains(Self.key(for: summary))
    }

    @discardableResult
    func toggleFavorite(_ summary: MediaSummary) -> Bool {
        if favoriteIDs.contains(Self.key(for: summary)) {
            _ = removeFavorite(summary)
            return false
        }
        LibraryStoreWriter.upsertFavorite(summary, into: context)
        saveAndReload()
        return true
    }

    /// 移除成功返回 true；未收藏返回 nil。
    @discardableResult
    func removeFavorite(_ summary: MediaSummary) -> Bool? {
        guard favoriteIDs.contains(Self.key(for: summary)) else { return nil }
        let kind = summary.mediaKind.rawValue
        let id = summary.id
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id }
        )
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
        saveAndReload()
        return true
    }

    // MARK: - 观看清单

    func isInWatchlist(_ summary: MediaSummary) -> Bool {
        watchlistIDs.contains(Self.key(for: summary))
    }

    @discardableResult
    func toggleWatchlist(_ summary: MediaSummary) -> Bool {
        if watchlistIDs.contains(Self.key(for: summary)) {
            _ = removeFromWatchlist(summary)
            return false
        }
        LibraryStoreWriter.upsertWatchlist(summary, into: context)
        saveAndReload()
        return true
    }

    @discardableResult
    func removeFromWatchlist(_ summary: MediaSummary) -> Bool? {
        guard watchlistIDs.contains(Self.key(for: summary)) else { return nil }
        let kind = summary.mediaKind.rawValue
        let id = summary.id
        let descriptor = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id }
        )
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
        saveAndReload()
        return true
    }

    /// 把观看清单条目移入收藏并移出清单（右键菜单用）。
    func moveToFavorites(_ summary: MediaSummary) {
        removeFromWatchlist(summary)
        LibraryStoreWriter.upsertFavorite(summary, into: context)
        saveAndReload()
    }

    // MARK: - 排序

    func items(kind: LibraryKind, sortedBy sort: SortOption) -> [LibrarySnapshot] {
        let source = kind == .favorites ? favoriteItems : watchlistItems
        switch sort {
        case .addedAt:
            return source.sorted { $0.addedAt > $1.addedAt }
        case .rating:
            return source.sorted { ($0.voteAverage ?? 0, $0.addedAt) > ($1.voteAverage ?? 0, $1.addedAt) }
        case .year:
            return source.sorted { ($0.year ?? 0, $0.addedAt) > ($1.year ?? 0, $1.addedAt) }
        }
    }

    var favoriteCount: Int { favoriteItems.count }
    var watchlistCount: Int { watchlistItems.count }

    /// 语言切换或详情回访后，用最新数据刷新库内展示字段。
    func refresh(_ summary: MediaSummary) {
        let key = Self.key(for: summary)
        if favoriteIDs.contains(key) {
            LibraryStoreWriter.upsertFavorite(summary, into: context)
        }
        if watchlistIDs.contains(key) {
            LibraryStoreWriter.upsertWatchlist(summary, into: context)
        }
        saveAndReload()
    }

    // MARK: - 内部

    private func saveAndReload() {
        do {
            try context.save()
        } catch {
            Log.store.error("保存失败：\(error.localizedDescription, privacy: .public)")
        }
        favoriteItems = Self.loadSnapshots(from: context, type: FavoriteItem.self)
        watchlistItems = Self.loadSnapshots(from: context, type: WatchlistItem.self)
        favoriteIDs = Set(favoriteItems.map(\.id))
        watchlistIDs = Set(watchlistItems.map(\.id))
    }

    private static func loadSnapshots<T: PersistentModel & LibraryRecord>(
        from context: ModelContext,
        type: T.Type
    ) -> [LibrarySnapshot] {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).map(\.snapshot)
    }

    private static func key(for summary: MediaSummary) -> String {
        "\(summary.mediaKind.rawValue)-\(summary.id)"
    }
}

/// 库类型（收藏 / 观看清单）。
enum LibraryKind: Sendable {
    case favorites
    case watchlist

    var title: String {
        switch self {
        case .favorites: return "收藏"
        case .watchlist: return "观看清单"
        }
    }
}
