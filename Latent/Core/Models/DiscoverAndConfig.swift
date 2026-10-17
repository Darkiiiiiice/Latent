import Foundation

/// 响应级缓存 TTL（设计文档第 4 节「缓存」）。
enum CacheTTL {
    /// configuration / genre list：30 天。
    static let settings: TimeInterval = 30 * 24 * 60 * 60
    /// 详情（含 append 数据、季详情）：7 天。
    static let detail: TimeInterval = 7 * 24 * 60 * 60
    /// 趋势：1 小时。
    static let trending: TimeInterval = 60 * 60
    /// 搜索：10 分钟。
    static let search: TimeInterval = 10 * 60
}

/// 发现页筛选条件（GET /3/discover/movie、/3/discover/tv）。
struct DiscoverQuery: Sendable, Equatable, Hashable {
    var genreIDs: Set<Int> = []
    var yearFrom: Int?
    var yearTo: Int?
    var minRating: Double?
    var sortBy: SortBy = .popularity

    enum SortBy: String, CaseIterable, Sendable, Hashable {
        case popularity = "popularity.desc"
        case rating = "vote_average.desc"
        case newest = "primary_release_date.desc"
        case oldest = "primary_release_date.asc"
        case revenue = "revenue.desc"

        var label: String {
            switch self {
            case .popularity: return "人气"
            case .rating: return "评分"
            case .newest: return "最新上映"
            case .oldest: return "最早上映"
            case .revenue: return "票房"
            }
        }
    }

    var isEmpty: Bool {
        genreIDs.isEmpty && yearFrom == nil && yearTo == nil && minRating == nil
    }
}

/// GET /3/configuration 的图片配置。
struct APIConfiguration: Codable, Sendable, Hashable {
    let baseURL: String?
    let posterSizes: [String]?
    let backdropSizes: [String]?
    let profileSizes: [String]?
    let stillSizes: [String]?

    private enum CodingKeys: String, CodingKey {
        case images
    }

    private enum ImageKeys: String, CodingKey {
        case secureBaseURL = "secure_base_url"
        case posterSizes = "poster_sizes"
        case backdropSizes = "backdrop_sizes"
        case profileSizes = "profile_sizes"
        case stillSizes = "still_sizes"
    }

    init(baseURL: String? = nil, posterSizes: [String]? = nil, backdropSizes: [String]? = nil,
         profileSizes: [String]? = nil, stillSizes: [String]? = nil) {
        self.baseURL = baseURL
        self.posterSizes = posterSizes
        self.backdropSizes = backdropSizes
        self.profileSizes = profileSizes
        self.stillSizes = stillSizes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let images = try container.nestedContainer(keyedBy: ImageKeys.self, forKey: .images)
        self.baseURL = (try? images.decodeIfPresent(String.self, forKey: .secureBaseURL)) ?? nil
        self.posterSizes = (try? images.decodeIfPresent([String].self, forKey: .posterSizes)) ?? nil
        self.backdropSizes = (try? images.decodeIfPresent([String].self, forKey: .backdropSizes)) ?? nil
        self.profileSizes = (try? images.decodeIfPresent([String].self, forKey: .profileSizes)) ?? nil
        self.stillSizes = (try? images.decodeIfPresent([String].self, forKey: .stillSizes)) ?? nil
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var images = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .images)
        try images.encodeIfPresent(baseURL, forKey: .secureBaseURL)
        try images.encodeIfPresent(posterSizes, forKey: .posterSizes)
        try images.encodeIfPresent(backdropSizes, forKey: .backdropSizes)
        try images.encodeIfPresent(profileSizes, forKey: .profileSizes)
        try images.encodeIfPresent(stillSizes, forKey: .stillSizes)
    }

    /// 兜底默认值（验证通过但配置缺字段时使用；实际以 configuration 响应为准）。
    static let fallback = APIConfiguration(baseURL: "https://image.tmdb.org/t/p/")
}

/// 类型列表响应（GET /3/genre/movie/list、/3/genre/tv/list）。
struct GenreListResponse: Codable, Sendable, Hashable {
    let genres: [Genre]

    init(genres: [Genre]) {
        self.genres = genres
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.genres = (try? container.decodeIfPresent([Genre].self, forKey: .genres)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case genres }
}
