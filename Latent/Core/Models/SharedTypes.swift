import Foundation

/// 详情页共用的最小字段集合（电影与剧集详情一致的部分）。
protocol MediaDetail: Sendable {
    var id: Int { get }
    var mediaKind: MediaKind { get }
    var title: String { get }
    var originalTitle: String? { get }
    var overview: String? { get }
    var posterPath: String? { get }
    var backdropPath: String? { get }
    /// 发布日期（电影：release_date；剧集：first_air_date）。
    var dateString: String? { get }
    var voteAverage: Double? { get }
    var voteCount: Int? { get }
    var genres: [Genre]? { get }
    var tagline: String? { get }
    var status: String? { get }
    var originalLanguage: String? { get }
    var homepage: URL? { get }
    var externalIDs: ExternalIDs? { get }
    var credits: Credits? { get }
    var images: MediaImages? { get }
    var similar: [MediaSummary]? { get }
    var recommendations: [MediaSummary]? { get }
    /// 观看平台（append_to_response=watch/providers）。
    var watchProviders: WatchProviders? { get }
    /// 事实栏行（各详情类型自带）。
    var facts: [(label: String, value: String)] { get }

    /// 写入片库时一并保存的富化字段（统计页用；设计文档第 6 / 14.3 节）。
    var libraryDetails: LibraryDetails { get }

    var year: Int? { get }
    var ratingText: String? { get }
}

extension MediaDetail {
    var year: Int? { Formatters.year(from: dateString) }
    var ratingText: String? { Formatters.rating(voteAverage) }
}

/// 类型（genre）。
struct Genre: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知类型"
    }

    private enum CodingKeys: String, CodingKey { case id, name }
}

/// 制片国家 / 地区（详情里的 `production_countries`，含名称便于展示）。
struct ProductionCountry: Codable, Sendable, Hashable {
    let iso3166_1: String
    let name: String

    init(iso3166_1: String, name: String = "") {
        self.iso3166_1 = iso3166_1
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iso3166_1 = ((try? container.decodeIfPresent(String.self, forKey: .iso3166_1)) ?? nil) ?? ""
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case iso3166_1 = "iso_3166_1"
    }
}

/// 外链标识。
struct ExternalIDs: Codable, Sendable, Hashable {
    let imdbID: String?
    let wikidataID: String?
    let instagramID: String?
    let twitterID: String?

    init(imdbID: String? = nil, wikidataID: String? = nil, instagramID: String? = nil, twitterID: String? = nil) {
        self.imdbID = imdbID
        self.wikidataID = wikidataID
        self.instagramID = instagramID
        self.twitterID = twitterID
    }

    private enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
        case wikidataID = "wikidata_id"
        case instagramID = "instagram_id"
        case twitterID = "twitter_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.imdbID = Self.clean((try? container.decodeIfPresent(String.self, forKey: .imdbID)) ?? nil)
        self.wikidataID = Self.clean((try? container.decodeIfPresent(String.self, forKey: .wikidataID)) ?? nil)
        self.instagramID = Self.clean((try? container.decodeIfPresent(String.self, forKey: .instagramID)) ?? nil)
        self.twitterID = Self.clean((try? container.decodeIfPresent(String.self, forKey: .twitterID)) ?? nil)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// 演职员（credits 子结构）。
struct Credits: Codable, Sendable, Hashable {
    let cast: [CastMember]?
    let crew: [CrewMember]?

    init(cast: [CastMember]? = nil, crew: [CrewMember]? = nil) {
        self.cast = cast
        self.crew = crew
    }

    private enum CodingKeys: String, CodingKey { case cast, crew }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cast = (try? container.decodeIfPresent([CastMember].self, forKey: .cast)) ?? nil
        self.crew = (try? container.decodeIfPresent([CrewMember].self, forKey: .crew)) ?? nil
    }

