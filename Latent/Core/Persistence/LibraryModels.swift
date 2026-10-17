import Foundation
import SwiftData

/// 库条目的统一形态（收藏 / 观看清单 / 历史共用字段）。
///
/// 设计文档第 6 节：去重键 = `(mediaType, tmdbID)`；属性可选或带默认值，
/// 为将来平滑加启 CloudKit 留路径。
protocol LibraryModel {
    var mediaType: String { get set }
    var tmdbID: Int { get set }
    var title: String { get set }
    var originalTitle: String? { get set }
    var year: Int? { get set }
    var posterPath: String? { get set }
    var voteAverage: Double? { get set }
    var addedAt: Date { get set }
}

extension LibraryModel {
    var mediaKind: MediaKind { MediaKind(tmdbValue: mediaType) }
}

/// 收藏。
@Model
final class FavoriteItem: LibraryModel {
    var mediaType: String = ""
    var tmdbID: Int = 0
    var title: String = ""
    var originalTitle: String?
    var year: Int?
    var posterPath: String?
    var voteAverage: Double?
    var addedAt: Date = Date()

    init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
         originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
         voteAverage: Double? = nil, addedAt: Date = Date()) {
        self.mediaType = mediaType
        self.tmdbID = tmdbID
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.posterPath = posterPath
        self.voteAverage = voteAverage
        self.addedAt = addedAt
    }

    convenience init(summary: MediaSummary, addedAt: Date = Date()) {
        self.init(
            mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
            originalTitle: summary.originalTitle, year: summary.year,
            posterPath: summary.posterPath, voteAverage: summary.voteAverage, addedAt: addedAt
        )
    }
}

/// 观看清单。
@Model
final class WatchlistItem: LibraryModel {
    var mediaType: String = ""
    var tmdbID: Int = 0
    var title: String = ""
    var originalTitle: String?
    var year: Int?
    var posterPath: String?
    var voteAverage: Double?
    var addedAt: Date = Date()

    init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
         originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
         voteAverage: Double? = nil, addedAt: Date = Date()) {
        self.mediaType = mediaType
        self.tmdbID = tmdbID
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.posterPath = posterPath
        self.voteAverage = voteAverage
        self.addedAt = addedAt
    }

    convenience init(summary: MediaSummary, addedAt: Date = Date()) {
        self.init(
            mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
            originalTitle: summary.originalTitle, year: summary.year,
            posterPath: summary.posterPath, voteAverage: summary.voteAverage, addedAt: addedAt
        )
    }
}

/// 浏览历史（保留 500 条上限）。
@Model
final class HistoryEntry: LibraryModel {
    var mediaType: String = ""
    var tmdbID: Int = 0
    var title: String = ""
    var originalTitle: String?
    var year: Int?
    var posterPath: String?
    var voteAverage: Double?
    var addedAt: Date = Date()
    var lastViewedAt: Date = Date()

    init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
         originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
         voteAverage: Double? = nil, addedAt: Date = Date(), lastViewedAt: Date = Date()) {
        self.mediaType = mediaType
        self.tmdbID = tmdbID
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.posterPath = posterPath
        self.voteAverage = voteAverage
        self.addedAt = addedAt
        self.lastViewedAt = lastViewedAt
    }

    convenience init(summary: MediaSummary, viewedAt: Date = Date()) {
        self.init(
            mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
            originalTitle: summary.originalTitle, year: summary.year,
            posterPath: summary.posterPath, voteAverage: summary.voteAverage,
            addedAt: viewedAt, lastViewedAt: viewedAt
        )
    }
}
