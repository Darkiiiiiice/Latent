import Foundation

/// 电影详情（GET /3/movie/{id}，append_to_response=credits,images,similar,recommendations,external_ids,release_dates,watch/providers）。
struct MovieDetail: MediaDetail, Decodable, Sendable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let dateString: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [Genre]?
    let tagline: String?
    let status: String?
    let originalLanguage: String?
    let homepage: URL?
    let externalIDs: ExternalIDs?
    let credits: Credits?
    let images: MediaImages?
    let similar: [MediaSummary]?
    let recommendations: [MediaSummary]?
    let watchProviders: WatchProviders?
    let runtime: Int?
    let budget: Int?
    let revenue: Int?
    /// 制片国家（详情基础响应自带，无需 append）。
    let productionCountries: [ProductionCountry]?
    /// 原始国家代码（`origin_country`）。
    let originCountry: [String]?
    /// 所属系列（v1.19）：系列片才有，普通独立电影为 nil。
    let belongsToCollection: CollectionSummary?

    var mediaKind: MediaKind { .movie }

    private enum CodingKeys: String, CodingKey {
        case id, title, overview, genres, tagline, status, homepage, runtime, budget, revenue
        case originalTitle = "original_title"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
        case externalIDs = "external_ids"
        case watchProviders = "watch/providers"
        case credits, images, similar, recommendations
        case productionCountries = "production_countries"
        case originCountry = "origin_country"
        case belongsToCollection = "belongs_to_collection"
    }

    init(
        id: Int, title: String, originalTitle: String? = nil, overview: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, dateString: String? = nil,
        voteAverage: Double? = nil, voteCount: Int? = nil, genres: [Genre]? = nil,
        tagline: String? = nil, status: String? = nil, originalLanguage: String? = nil,
        homepage: URL? = nil, externalIDs: ExternalIDs? = nil, credits: Credits? = nil,
        images: MediaImages? = nil, similar: [MediaSummary]? = nil,
        recommendations: [MediaSummary]? = nil, watchProviders: WatchProviders? = nil,
        runtime: Int? = nil, budget: Int? = nil, revenue: Int? = nil,
        productionCountries: [ProductionCountry]? = nil, originCountry: [String]? = nil,
        belongsToCollection: CollectionSummary? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.dateString = dateString
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genres = genres
        self.tagline = tagline
        self.status = status
        self.originalLanguage = originalLanguage
        self.homepage = homepage
        self.externalIDs = externalIDs
        self.credits = credits
        self.images = images
        self.similar = similar
        self.recommendations = recommendations
        self.watchProviders = watchProviders
        self.runtime = runtime
        self.budget = budget
        self.revenue = revenue
        self.productionCountries = productionCountries
        self.originCountry = originCountry
        self.belongsToCollection = belongsToCollection
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "（无标题）"
        self.originalTitle = (try? container.decodeIfPresent(String.self, forKey: .originalTitle)) ?? nil
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.backdropPath = (try? container.decodeIfPresent(String.self, forKey: .backdropPath)) ?? nil
        self.dateString = (try? container.decodeIfPresent(String.self, forKey: .releaseDate)) ?? nil
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        self.voteCount = (try? container.decodeIfPresent(Int.self, forKey: .voteCount)) ?? nil
        self.genres = (try? container.decodeIfPresent([Genre].self, forKey: .genres)) ?? nil
        self.tagline = (try? container.decodeIfPresent(String.self, forKey: .tagline)) ?? nil
        self.status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        self.originalLanguage = (try? container.decodeIfPresent(String.self, forKey: .originalLanguage)) ?? nil
        let homepageString = (try? container.decodeIfPresent(String.self, forKey: .homepage)) ?? nil
        self.homepage = homepageString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self.externalIDs = (try? container.decodeIfPresent(ExternalIDs.self, forKey: .externalIDs)) ?? nil
        self.credits = (try? container.decodeIfPresent(Credits.self, forKey: .credits)) ?? nil
        self.images = (try? container.decodeIfPresent(MediaImages.self, forKey: .images)) ?? nil
        // TMDB 的相似 / 推荐是分页对象（{ page, results }），只取 results。
        let similarPage = (try? container.decodeIfPresent(Paged<MediaSummary>.self, forKey: .similar)) ?? nil
        let recommendationsPage = (try? container.decodeIfPresent(Paged<MediaSummary>.self, forKey: .recommendations)) ?? nil
        self.similar = similarPage?.items
        self.recommendations = recommendationsPage?.items
        self.watchProviders = (try? container.decodeIfPresent(WatchProviders.self, forKey: .watchProviders)) ?? nil
        self.runtime = (try? container.decodeIfPresent(Int.self, forKey: .runtime)) ?? nil
        self.budget = (try? container.decodeIfPresent(Int.self, forKey: .budget)) ?? nil
        self.revenue = (try? container.decodeIfPresent(Int.self, forKey: .revenue)) ?? nil
        self.productionCountries = (try? container.decodeIfPresent([ProductionCountry].self, forKey: .productionCountries)) ?? nil
        self.originCountry = (try? container.decodeIfPresent([String].self, forKey: .originCountry)) ?? nil
        self.belongsToCollection = (try? container.decodeIfPresent(CollectionSummary.self, forKey: .belongsToCollection)) ?? nil
    }

    /// 事实栏行（电影：状态 / 上映 / 时长 / 预算 / 票房 / 语言）。
    var facts: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let status { rows.append((label: "状态", value: status)) }
        if let date = Formatters.fullDate(dateString) { rows.append((label: "上映", value: date)) }
        if let runtime, let text = Formatters.runtime(minutes: runtime) { rows.append((label: "时长", value: text)) }
        if let budget, let text = Formatters.money(budget) { rows.append((label: "预算", value: text)) }
        if let revenue, let text = Formatters.money(revenue) { rows.append((label: "票房", value: text)) }
        if let originalLanguage { rows.append((label: "语言", value: originalLanguage)) }
        return rows
    }

    var libraryDetails: LibraryDetails { LibraryDetails(movie: self) }
}

