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
struct DiscoverQuery: Codable, Sendable, Equatable, Hashable {
    var genreIDs: Set<Int> = []
    var yearFrom: Int?
    var yearTo: Int?
    var minRating: Double?
    /// 评分上限（含）。
    var maxRating: Double?
    /// 流媒体平台（TMDB `provider_id`，多选取并集）。
    var providerIDs: Set<Int> = []
    /// 观看地区（ISO 3166-1 alpha-2）；平台可用性按地区划分，随筛选一起保存。
    var region: String = DiscoverQuery.defaultRegion
    /// 时长上限（分钟，含）。TMDB 只对电影支持 `with_runtime`，剧集侧忽略此条件。
    var maxRuntime: Int?
    var sortBy: SortBy = .popularity

    enum SortBy: String, Codable, CaseIterable, Sendable, Hashable {
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

        /// 请求用的排序值：电影按上映日期，剧集端点对应的字段是首播日期。
        func rawValue(for mediaKind: MediaKind) -> String {
            switch (self, mediaKind) {
            case (.newest, .tv): return "first_air_date.desc"
            case (.oldest, .tv): return "first_air_date.asc"
            default: return rawValue
            }
        }
    }

    /// 是否设置了「会真正收窄结果」的条件。
    ///
    /// 观看地区不算条件——它只在选择了平台时才参与请求，单独改地区不改变结果集。
    var isEmpty: Bool {
        genreIDs.isEmpty && yearFrom == nil && yearTo == nil
            && minRating == nil && maxRating == nil && providerIDs.isEmpty
            && maxRuntime == nil
    }

    // MARK: - 观看地区（TMDB `watch_region`）

    static let defaultRegion = "CN"

    /// 平台可用性按地区划分；这里只列常见地区，中文名由 `CountryDirectory` 提供。
    static let regions: [String] = [
        "CN", "HK", "TW", "JP", "KR", "SG", "US", "GB", "CA", "AU", "DE", "FR"
    ]

    // MARK: - 摘要文本

    /// 「电影 · 科幻+动作 · 2010–2024 · 评分 ≤7.0 · 平台 2 个」——保存快捷入口时的默认名字。
    ///
    /// 类型与平台的中文名由调用方查表传入（两者都依赖当前已加载的列表）。
    func summaryLabel(genreNames: [Int: String] = [:], providerNames: [Int: String] = [:]) -> String {
        var parts: [String] = []

        if !genreIDs.isEmpty {
            let names = genreIDs.sorted().map { genreNames[$0] ?? "类型\($0)" }
            parts.append(names.joined(separator: "+"))
        }

        switch (yearFrom, yearTo) {
        case let (from?, to?): parts.append("\(from)–\(to)")
        case let (from?, nil): parts.append("\(from) 年后")
        case let (nil, to?): parts.append("\(to) 年前")
        case (nil, nil): break
        }

        switch (minRating, maxRating) {
        case let (min?, max?): parts.append("评分 \(min)–\(max)")
        case let (min?, nil): parts.append("评分 ≥\(min)")
        case let (nil, max?): parts.append("评分 ≤\(max)")
        case (nil, nil): break
        }

        if !providerIDs.isEmpty {
            let names = providerIDs.sorted().compactMap { providerNames[$0] }
            parts.append(names.isEmpty ? "平台 \(providerIDs.count) 个" : names.joined(separator: "+"))
        }

        if let maxRuntime {
            parts.append("≤\(maxRuntime) 分钟")
        }

        if parts.isEmpty {
            parts.append(sortBy.label)
        }
        return parts.joined(separator: " · ")
    }
}

/// 发现页筛选快捷入口（UserDefaults 持久化，见 `AppSettings`）。
struct DiscoverPreset: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var mediaKind: MediaKind
    var query: DiscoverQuery
    var createdAt: Date = Date()
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
