import Foundation
import SwiftData
import OSLog

/// 一次单条 / 批量移出或移动的可撤销记录（v1.7，v1.7.1 泛化）。
///
/// `snapshots` 是操作前的源清单快照，撤销时按原 `addedAt` 放回；
/// `destinationIDsAdded` 只记录本次真正新增到目标清单的条目——撤销时只移除这些，
/// 移动前已在目标清单的条目保持不动。
struct LibraryChange: Identifiable, Sendable, Equatable {
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

/// 详情回填的单条结果。
enum DetailFetchResult: Sendable {
    /// 取到详情。
    case found(LibraryDetails)
    /// 作品已不存在（404）：标记为已尝试，不再反复请求。
    case gone
    /// 网络 / 服务端错误：保留待补状态，下次启动再试。
    case failed
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

    /// 最近一次可撤销的片库操作（单条 / 批量）；供内联「撤销」与片库页 `⌘Z` 共用。
    private(set) var lastChange: LibraryChange?

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
    func toggleFavorite(_ summary: MediaSummary, details: LibraryDetails? = nil) -> Bool {
        if favoriteIDs.contains(Self.key(for: summary)) {
            _ = removeFavorite(summary)
            return false
        }
        LibraryStoreWriter.upsertFavorite(summary, into: context, details: details)
        saveAndReload()
        return true
    }

    /// 移除成功返回 true；未收藏返回 nil。单条移出同样写入撤销记录（v1.7.1）。
    @discardableResult
    func removeFavorite(_ summary: MediaSummary) -> Bool? {
        let key = Self.key(for: summary)
        guard let snapshot = favoriteItems.first(where: { $0.id == key }) else { return nil }
        deleteRecords(ids: [key], from: .favorites)
        lastChange = LibraryChange(source: .favorites, destination: nil, snapshots: [snapshot])
        saveAndReload()
        return true
    }

    // MARK: - 观看清单

    func isInWatchlist(_ summary: MediaSummary) -> Bool {
        watchlistIDs.contains(Self.key(for: summary))
    }

    @discardableResult
    func toggleWatchlist(_ summary: MediaSummary, details: LibraryDetails? = nil) -> Bool {
        if watchlistIDs.contains(Self.key(for: summary)) {
            _ = removeFromWatchlist(summary)
            return false
        }
        LibraryStoreWriter.upsertWatchlist(summary, into: context, details: details)
        saveAndReload()
        return true
    }

    /// 移除成功返回 true；不在清单返回 nil。单条移出同样写入撤销记录（v1.7.1）。
    @discardableResult
    func removeFromWatchlist(_ summary: MediaSummary) -> Bool? {
        let key = Self.key(for: summary)
        guard let snapshot = watchlistItems.first(where: { $0.id == key }) else { return nil }
        deleteRecords(ids: [key], from: .watchlist)
        lastChange = LibraryChange(source: .watchlist, destination: nil, snapshots: [snapshot])
        saveAndReload()
        return true
    }

    /// 把观看清单条目移入收藏并移出清单（右键菜单用）。
    @discardableResult
    func moveToFavorites(_ summary: MediaSummary) -> LibraryChange? {
        moveSingle(summary, from: .watchlist, to: .favorites)
    }

    /// 把收藏条目移入观看清单并移出收藏（右键菜单用）。
    @discardableResult
    func moveToWatchlist(_ summary: MediaSummary) -> LibraryChange? {
        moveSingle(summary, from: .favorites, to: .watchlist)
    }

    // MARK: - 批量（v1.7）

    /// 批量移出当前清单；返回可撤销记录。没有任何匹配条目时返回 nil。
    @discardableResult
    func removeItems(ids: Set<String>, from kind: LibraryKind) -> LibraryChange? {
        guard !ids.isEmpty else { return nil }
        let snapshots = items(in: kind).filter { ids.contains($0.id) }
        guard !snapshots.isEmpty else { return nil }

        deleteRecords(ids: Set(snapshots.map(\.id)), from: kind)
        let change = LibraryChange(
            source: kind,
            destination: nil,
            snapshots: snapshots
        )
        lastChange = change
        saveAndReload()
        return change
    }

    /// 批量移到另一清单；返回可撤销记录。没有任何匹配条目时返回 nil。
    @discardableResult
    func moveItems(
        ids: Set<String>,
        from source: LibraryKind,
        to destination: LibraryKind
    ) -> LibraryChange? {
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

        let change = LibraryChange(
            source: source,
            destination: destination,
            snapshots: snapshots,
            destinationIDsAdded: added
        )
        lastChange = change
        saveAndReload()
        return change
    }

    /// 撤销一次单条 / 批量操作：目标清单只移除本次新增的条目，源清单按原 `addedAt` 恢复。
    func undo(_ change: LibraryChange) {
        if let destination = change.destination {
            deleteRecords(ids: change.destinationIDsAdded, from: destination)
        }
        for snapshot in change.snapshots {
            upsert(snapshot, into: change.source, addedAt: snapshot.addedAt)
        }
        if lastChange?.id == change.id {
            lastChange = nil
        }
        saveAndReload()
    }

