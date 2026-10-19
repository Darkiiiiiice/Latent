import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// 电影 / 剧集实体：同时用于 Shortcuts 参数与 Spotlight 索引（`IndexedEntity`）。
///
/// ID 约定：`movie-<tmdbID>` / `tv-<tmdbID>`，与库条目 `LibrarySnapshot.id` 一致。
struct TitleEntity: IndexedEntity, Hashable, Sendable {
    let tmdbID: Int
    let mediaKind: MediaKind
    let title: String
    let originalTitle: String?
    let year: Int?
    let voteAverage: Double?
    let posterPath: String?
    let overview: String?

    var id: String { "\(mediaKind.rawValue)-\(tmdbID)" }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "影视作品"

    static let defaultQuery = TitleEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        var subtitle = mediaKind.label
        if let year {
            subtitle += " · \(year)"
        }
        if let rating = Formatters.rating(voteAverage) {
            subtitle += " · ★ \(rating)"
        }
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)",
            image: displayImage
        )
    }

    /// Spotlight 属性：标题、描述、关键词与海报缩略图。
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(
            contentType: mediaKind == .movie ? UTType.movie : UTType.video
        )
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = descriptionText
        attributes.keywords = keywords
        if let posterURL = posterURL {
            attributes.thumbnailURL = posterURL
        }
        attributes.metadataModificationDate = Date()
        return attributes
    }

    var summary: MediaSummary {
        MediaSummary(
            id: tmdbID,
            mediaKind: mediaKind,
            title: title,
            originalTitle: originalTitle,
            overview: overview,
            posterPath: posterPath,
            dateString: year.map { "\($0)-01-01" },
            voteAverage: voteAverage
        )
    }

    var detailDestination: DetailDestination? {
        switch mediaKind {
        case .movie: return .movie(id: tmdbID, fallback: summary)
        case .tv: return .tv(id: tmdbID, fallback: summary)
        default: return nil
        }
    }

    // MARK: - 初始化

    init(
        tmdbID: Int,
        mediaKind: MediaKind,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        voteAverage: Double? = nil,
        posterPath: String? = nil,
        overview: String? = nil
    ) {
        self.tmdbID = tmdbID
        self.mediaKind = mediaKind
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.voteAverage = voteAverage
        self.posterPath = posterPath
        self.overview = overview
    }

    init(snapshot: LibrarySnapshot) {
        self.init(
            tmdbID: snapshot.tmdbID,
            mediaKind: snapshot.mediaKind,
            title: snapshot.title,
            originalTitle: snapshot.originalTitle,
            year: snapshot.year,
            voteAverage: snapshot.voteAverage,
            posterPath: snapshot.posterPath
        )
    }

    init(summary: MediaSummary) {
        self.init(
            tmdbID: summary.id,
            mediaKind: summary.mediaKind,
            title: summary.title,
            originalTitle: summary.originalTitle,
            year: summary.year,
            voteAverage: summary.voteAverage,
            posterPath: summary.posterPath,
            overview: summary.overview
        )
    }

    // MARK: - 合并 / 解析（Spotlight 与测试共用）

    /// 收藏 + 清单合并；同一 ID 只保留一条（收藏的加入时间更早或数据更完整时以收藏为准）。
    static func merged(favorites: [LibrarySnapshot], watchlist: [LibrarySnapshot]) -> [TitleEntity] {
        let buckets = buckets(favorites: favorites, watchlist: watchlist)
        return buckets.favorites + buckets.watchlist
    }

    /// 收藏优先：同一作品同时存在时只进收藏组。
    static func buckets(
        favorites: [LibrarySnapshot],
        watchlist: [LibrarySnapshot]
    ) -> (favorites: [TitleEntity], watchlist: [TitleEntity]) {
        let favoriteEntities = favorites
            .sorted { $0.addedAt > $1.addedAt }
            .map(TitleEntity.init(snapshot:))
        let favoriteIDs = Set(favoriteEntities.map(\.id))
        let watchlistEntities = watchlist
            .filter { !favoriteIDs.contains($0.id) }
            .sorted { $0.addedAt > $1.addedAt }
            .map(TitleEntity.init(snapshot:))
        return (favoriteEntities, watchlistEntities)
    }

    static func parse(identifier: String) -> (mediaKind: MediaKind, tmdbID: Int)? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "movie": return (.movie, id)
        case "tv": return (.tv, id)
        default: return nil
        }
    }

    // MARK: - 私有展示

    private var posterURL: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    private var displayImage: DisplayRepresentation.Image? {
        if let posterURL {
            return .init(url: posterURL)
        }
        return .init(systemName: mediaKind == .movie ? "film" : "tv")
    }

    private var descriptionText: String {
        var parts = [mediaKind.label]
        if let year { parts.append("\(year)") }
        if let rating = Formatters.rating(voteAverage) { parts.append("评分 \(rating)") }
        parts.append("TMDB \(tmdbID)")
        if let overview, !overview.isEmpty {
            parts.append(overview)
        }
        return parts.joined(separator: " · ")
    }

    private var keywords: [String] {
        var values = [title, mediaKind.label, "TMDB"]
        if let originalTitle, !originalTitle.isEmpty, originalTitle != title {
            values.append(originalTitle)
        }
        if let year {
            values.append("\(year)")
        }
        return values
    }
}
