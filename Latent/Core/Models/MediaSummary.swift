import Foundation

/// 精简作品（趋势、搜索、相似 / 推荐、库条目共用的最小结构）。
///
/// 设计原则（第 4 节）：全字段 optional，缺字段不导致整条记录解码失败。
/// 只解码不编码（缓存保存原始 JSON Data），因此只声明 `Decodable`。
struct MediaSummary: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let mediaKind: MediaKind
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    /// 电影用 release_date，剧集用 first_air_date，统一为 `yyyy-MM-dd`。
    let dateString: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIDs: [Int]?

    var year: Int? { Formatters.year(from: dateString) }

    /// 供库条目（收藏 / 清单 / 历史）写入的初始快照。
    var hasPoster: Bool { posterPath?.isEmpty == false }

    /// 用详情数据回填（标题随语言切换会变；详情比列表更完整）。
    func resolved<Detail: MediaDetail>(from detail: Detail) -> MediaSummary {
        MediaSummary(
            id: detail.id,
            mediaKind: detail.mediaKind,
            title: detail.title,
            originalTitle: detail.originalTitle,
            overview: detail.overview ?? overview,
            posterPath: detail.posterPath ?? posterPath,
            backdropPath: detail.backdropPath ?? backdropPath,
            dateString: detail.dateString ?? dateString,
            voteAverage: detail.voteAverage ?? voteAverage,
            voteCount: detail.voteCount ?? voteCount,
            popularity: popularity,
            genreIDs: detail.genres?.map(\.id) ?? genreIDs
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIDs = "genre_ids"
    }

    init(
        id: Int,
        mediaKind: MediaKind,
        title: String,
        originalTitle: String? = nil,
        overview: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        dateString: String? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil,
        popularity: Double? = nil,
        genreIDs: [Int]? = nil
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.dateString = dateString
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.genreIDs = genreIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)

        // media_type 缺省时按标题字段推断（多类型搜索里有明确值；相似 / 推荐接口没有）。
        let rawType = try? container.decodeIfPresent(String.self, forKey: .mediaType)
        if let rawType, !rawType.isEmpty {
            self.mediaKind = MediaKind(tmdbValue: rawType)
        } else {
            let hasMovieTitle = (try? container.decodeIfPresent(String.self, forKey: .title)) != nil
            self.mediaKind = hasMovieTitle ? .movie : .tv
        }

        let title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        let name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.title = title ?? name ?? "（无标题）"

        self.originalTitle = ((try? container.decodeIfPresent(String.self, forKey: .originalTitle)) ?? nil)
            ?? ((try? container.decodeIfPresent(String.self, forKey: .originalName)) ?? nil)
        self.overview = (try? container.decodeIfPresent(String.self, forKey: .overview)) ?? nil
        self.posterPath = (try? container.decodeIfPresent(String.self, forKey: .posterPath)) ?? nil
        self.backdropPath = (try? container.decodeIfPresent(String.self, forKey: .backdropPath)) ?? nil
        let release = (try? container.decodeIfPresent(String.self, forKey: .releaseDate)) ?? nil
        let air = (try? container.decodeIfPresent(String.self, forKey: .firstAirDate)) ?? nil
        self.dateString = (release?.isEmpty == false ? release : nil) ?? (air?.isEmpty == false ? air : nil)
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        self.voteCount = (try? container.decodeIfPresent(Int.self, forKey: .voteCount)) ?? nil
        self.popularity = (try? container.decodeIfPresent(Double.self, forKey: .popularity)) ?? nil
        self.genreIDs = (try? container.decodeIfPresent([Int].self, forKey: .genreIDs)) ?? nil
    }
}

extension Collection where Element == MediaSummary {
    /// 「来一部」：随机挑一部；列表多于一条时避开上一部，避免连点两次开同一部。
    func randomPick(excluding previous: MediaSummary?) -> MediaSummary? {
        guard !isEmpty else { return nil }
        guard count > 1, let previous else { return randomElement() }
        let others = filter { !($0.id == previous.id && $0.mediaKind == previous.mediaKind) }
        return others.randomElement() ?? randomElement()
    }
}

/// 人物精简信息（多类型搜索的分组结果用）。
struct PersonSummary: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }

    init(id: Int, name: String, profilePath: String? = nil, knownForDepartment: String? = nil) {
        self.id = id
        self.name = name
        self.profilePath = profilePath
        self.knownForDepartment = knownForDepartment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "（无名）"
        self.profilePath = (try? container.decodeIfPresent(String.self, forKey: .profilePath)) ?? nil
        self.knownForDepartment = (try? container.decodeIfPresent(String.self, forKey: .knownForDepartment)) ?? nil
    }
}

/// 多类型搜索结果的一项（三态单值解码）。
enum SearchResult: Sendable, Identifiable, Hashable {
    case movie(MediaSummary)
    case tv(MediaSummary)
    case person(PersonSummary)

    var id: String {
        switch self {
        case .movie(let s): return "movie-\(s.id)"
        case .tv(let s): return "tv-\(s.id)"
        case .person(let p): return "person-\(p.id)"
        }
    }
}

extension SearchResult: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MediaSummary.CodingKeys.self)
        let rawType = (try? container.decodeIfPresent(String.self, forKey: .mediaType)) ?? nil
        switch MediaKind(tmdbValue: rawType) {
        case .person:
            self = .person(try PersonSummary(from: decoder))
        case .tv:
            self = .tv(try MediaSummary(from: decoder))
        default:
            self = .movie(try MediaSummary(from: decoder))
        }
    }
}