/// 剧集详情（GET /3/tv/{id}，append_to_response=credits,images,similar,recommendations,external_ids,content_ratings,watch/providers）。
struct TVShowDetail: MediaDetail, Decodable, Sendable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [Genre]?
    let tagline: String?
    let status: String?
    let originalLanguage: String?
    let homepage: URL?
    let externalIDs: ExternalIDs?
    let credits: Credits?
    let images: MediaImages?
    let similar: [MediaSummary]?
    let recommendations: [MediaSummary]?
    let watchProviders: WatchProviders?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [Season]?
    let episodeRunTime: [Int]?
    let lastAirDate: String?
    let networks: [Network]?
    /// 主创（TMDB `created_by`；与分集导演是两回事）。
    let createdBy: [Creator]?
    /// 出品国家 / 地区。
    let productionCountries: [ProductionCountry]?
    let originCountry: [String]?
    /// 下一集（v1.18「追更」）：TMDB 在未完结剧集上直接给出 `next_episode_to_air`。
    let nextEpisodeToAir: Episode?

    var mediaKind: MediaKind { .tv }
    var title: String { name }
    var originalTitle: String? { originalName }
    var dateString: String? { firstAirDate }

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, tagline, status, homepage, seasons, networks
        case originalName = "original_name"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
        case externalIDs = "external_ids"
        case watchProviders = "watch/providers"
        case credits, images, similar, recommendations
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case lastAirDate = "last_air_date"
        case createdBy = "created_by"
        case productionCountries = "production_countries"
        case originCountry = "origin_country"
        case nextEpisodeToAir = "next_episode_to_air"
    }

    init(
        id: Int, name: String, originalName: String? = nil, overview: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, firstAirDate: String? = nil,
        voteAverage: Double? = nil, voteCount: Int? = nil, genres: [Genre]? = nil,
        tagline: String? = nil, status: String? = nil, originalLanguage: String? = nil,
        homepage: URL? = nil, externalIDs: ExternalIDs? = nil, credits: Credits? = nil,
        images: MediaImages? = nil, similar: [MediaSummary]? = nil,
        recommendations: [MediaSummary]? = nil, watchProviders: WatchProviders? = nil,
        numberOfSeasons: Int? = nil,
        numberOfEpisodes: Int? = nil, seasons: [Season]? = nil,
        episodeRunTime: [Int]? = nil, lastAirDate: String? = nil,
        networks: [Network]? = nil, createdBy: [Creator]? = nil,
        productionCountries: [ProductionCountry]? = nil, originCountry: [String]? = nil,
        nextEpisodeToAir: Episode? = nil
    ) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.firstAirDate = firstAirDate
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genres = genres
        self.tagline = tagline
        self.status = status
        self.originalLanguage = originalLanguage
        self.homepage = homepage
        self.externalIDs = externalIDs
        self.credits = credits
        self.images = images
        self.similar = similar
        self.recommendations = recommendations
        self.watchProviders = watchProviders
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.seasons = seasons
        self.episodeRunTime = episodeRunTime
        self.lastAirDate = lastAirDate
        self.networks = networks
        self.createdBy = createdBy
        self.productionCountries = productionCountries
        self.originCountry = originCountry
        self.nextEpisodeToAir = nextEpisodeToAir
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "（无标题）"
        self.originalName = (try? container.decodeIfPresent(String.self, forKey: .originalName)) ?? nil
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.backdropPath = (try? container.decodeIfPresent(String.self, forKey: .backdropPath)) ?? nil
        self.firstAirDate = (try? container.decodeIfPresent(String.self, forKey: .firstAirDate)) ?? nil
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        self.voteCount = (try? container.decodeIfPresent(Int.self, forKey: .voteCount)) ?? nil
        self.genres = (try? container.decodeIfPresent([Genre].self, forKey: .genres)) ?? nil
        self.tagline = (try? container.decodeIfPresent(String.self, forKey: .tagline)) ?? nil
        self.status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil
        self.originalLanguage = (try? container.decodeIfPresent(String.self, forKey: .originalLanguage)) ?? nil
        let homepageString = (try? container.decodeIfPresent(String.self, forKey: .homepage)) ?? nil
        self.homepage = homepageString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self.externalIDs = (try? container.decodeIfPresent(ExternalIDs.self, forKey: .externalIDs)) ?? nil
        self.credits = (try? container.decodeIfPresent(Credits.self, forKey: .credits)) ?? nil
        self.images = (try? container.decodeIfPresent(MediaImages.self, forKey: .images)) ?? nil
        // 同电影：相似 / 推荐是分页对象。
        let similarPage = (try? container.decodeIfPresent(Paged<MediaSummary>.self, forKey: .similar)) ?? nil
        let recommendationsPage = (try? container.decodeIfPresent(Paged<MediaSummary>.self, forKey: .recommendations)) ?? nil
        self.similar = similarPage?.items
        self.recommendations = recommendationsPage?.items
        self.watchProviders = (try? container.decodeIfPresent(WatchProviders.self, forKey: .watchProviders)) ?? nil
        self.numberOfSeasons = (try? container.decodeIfPresent(Int.self, forKey: .numberOfSeasons)) ?? nil
        self.numberOfEpisodes = (try? container.decodeIfPresent(Int.self, forKey: .numberOfEpisodes)) ?? nil
        self.seasons = (try? container.decodeIfPresent([Season].self, forKey: .seasons)) ?? nil
        self.episodeRunTime = (try? container.decodeIfPresent([Int].self, forKey: .episodeRunTime)) ?? nil
        self.lastAirDate = (try? container.decodeIfPresent(String.self, forKey: .lastAirDate)) ?? nil
        self.networks = (try? container.decodeIfPresent([Network].self, forKey: .networks)) ?? nil
        self.createdBy = (try? container.decodeIfPresent([Creator].self, forKey: .createdBy)) ?? nil
        self.productionCountries = (try? container.decodeIfPresent([ProductionCountry].self, forKey: .productionCountries)) ?? nil
        self.originCountry = (try? container.decodeIfPresent([String].self, forKey: .originCountry)) ?? nil
        self.nextEpisodeToAir = (try? container.decodeIfPresent(Episode.self, forKey: .nextEpisodeToAir)) ?? nil
    }

    /// TMDB `status` 是英文枚举（v1.18）：界面其余部分是中文，这里翻译一道；
    /// 出现未知取值时原样显示，不吞信息。
    var statusLabel: String? {
        guard let status, !status.isEmpty else { return nil }
        switch status {
        case "Returning Series": return "连载中"
        case "Ended": return "已完结"
        case "Canceled": return "已取消"
        case "In Production": return "制作中"
        case "Planned": return "计划中"
        case "Pilot": return "试播"
        default: return status
        }
    }

    /// 是否已停更 / 完结（决定追更条要不要显示「已完结」）。
    var hasEnded: Bool {
        guard let status else { return false }
        return status == "Ended" || status == "Canceled"
    }

    /// 事实栏行（剧集：状态 / 首播 / 季数 / 集数 / 最近播出 / 语言）。
    var facts: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let statusLabel { rows.append((label: "状态", value: statusLabel)) }
        if let date = Formatters.fullDate(firstAirDate) { rows.append((label: "首播", value: date)) }
        if let seasons = numberOfSeasons { rows.append((label: "季数", value: "\(seasons)")) }
        if let episodes = numberOfEpisodes { rows.append((label: "集数", value: "\(episodes)")) }
        if let lastAirDate, let date = Formatters.fullDate(lastAirDate) { rows.append((label: "最近播出", value: date)) }
        if let originalLanguage { rows.append((label: "语言", value: originalLanguage)) }
        return rows
    }

    var libraryDetails: LibraryDetails { LibraryDetails(tv: self) }
}

