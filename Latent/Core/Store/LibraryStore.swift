import Foundation
import SwiftData
import OSLog

/// 一次批量移出 / 移动的可撤销记录（v1.7）。
///
/// `snapshots` 是操作前的源清单快照，撤销时按原 `addedAt` 放回；
/// `destinationIDsAdded` 只记录本次真正新增到目标清单的条目——撤销时只移除这些，
/// 移动前已在目标清单的条目保持不动。
struct LibraryBatchChange: Identifiable, Sendable, Equatable {
    let id: UUID
    let source: LibraryKind
    let destination: LibraryKind?
    let snapshots: [LibrarySnapshot]
    let destinationIDsAdded: Set<String>

    init(
        id: UUID = UUID(),
        source: LibraryKind,
        destination: LibraryKind?,
        snapshots: [LibrarySnapshot],
        destinationIDsAdded: Set<String> = []
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.snapshots = snapshots
        self.destinationIDsAdded = destinationIDsAdded
    }
}

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

    /// 最近一次批量操作；供内联「撤销」与片库页 `⌘Z` 共用。
    private(set) var lastBatchChange: LibraryBatchChange?

    /// 库内容变化（增删 / 详情回填）后的回调；AppEnvironment 用它刷新 Spotlight 索引。
    var onChange: (() -> Void)?

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

    // MARK: - 批量（v1.7）

    /// 批量移出当前清单；返回可撤销记录。没有任何匹配条目时返回 nil。
    @discardableResult
    func removeItems(ids: Set<String>, from kind: LibraryKind) -> LibraryBatchChange? {
        guard !ids.isEmpty else { return nil }
        let snapshots = items(in: kind).filter { ids.contains($0.id) }
        guard !snapshots.isEmpty else { return nil }

        deleteRecords(ids: Set(snapshots.map(\.id)), from: kind)
        let change = LibraryBatchChange(
            source: kind,
            destination: nil,
            snapshots: snapshots
        )
        lastBatchChange = change
        saveAndReload()
        return change
    }

    /// 批量移到另一清单；返回可撤销记录。没有任何匹配条目时返回 nil。
    @discardableResult
    func moveItems(
        ids: Set<String>,
        from source: LibraryKind,
        to destination: LibraryKind
    ) -> LibraryBatchChange? {
        guard source != destination, !ids.isEmpty else { return nil }
        let snapshots = items(in: source).filter { ids.contains($0.id) }
        guard !snapshots.isEmpty else { return nil }

        let destinationIDs = Set(items(in: destination).map(\.id))
        var added: Set<String> = []
        for snapshot in snapshots where !destinationIDs.contains(snapshot.id) {
            upsert(snapshot, into: destination)
            added.insert(snapshot.id)
        }
        deleteRecords(ids: Set(snapshots.map(\.id)), from: source)

        let change = LibraryBatchChange(
            source: source,
            destination: destination,
            snapshots: snapshots,
            destinationIDsAdded: added
        )
        lastBatchChange = change
        saveAndReload()
        return change
    }

    /// 撤销一次批量操作：目标清单只移除本次新增的条目，源清单按原 `addedAt` 恢复。
    func undo(_ change: LibraryBatchChange) {
        if let destination = change.destination {
            deleteRecords(ids: change.destinationIDsAdded, from: destination)
        }
        for snapshot in change.snapshots {
            upsert(snapshot, into: change.source, addedAt: snapshot.addedAt)
        }
        if lastBatchChange?.id == change.id {
            lastBatchChange = nil
        }
        saveAndReload()
    }

    func undoLastBatch() {
        guard let change = lastBatchChange else { return }
        undo(change)
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
    ///
    /// 保留原 `addedAt`：刷新展示字段不应改变「添加时间」排序（v1.7 修正）。
    func refresh(_ summary: MediaSummary) {
        let key = Self.key(for: summary)
        if favoriteIDs.contains(key) {
            let addedAt = favoriteItems.first { $0.id == key }?.addedAt ?? Date()
            LibraryStoreWriter.upsertFavorite(summary, into: context, addedAt: addedAt)
        }
        if watchlistIDs.contains(key) {
            let addedAt = watchlistItems.first { $0.id == key }?.addedAt ?? Date()
            LibraryStoreWriter.upsertWatchlist(summary, into: context, addedAt: addedAt)
        }
        saveAndReload()
    }

    // MARK: - 内部

    private func items(in kind: LibraryKind) -> [LibrarySnapshot] {
        kind == .favorites ? favoriteItems : watchlistItems
    }

    private func upsert(
        _ snapshot: LibrarySnapshot,
        into kind: LibraryKind,
        addedAt: Date = Date()
    ) {
        switch kind {
        case .favorites:
            LibraryStoreWriter.upsertFavorite(snapshot.asSummary, into: context, addedAt: addedAt)
        case .watchlist:
            LibraryStoreWriter.upsertWatchlist(snapshot.asSummary, into: context, addedAt: addedAt)
        }
    }

    /// 按 `(mediaType, tmdbID)` 删除；一次批量只调用一次 save。
    private func deleteRecords(ids: Set<String>, from kind: LibraryKind) {
        guard !ids.isEmpty else { return }
        switch kind {
        case .favorites:
            let records = (try? context.fetch(FetchDescriptor<FavoriteItem>())) ?? []
            for record in records
            where ids.contains(Self.key(mediaType: record.mediaType, tmdbID: record.tmdbID)) {
                context.delete(record)
            }
        case .watchlist:
            let records = (try? context.fetch(FetchDescriptor<WatchlistItem>())) ?? []
            for record in records
            where ids.contains(Self.key(mediaType: record.mediaType, tmdbID: record.tmdbID)) {
                context.delete(record)
            }
        }
    }

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
        onChange?()
    }

    private static func loadSnapshots<T: PersistentModel & LibraryRecord>(
        from context: ModelContext,
        type: T.Type
    ) -> [LibrarySnapshot] {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).map(\.snapshot)
    }

    private static func key(for summary: MediaSummary) -> String {
        key(mediaType: summary.mediaKind.rawValue, tmdbID: summary.id)
    }

    private static func key(mediaType: String, tmdbID: Int) -> String {
        "\(mediaType)-\(tmdbID)"
    }
}

/// 库类型（收藏 / 观看清单）。
enum LibraryKind: Sendable, Hashable {
    case favorites
    case watchlist

    var title: String {
        switch self {
        case .favorites: return "收藏"
        case .watchlist: return "观看清单"
        }
    }

    var opposite: LibraryKind {
        self == .favorites ? .watchlist : .favorites
    }
}