    func undoLastChange() {
        guard let change = lastChange else { return }
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
    func refresh(_ summary: MediaSummary, details: LibraryDetails? = nil) {
        let key = Self.key(for: summary)
        if favoriteIDs.contains(key) {
            let addedAt = favoriteItems.first { $0.id == key }?.addedAt ?? Date()
            LibraryStoreWriter.upsertFavorite(summary, into: context, addedAt: addedAt, details: details)
        }
        if watchlistIDs.contains(key) {
            let addedAt = watchlistItems.first { $0.id == key }?.addedAt ?? Date()
            LibraryStoreWriter.upsertWatchlist(summary, into: context, addedAt: addedAt, details: details)
        }
        saveAndReload()
    }

    // MARK: - 回填（v1.9）

    /// 尚未富化的收藏 / 清单条数。
    var pendingEnrichmentCount: Int {
        (favoriteItems + watchlistItems).filter { !$0.isEnriched }.count
    }

    /// 逐条补齐详情富化字段。
    ///
    /// 回填受沙盒限制只能在应用运行时进行，`limit` 控制单次批量；
    /// 遇到网络 / 服务端错误立即停止，未处理的条目保持待补状态，下次启动再试。
    /// 返回本次实际处理（成功或确认已下线）的条数。
    @discardableResult
    func backfillDetails(
        limit: Int = 40,
        fetch: @escaping @Sendable (MediaKind, Int) async -> DetailFetchResult
    ) async -> Int {
        let pending = Array((favoriteItems + watchlistItems)
            .filter { !$0.isEnriched }
            .prefix(limit))
        guard !pending.isEmpty else { return 0 }

        var processed = 0
        for snapshot in pending {
            if Task.isCancelled { break }
            switch await fetch(snapshot.mediaKind, snapshot.tmdbID) {
            case .found(let details):
                applyBackfill(snapshot, details: details)
                processed += 1
            case .gone:
                applyBackfill(snapshot, details: nil)
                processed += 1
            case .failed:
                saveAndReload()
                return processed
            }
        }
        saveAndReload()
        return processed
    }

    private func applyBackfill(_ snapshot: LibrarySnapshot, details: LibraryDetails?) {
        let kind = snapshot.mediaKind.rawValue
        let id = snapshot.tmdbID
        let favorites = (try? context.fetch(FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id }
        ))) ?? []
        let watchlist = (try? context.fetch(FetchDescriptor<WatchlistItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id }
        ))) ?? []

        var records: [any LibraryModel] = []
        records.append(contentsOf: favorites)
        records.append(contentsOf: watchlist)

        let fetchedAt = Date()
        for record in records {
            if let details {
                details.apply(to: record, fetchedAt: fetchedAt)
            } else {
                // 作品已从 TMDB 下线：记为已尝试，不再反复请求。
                record.detailFetchedAt = fetchedAt
            }
        }
    }

    // MARK: - 内部

    /// 单条移动：只移除源条目；目标原本已有该条目时保留其 `addedAt`，撤销只删本次新增。
    @discardableResult
    private func moveSingle(
        _ summary: MediaSummary,
        from source: LibraryKind,
        to destination: LibraryKind
    ) -> LibraryChange? {
        guard source != destination else { return nil }
        let key = Self.key(for: summary)
        guard let snapshot = items(in: source).first(where: { $0.id == key }) else { return nil }

        let alreadyInDestination = items(in: destination).contains { $0.id == key }
        if !alreadyInDestination {
            upsert(snapshot, into: destination)
        }
        deleteRecords(ids: [key], from: source)

        let change = LibraryChange(
            source: source,
            destination: destination,
            snapshots: [snapshot],
            destinationIDsAdded: alreadyInDestination ? [] : [key]
        )
        lastChange = change
        saveAndReload()
        return change
    }

    private func items(in kind: LibraryKind) -> [LibrarySnapshot] {
        kind == .favorites ? favoriteItems : watchlistItems
    }

    private func upsert(
        _ snapshot: LibrarySnapshot,
        into kind: LibraryKind,
        addedAt: Date = Date()
    ) {
        // 移动 / 撤销时空值快照不应把条目误标为「已富化」。
        let details = snapshot.isEnriched
            ? LibraryDetails(
                genreNames: snapshot.genreNames, runtime: snapshot.runtime,
                director: snapshot.director, topCast: snapshot.topCast,
                countries: snapshot.countries, budget: snapshot.budget,
                revenue: snapshot.revenue
            )
            : nil
        switch kind {
        case .favorites:
            LibraryStoreWriter.upsertFavorite(snapshot.asSummary, into: context, addedAt: addedAt, details: details)
        case .watchlist:
            LibraryStoreWriter.upsertWatchlist(snapshot.asSummary, into: context, addedAt: addedAt, details: details)
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