/// 剧集某一季。
struct Season: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let episodeCount: Int?
    let voteAverage: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
        case airDate = "air_date"
        case episodeCount = "episode_count"
        case voteAverage = "vote_average"
    }

    init(id: Int, seasonNumber: Int, name: String? = nil, overview: String? = nil,
         posterPath: String? = nil, airDate: String? = nil, episodeCount: Int? = nil,
         voteAverage: Double? = nil) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.airDate = airDate
        self.episodeCount = episodeCount
        self.voteAverage = voteAverage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.seasonNumber = (try? container.decode(Int.self, forKey: .seasonNumber)) ?? 0
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.airDate = (try? container.decodeIfPresent(String.self, forKey: .airDate)) ?? nil
        self.episodeCount = (try? container.decodeIfPresent(Int.self, forKey: .episodeCount)) ?? nil
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return seasonNumber == 0 ? "特别篇" : "第 \(seasonNumber) 季"
    }
}

/// 剧集主创（`created_by`）。
struct Creator: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
    }

    init(id: Int, name: String, profilePath: String? = nil) {
        self.id = id
        self.name = name
        self.profilePath = profilePath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知"
        self.profilePath = (try? container.decodeIfPresent(String.self, forKey: .profilePath)) ?? nil
    }
}

/// 播出平台（networks）。
struct Network: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logoPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }

    init(id: Int, name: String, logoPath: String? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知"
        self.logoPath = (try? container.decodeIfPresent(String.self, forKey: .logoPath)) ?? nil
    }
}

