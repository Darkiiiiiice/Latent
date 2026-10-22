import Foundation

/// 对比档案（v1.32）：把电影 / 剧集详情压成同构字段，供并排对比使用。
///
/// 只收 TMDB 明确给出的值，缺字段保持 nil（界面画「—」），不推断、不补零。
struct CompareProfile: Sendable, Identifiable, Hashable {
    /// 演员条目（共同出演靠 id 取交集，名字可能因语言而变）。
    struct CastEntry: Sendable, Identifiable, Hashable {
        let id: Int
        let name: String
        let character: String?
    }

    /// 与 `MediaSummary.stableID` 同构：同一 TMDB ID 的电影 / 剧集不会串。
    let id: String
    let tmdbID: Int
    let mediaKind: MediaKind
    let title: String
    let originalTitle: String?
    let posterPath: String?
    /// 电影为上映日、剧集为首播日（`yyyy年M月d日`）。
    let dateText: String?
    let rating: Double?
    let voteCount: Int?
    /// 电影片长；剧集取单集时长。
    let runtimeMinutes: Int?
    /// 剧集体量（季 / 集）；电影为 nil。
    let seasonsText: String?
    let budget: Int?
    let revenue: Int?
    let genres: [String]
    let directors: [String]
    let cast: [CastEntry]

    /// 统一入口：只有电影 / 剧集实现 `MediaDetail`，人物与公司不参与对比。
    init(detail: any MediaDetail) {
        switch detail {
        case let movie as MovieDetail:
            self.init(movie: movie)
        case let show as TVShowDetail:
            self.init(show: show)
        default:
            preconditionFailure("不支持的详情类型：\(type(of: detail))")
        }
    }

    init(movie: MovieDetail) {
        self.id = "movie-\(movie.id)"
        self.tmdbID = movie.id
        self.mediaKind = .movie
        self.title = movie.title
        self.originalTitle = movie.originalTitle
        self.posterPath = movie.posterPath
        self.dateText = Formatters.fullDate(movie.dateString)
        self.rating = movie.voteAverage
        self.voteCount = movie.voteCount
        self.runtimeMinutes = movie.runtime
        self.seasonsText = nil
        self.budget = movie.budget
        self.revenue = movie.revenue
        self.genres = movie.genres?.map(\.name) ?? []
        self.directors = movie.credits?.directors.map(\.name) ?? []
        self.cast = Self.castEntries(movie.credits?.cast)
    }

    init(show: TVShowDetail) {
        self.id = "tv-\(show.id)"
        self.tmdbID = show.id
        self.mediaKind = .tv
        self.title = show.name
        self.originalTitle = show.originalName
        self.posterPath = show.posterPath
        self.dateText = Formatters.fullDate(show.firstAirDate)
        self.rating = show.voteAverage
        self.voteCount = show.voteCount
        self.runtimeMinutes = show.episodeRunTime?.first
        self.seasonsText = Self.seasonsText(show)
        self.budget = nil
        self.revenue = nil
        self.genres = show.genres?.map(\.name) ?? []
        // 剧集优先用 `created_by`（主创），没有时退回 credits 里的 Creator / Director。
        if let created = show.createdBy, !created.isEmpty {
            self.directors = created.map(\.name)
        } else {
            self.directors = show.credits?.directors.map(\.name) ?? []
        }
        self.cast = Self.castEntries(show.credits?.cast)
    }

    private static func castEntries(_ cast: [CastMember]?) -> [CastEntry] {
        (cast ?? []).map { CastEntry(id: $0.id, name: $0.name, character: $0.characterOrNil) }
    }

