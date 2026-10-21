import Foundation
import SwiftData

/// 版本化 Schema（设计文档第 6 节）。
///
/// V1：按 `(mediaType, tmdbID)` 去重的三份清单，只存列表展示字段。
/// V2：在 V1 基础上追加详情富化字段（类型 / 时长 / 导演 / 主演 / 国家 / 预算票房），
///     全部为可选属性，走轻量迁移——旧数据保留，富化字段在启动回填后补齐。
/// V3：再补 `voteCount`（评分人数），供统计页的「冷门 / 大众指数」使用，同样是可选属性。
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [FavoriteItem.self, WatchlistItem.self, HistoryEntry.self]
    }

    @Model
    final class FavoriteItem {
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
    }

    @Model
    final class WatchlistItem {
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
    }

    @Model
    final class HistoryEntry {
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
    }
}

/// 当前 Schema：加入详情富化字段。
enum LibrarySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [FavoriteItem.self, WatchlistItem.self, HistoryEntry.self]
    }

    @Model
    final class FavoriteItem {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?

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
                posterPath: summary.posterPath, voteAverage: summary.voteAverage,
                addedAt: addedAt
            )
        }
    }

    @Model
    final class WatchlistItem {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?

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
                posterPath: summary.posterPath, voteAverage: summary.voteAverage,
                addedAt: addedAt
            )
        }
    }

    @Model
    final class HistoryEntry {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()
        var lastViewedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?

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
}

/// 当前 Schema：在 V2 富化字段之上补 `voteCount`，供「冷门 / 大众指数」使用。
enum LibrarySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [FavoriteItem.self, WatchlistItem.self, HistoryEntry.self]
    }

    @Model
    final class FavoriteItem {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?
        var voteCount: Int?

        init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
             originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
             voteAverage: Double? = nil, addedAt: Date = Date(),
             details: LibraryDetails? = nil) {
            self.mediaType = mediaType
            self.tmdbID = tmdbID
            self.title = title
            self.originalTitle = originalTitle
            self.year = year
            self.posterPath = posterPath
            self.voteAverage = voteAverage
            self.addedAt = addedAt
            details?.apply(to: self)
        }

        convenience init(summary: MediaSummary, addedAt: Date = Date(), details: LibraryDetails? = nil) {
            self.init(
                mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
                originalTitle: summary.originalTitle, year: summary.year,
                posterPath: summary.posterPath, voteAverage: summary.voteAverage,
                addedAt: addedAt, details: details
            )
        }
    }

    @Model
    final class WatchlistItem {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?
        var voteCount: Int?

        init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
             originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
             voteAverage: Double? = nil, addedAt: Date = Date(),
             details: LibraryDetails? = nil) {
            self.mediaType = mediaType
            self.tmdbID = tmdbID
            self.title = title
            self.originalTitle = originalTitle
            self.year = year
            self.posterPath = posterPath
            self.voteAverage = voteAverage
            self.addedAt = addedAt
            details?.apply(to: self)
        }

        convenience init(summary: MediaSummary, addedAt: Date = Date(), details: LibraryDetails? = nil) {
            self.init(
                mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
                originalTitle: summary.originalTitle, year: summary.year,
                posterPath: summary.posterPath, voteAverage: summary.voteAverage,
                addedAt: addedAt, details: details
            )
        }
    }

    @Model
    final class HistoryEntry {
        var mediaType: String = ""
        var tmdbID: Int = 0
        var title: String = ""
        var originalTitle: String?
        var year: Int?
        var posterPath: String?
        var voteAverage: Double?
        var addedAt: Date = Date()
        var lastViewedAt: Date = Date()

        var genreNames: [String]?
        var runtime: Int?
        var director: String?
        var topCast: [String]?
        var countries: [String]?
        var budget: Int64?
        var revenue: Int64?
        var detailFetchedAt: Date?
        var voteCount: Int?

        init(mediaType: String = "", tmdbID: Int = 0, title: String = "",
             originalTitle: String? = nil, year: Int? = nil, posterPath: String? = nil,
             voteAverage: Double? = nil, addedAt: Date = Date(), lastViewedAt: Date = Date(),
             details: LibraryDetails? = nil) {
            self.mediaType = mediaType
            self.tmdbID = tmdbID
            self.title = title
            self.originalTitle = originalTitle
            self.year = year
            self.posterPath = posterPath
            self.voteAverage = voteAverage
            self.addedAt = addedAt
            self.lastViewedAt = lastViewedAt
            details?.apply(to: self)
        }

        convenience init(summary: MediaSummary, viewedAt: Date = Date(), details: LibraryDetails? = nil) {
            self.init(
                mediaType: summary.mediaKind.rawValue, tmdbID: summary.id, title: summary.title,
                originalTitle: summary.originalTitle, year: summary.year,
                posterPath: summary.posterPath, voteAverage: summary.voteAverage,
                addedAt: viewedAt, lastViewedAt: viewedAt, details: details
            )
        }
    }
}

/// 迁移计划：V1 → V2 → V3 均只新增可选属性，走轻量迁移，无需数据搬运。
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
            .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self)
        ]
    }
}

/// 当前 Schema 类型别名，供容器与 Store 使用。
typealias CurrentLibrarySchema = LibrarySchemaV3

// 全模块统一使用当前版本的模型类型；V1 / V2 类型只在迁移计划里出现。
typealias FavoriteItem = LibrarySchemaV3.FavoriteItem
typealias WatchlistItem = LibrarySchemaV3.WatchlistItem
typealias HistoryEntry = LibrarySchemaV3.HistoryEntry