    /// 导演（剧集为主创；过滤空名单）。
    var directors: [CrewMember] {
        (crew ?? []).filter { $0.job == "Director" || $0.job == "Creator" }
    }
}

/// 演员（含角色）。
struct CastMember: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?

    var characterOrNil: String? {
        guard let character, !character.isEmpty else { return nil }
        return character
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }

    init(id: Int, name: String, character: String? = nil, profilePath: String? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.profilePath = profilePath
        self.order = order
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "（无名）"
        self.character = (try? container.decodeIfPresent(String.self, forKey: .character)) ?? nil
        self.profilePath = (try? container.decodeIfPresent(String.self, forKey: .profilePath)) ?? nil
        self.order = (try? container.decodeIfPresent(Int.self, forKey: .order)) ?? nil
    }
}

/// 职员（导演出自这里）。
struct CrewMember: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let job: String?
    let department: String?
    let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, job, department
        case profilePath = "profile_path"
    }

    init(id: Int, name: String, job: String? = nil, department: String? = nil, profilePath: String? = nil) {
        self.id = id
        self.name = name
        self.job = job
        self.department = department
        self.profilePath = profilePath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "（无名）"
        self.job = (try? container.decodeIfPresent(String.self, forKey: .job)) ?? nil
        self.department = (try? container.decodeIfPresent(String.self, forKey: .department)) ?? nil
        self.profilePath = (try? container.decodeIfPresent(String.self, forKey: .profilePath)) ?? nil
    }
}

/// 图片集合（append_to_response=images）。
struct MediaImages: Codable, Sendable, Hashable {
    let backdrops: [ImageAsset]?
    let posters: [ImageAsset]?
    let logos: [ImageAsset]?

    private enum CodingKeys: String, CodingKey { case backdrops, posters, logos }

    init(backdrops: [ImageAsset]? = nil, posters: [ImageAsset]? = nil, logos: [ImageAsset]? = nil) {
        self.backdrops = backdrops
        self.posters = posters
        self.logos = logos
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backdrops = (try? container.decodeIfPresent([ImageAsset].self, forKey: .backdrops)) ?? nil
        self.posters = (try? container.decodeIfPresent([ImageAsset].self, forKey: .posters)) ?? nil
        self.logos = (try? container.decodeIfPresent([ImageAsset].self, forKey: .logos)) ?? nil
    }

    /// 剧照 rail（按宽高比过滤掉海报比例图，最多 20 张）。
    var stills: [ImageAsset] {
        (backdrops ?? [])
            .filter { ($0.aspectRatio ?? 1.78) >= 1.5 }
            .prefix(20)
            .map { $0 }
    }
}

/// 单张图片。
struct ImageAsset: Codable, Sendable, Identifiable, Hashable {
    let filePath: String
    let width: Int?
    let height: Int?
    let aspectRatio: Double?
    let voteAverage: Double?
    let language: String?

    var id: String { filePath }

    private enum CodingKeys: String, CodingKey {
        case width, height, language
        case filePath = "file_path"
        case aspectRatio = "aspect_ratio"
        case voteAverage = "vote_average"
    }

    init(filePath: String, width: Int? = nil, height: Int? = nil, aspectRatio: Double? = nil, voteAverage: Double? = nil, language: String? = nil) {
        self.filePath = filePath
        self.width = width
        self.height = height
        self.aspectRatio = aspectRatio
        self.voteAverage = voteAverage
        self.language = language
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.width = (try? container.decodeIfPresent(Int.self, forKey: .width)) ?? nil
        self.height = (try? container.decodeIfPresent(Int.self, forKey: .height)) ?? nil
        self.aspectRatio = (try? container.decodeIfPresent(Double.self, forKey: .aspectRatio)) ?? nil
        self.voteAverage = (try? container.decodeIfPresent(Double.self, forKey: .voteAverage)) ?? nil
        self.language = (try? container.decodeIfPresent(String.self, forKey: .language)) ?? nil
    }
}