/// 电影所属系列（`belongs_to_collection`，v1.19）：只带定位与展示所需字段。
struct CollectionSummary: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let posterPath: String?
    let backdropPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    init(id: Int, name: String, posterPath: String? = nil, backdropPath: String? = nil) {
        self.id = id
        self.name = name
        self.posterPath = posterPath
        self.backdropPath = backdropPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知系列"
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.backdropPath = (try? container.decodeIfPresent(String.self, forKey: .backdropPath)) ?? nil
    }
}

/// 系列详情（GET /3/collection/{id}，v1.19）。
///
/// `parts` 里的条目没有 `media_type`，`MediaSummary` 会按 `title` 字段推断为电影；
/// 个别旧片可能缺 `release_date`，因此排序时把无日期的放最后（不伪造年份）。
struct MovieCollection: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let parts: [MediaSummary]

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, parts
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    init(
        id: Int, name: String, overview: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, parts: [MediaSummary] = []
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.parts = parts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知系列"
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.backdropPath = (try? container.decodeIfPresent(String.self, forKey: .backdropPath)) ?? nil
        self.parts = (try? container.decodeIfPresent([MediaSummary].self, forKey: .parts)) ?? []
    }

    /// 按上映日期正序排列的系列作品（v1.19）：TMDB 的顺序基本可用，但缺日期的条目会被排到最后。
    var orderedParts: [MediaSummary] {
        parts.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.dateString, rhs.element.dateString) {
                case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l < r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
