import Foundation

/// 电影详情（GET /3/movie/{id}，append_to_response=credits,images,similar,recommendations,external_ids,release_dates）。
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
    let runtime: Int?
    let budget: Int?
    let revenue: Int?

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
        case credits, images, similar, recommendations
    }

    init(
        id: Int, title: String, originalTitle: String? = nil, overview: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, dateString: String? = nil,
        voteAverage: Double? = nil, voteCount: Int? = nil, genres: [Genre]? = nil,
        tagline: String? = nil, status: String? = nil, originalLanguage: String? = nil,
        homepage: URL? = nil, externalIDs: ExternalIDs? = nil, credits: Credits? = nil,
        images: MediaImages? = nil, similar: [MediaSummary]? = nil,
        recommendations: [MediaSummary]? = nil, runtime: Int? = nil,
        budget: Int? = nil, revenue: Int? = nil
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
        self.runtime = runtime
        self.budget = budget
        self.revenue = revenue
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
        self.runtime = (try? container.decodeIfPresent(Int.self, forKey: .runtime)) ?? nil
        self.budget = (try? container.decodeIfPresent(Int.self, forKey: .budget)) ?? nil
        self.revenue = (try? container.decodeIfPresent(Int.self, forKey: .revenue)) ?? nil
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
}

/// 剧集详情（GET /3/tv/{id}，append_to_response=credits,images,similar,recommendations,external_ids,content_ratings）。
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
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [Season]?
    let episodeRunTime: [Int]?
    let lastAirDate: String?
    let networks: [Network]?
    /// 主创（TMDB `created_by`；与分集导演是两回事）。
    let createdBy: [Creator]?

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
        case credits, images, similar, recommendations
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case lastAirDate = "last_air_date"
        case createdBy = "created_by"
    }

    init(
        id: Int, name: String, originalName: String? = nil, overview: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, firstAirDate: String? = nil,
        voteAverage: Double? = nil, voteCount: Int? = nil, genres: [Genre]? = nil,
        tagline: String? = nil, status: String? = nil, originalLanguage: String? = nil,
        homepage: URL? = nil, externalIDs: ExternalIDs? = nil, credits: Credits? = nil,
        images: MediaImages? = nil, similar: [MediaSummary]? = nil,
        recommendations: [MediaSummary]? = nil, numberOfSeasons: Int? = nil,
        numberOfEpisodes: Int? = nil, seasons: [Season]? = nil,
        episodeRunTime: [Int]? = nil, lastAirDate: String? = nil,
        networks: [Network]? = nil, createdBy: [Creator]? = nil
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
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.seasons = seasons
        self.episodeRunTime = episodeRunTime
        self.lastAirDate = lastAirDate
        self.networks = networks
        self.createdBy = createdBy
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
        self.numberOfSeasons = (try? container.decodeIfPresent(Int.self, forKey: .numberOfSeasons)) ?? nil
        self.numberOfEpisodes = (try? container.decodeIfPresent(Int.self, forKey: .numberOfEpisodes)) ?? nil
        self.seasons = (try? container.decodeIfPresent([Season].self, forKey: .seasons)) ?? nil
        self.episodeRunTime = (try? container.decodeIfPresent([Int].self, forKey: .episodeRunTime)) ?? nil
        self.lastAirDate = (try? container.decodeIfPresent(String.self, forKey: .lastAirDate)) ?? nil
        self.networks = (try? container.decodeIfPresent([Network].self, forKey: .networks)) ?? nil
        self.createdBy = (try? container.decodeIfPresent([Creator].self, forKey: .createdBy)) ?? nil
    }

    /// 事实栏行（剧集：状态 / 首播 / 季数 / 集数 / 最近播出 / 语言）。
    var facts: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let status { rows.append((label: "状态", value: status)) }
        if let date = Formatters.fullDate(firstAirDate) { rows.append((label: "首播", value: date)) }
        if let seasons = numberOfSeasons { rows.append((label: "季数", value: "\(seasons)")) }
        if let episodes = numberOfEpisodes { rows.append((label: "集数", value: "\(episodes)")) }
        if let lastAirDate, let date = Formatters.fullDate(lastAirDate) { rows.append((label: "最近播出", value: date)) }
        if let originalLanguage { rows.append((label: "语言", value: originalLanguage)) }
        return rows
    }
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
