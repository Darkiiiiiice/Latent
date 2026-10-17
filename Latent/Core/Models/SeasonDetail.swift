import Foundation

/// 季详情（GET /3/tv/{id}/season/{n}）——含分集明细。
struct SeasonDetail: Decodable, Sendable {
    let id: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let episodes: [Episode]?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, episodes
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
        case airDate = "air_date"
    }

    init(id: Int, seasonNumber: Int, name: String? = nil, overview: String? = nil,
         posterPath: String? = nil, airDate: String? = nil, episodes: [Episode]? = nil) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.airDate = airDate
        self.episodes = episodes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.seasonNumber = (try? container.decode(Int.self, forKey: .seasonNumber)) ?? 0
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.airDate = (try? container.decodeIfPresent(String.self, forKey: .airDate)) ?? nil
        self.episodes = (try? container.decodeIfPresent([Episode].self, forKey: .episodes)) ?? nil
    }
}

/// 单集：标题 / 集号 / 播出日期 / 时长 / 评分 / 简介（有则显示，缺则优雅降级）。
struct Episode: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let airDate: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case airDate = "air_date"
        case stillPath = "still_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    init(id: Int, episodeNumber: Int, seasonNumber: Int? = nil, name: String? = nil,
         overview: String? = nil, airDate: String? = nil, stillPath: String? = nil,
         voteAverage: Double? = nil, voteCount: Int? = nil, runtime: Int? = nil) {
        self.id = id
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.stillPath = stillPath
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.runtime = runtime
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        self.episodeNumber = (try? container.decode(Int.self, forKey: .episodeNumber)) ?? 0
        self.seasonNumber = (try? container.decodeIfPresent(Int.self, forKey: .seasonNumber)) ?? nil
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.airDate = (try? container.decodeIfPresent(String.self, forKey: .airDate)) ?? nil
        self.stillPath = (try? container.decodeIfPresent(String.self, forKey: .stillPath)) ?? nil
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        self.voteCount = (try? container.decodeIfPresent(Int.self, forKey: .voteCount)) ?? nil
        self.runtime = (try? container.decodeIfPresent(Int.self, forKey: .runtime)) ?? nil
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "第 \(episodeNumber) 集"
    }
}
