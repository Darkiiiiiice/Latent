import Foundation
import SwiftData
import OSLog

/// 库写入（收藏 / 清单 / 历史）：以 `(mediaType, tmdbID)` 为键去重，刷新或插入（设计文档第 6 节）。
///
/// 按具体模型类型分派（`#Predicate` 需要访问具体类型的属性，协议属性不可用）。
enum LibraryStoreWriter {
    @discardableResult
    static func upsertFavorite(
        _ summary: MediaSummary,
        into context: ModelContext,
        addedAt: Date = Date(),
        details: LibraryDetails? = nil
    ) -> FavoriteItem {
        let kind = summary.mediaKind.rawValue
        let id = summary.id
        let descriptor = FetchDescriptor<FavoriteItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if let first = existing.first {
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
            first.mediaType = kind
            first.tmdbID = id
            first.title = summary.title
            first.originalTitle = summary.originalTitle
            first.year = summary.year
            first.posterPath = summary.posterPath
            first.voteAverage = summary.voteAverage
            first.addedAt = addedAt
            details?.apply(to: first)
            return first
        }
        let item = FavoriteItem(summary: summary, addedAt: addedAt, details: details)
        context.insert(item)
        return item
    }

    @discardableResult
    static func upsertWatchlist(
        _ summary: MediaSummary,
        into context: ModelContext,
        addedAt: Date = Date(),
        details: LibraryDetails? = nil
    ) -> WatchlistItem {
        let kind = summary.mediaKind.rawValue
        let id = summary.id
        let descriptor = FetchDescriptor<WatchlistItem>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if let first = existing.first {
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
            first.mediaType = kind
            first.tmdbID = id
            first.title = summary.title
            first.originalTitle = summary.originalTitle
            first.year = summary.year
            first.posterPath = summary.posterPath
            first.voteAverage = summary.voteAverage
            first.addedAt = addedAt
            details?.apply(to: first)
            return first
        }
        let item = WatchlistItem(summary: summary, addedAt: addedAt, details: details)
        context.insert(item)
        return item
    }

    @discardableResult
    static func upsertHistory(_ summary: MediaSummary, into context: ModelContext, at date: Date = Date()) -> HistoryEntry {
        let kind = summary.mediaKind.rawValue
        let id = summary.id
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.mediaType == kind && $0.tmdbID == id },
            sortBy: [SortDescriptor(\.lastViewedAt, order: .reverse)]
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if let first = existing.first {
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
            first.mediaType = kind
            first.tmdbID = id
            first.title = summary.title
            first.originalTitle = summary.originalTitle
            first.year = summary.year
            first.posterPath = summary.posterPath
            first.voteAverage = summary.voteAverage
            first.lastViewedAt = date
            return first
        }
        let entry = HistoryEntry(summary: summary, viewedAt: date)
        context.insert(entry)
        return entry
    }
}

/// 库快照（送进视图的 Sendable 值；不持有 SwiftData 对象）。
struct LibrarySnapshot: Sendable, Identifiable, Hashable {
    let mediaKind: MediaKind
    let tmdbID: Int
    let title: String
    let originalTitle: String?
    let year: Int?
    let posterPath: String?
    let voteAverage: Double?
    let addedAt: Date

    // MARK: 详情富化（V2；旧数据为 nil，回填后补齐）
    var genreNames: [String] = []
    var runtime: Int? = nil
    var director: String? = nil
    var topCast: [String] = []
    var countries: [String] = []
    var budget: Int64? = nil
    var revenue: Int64? = nil
    var detailFetchedAt: Date? = nil

    var id: String { "\(mediaKind.rawValue)-\(tmdbID)" }

    /// 详情字段是否已回填（统计页据此提示待补数量）。
    var isEnriched: Bool { detailFetchedAt != nil }

    var asSummary: MediaSummary {
        MediaSummary(
            id: tmdbID, mediaKind: mediaKind, title: title,
            originalTitle: originalTitle, posterPath: posterPath,
            dateString: year.map { "\($0)-01-01" },
            voteAverage: voteAverage
        )
    }
}

/// 库记录（收藏 / 清单 / 历史）的统一读取面。
@MainActor
protocol LibraryRecord: PersistentModel, LibraryModel {
    var lastViewedAt: Date { get }
    var snapshot: LibrarySnapshot { get }
}

extension FavoriteItem: LibraryRecord {
    var snapshot: LibrarySnapshot {
        LibrarySnapshot(mediaKind: mediaKind, tmdbID: tmdbID, title: title,
                        originalTitle: originalTitle, year: year,
                        posterPath: posterPath, voteAverage: voteAverage, addedAt: addedAt,
                        genreNames: genreNames ?? [], runtime: runtime, director: director,
                        topCast: topCast ?? [], countries: countries ?? [],
                        budget: budget, revenue: revenue, detailFetchedAt: detailFetchedAt)
    }
    var lastViewedAt: Date { addedAt }
}

extension WatchlistItem: LibraryRecord {
    var snapshot: LibrarySnapshot {
        LibrarySnapshot(mediaKind: mediaKind, tmdbID: tmdbID, title: title,
                        originalTitle: originalTitle, year: year,
                        posterPath: posterPath, voteAverage: voteAverage, addedAt: addedAt,
                        genreNames: genreNames ?? [], runtime: runtime, director: director,
                        topCast: topCast ?? [], countries: countries ?? [],
                        budget: budget, revenue: revenue, detailFetchedAt: detailFetchedAt)
    }
    var lastViewedAt: Date { addedAt }
}

extension HistoryEntry: LibraryRecord {
    var snapshot: LibrarySnapshot {
        LibrarySnapshot(mediaKind: mediaKind, tmdbID: tmdbID, title: title,
                        originalTitle: originalTitle, year: year,
                        posterPath: posterPath, voteAverage: voteAverage, addedAt: lastViewedAt,
                        genreNames: genreNames ?? [], runtime: runtime, director: director,
                        topCast: topCast ?? [], countries: countries ?? [],
                        budget: budget, revenue: revenue, detailFetchedAt: detailFetchedAt)
    }
}