    private static func seasonsText(_ show: TVShowDetail) -> String? {
        var parts: [String] = []
        if let seasons = show.numberOfSeasons { parts.append("\(seasons) 季") }
        if let episodes = show.numberOfEpisodes { parts.append("\(episodes) 集") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var stableID: String { id }
}

/// 对比结果（v1.32）：指标行 + 共同项，全部由两侧档案算出，不联网。
struct CompareResult: Sendable {
    struct Row: Identifiable, Sendable {
        /// 谁领先：评分与票房才有意义，其余行一律 `.none`（不强判优劣）。
        enum Leader: Sendable {
            case left, right, tie, none
        }

        let id: String
        let label: String
        let left: String
        let right: String
        let leader: Leader
    }

    let left: CompareProfile
    let right: CompareProfile
    let rows: [Row]
    /// 共同类型（保持左片顺序）。
    let sharedGenres: [String]
    /// 共同导演 / 主创（按名字取交集）。
    let sharedDirectors: [String]
    /// 共同出演（按演员 id 取交集，保持左片演职员顺序）。
    let sharedCast: [CompareProfile.CastEntry]
    /// 两部在同一指标上的相同项数量，供页头一句话概括。
    var sharedCount: Int { sharedGenres.count + sharedDirectors.count + sharedCast.count }

    static func make(left: CompareProfile, right: CompareProfile) -> CompareResult {
        let rightGenres = Set(right.genres)
        let rightCastIDs = Set(right.cast.map(\.id))

        return CompareResult(
            left: left,
            right: right,
            rows: rows(left: left, right: right),
            sharedGenres: left.genres.filter { rightGenres.contains($0) },
            sharedDirectors: left.directors.filter { right.directors.contains($0) },
            sharedCast: left.cast.filter { rightCastIDs.contains($0.id) }
        )
    }

    // MARK: - 指标行

    private static func rows(left: CompareProfile, right: CompareProfile) -> [Row] {
        var rows: [Row] = [
            Row(
                id: "genre",
                label: "类型",
                left: genreText(left.genres),
                right: genreText(right.genres),
                leader: .none
            ),
            Row(
                id: "date",
                label: left.mediaKind == .movie && right.mediaKind == .movie ? "上映" : "首播",
                left: left.dateText ?? "—",
                right: right.dateText ?? "—",
                leader: .none
            ),
        ]

        if left.runtimeMinutes != nil || right.runtimeMinutes != nil {
            rows.append(Row(
                id: "runtime",
                label: "片长",
                left: Formatters.runtime(minutes: left.runtimeMinutes) ?? "—",
                right: Formatters.runtime(minutes: right.runtimeMinutes) ?? "—",
                leader: .none
            ))
        }

        if left.seasonsText != nil || right.seasonsText != nil {
            rows.append(Row(
                id: "seasons",
                label: "体量",
                left: left.seasonsText ?? "—",
                right: right.seasonsText ?? "—",
                leader: .none
            ))
        }

        if left.rating != nil || right.rating != nil {
            let leftText = ratingText(left.rating, votes: left.voteCount)
            let rightText = ratingText(right.rating, votes: right.voteCount)
            rows.append(Row(
                id: "rating",
                label: "评分",
                left: leftText,
                right: rightText,
                leader: leader(left.rating, right.rating)
            ))
        }

        if left.budget != nil || right.budget != nil {
            rows.append(Row(
                id: "budget",
                label: "预算",
                left: Formatters.money(left.budget) ?? "—",
                right: Formatters.money(right.budget) ?? "—",
                leader: .none
            ))
        }

        if left.revenue != nil || right.revenue != nil {
            rows.append(Row(
                id: "revenue",
                label: "票房",
                left: Formatters.money(left.revenue) ?? "—",
                right: Formatters.money(right.revenue) ?? "—",
                leader: leader(left.revenue.map(Double.init), right.revenue.map(Double.init))
            ))
        }

        return rows
    }

    private static func genreText(_ genres: [String]) -> String {
        genres.isEmpty ? "—" : genres.prefix(3).joined(separator: " / ")
    }

    private static func ratingText(_ rating: Double?, votes: Int?) -> String {
        guard let value = Formatters.rating(rating) else { return "—" }
        guard let votes, votes > 0 else { return value }
        return "\(value) · \(Formatters.voteCount(votes))"
    }

    private static func leader(_ left: Double?, _ right: Double?) -> Row.Leader {
        guard let left, let right else { return .none }
        if left == right { return .tie }
        return left > right ? .left : .right
    }
}
