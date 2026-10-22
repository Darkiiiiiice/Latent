import Foundation

/// 客户端抽象：视图与 Store 只依赖此协议（便于 MockClient / 预览 / 单测）。
protocol TMDBClientProtocol: Sendable {
    func validateToken() async throws -> APIConfiguration
    func trending(mediaKind: MediaKind, window: Endpoint.TrendingWindow, page: Int) async throws -> Paged<MediaSummary>
    func searchMulti(query: String, page: Int) async throws -> Paged<SearchResult>
    func movieDetail(id: Int) async throws -> MovieDetail
    func tvDetail(id: Int) async throws -> TVShowDetail
    func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetail
    func personDetail(id: Int) async throws -> PersonDetail
    func collection(id: Int) async throws -> MovieCollection
    func company(id: Int) async throws -> CompanyDetail
    func reviews(mediaKind: MediaKind, id: Int, page: Int) async throws -> Paged<Review>
    func discover(mediaKind: MediaKind, query: DiscoverQuery, page: Int) async throws -> Paged<MediaSummary>
    func genreList(mediaKind: MediaKind) async throws -> [Genre]
    func watchProviders(mediaKind: MediaKind, region: String) async throws -> [WatchProvider]
}

extension TMDBClient {
    // 默认参数不便写在协议里，这里提供便捷重载。
    func trending(mediaKind: MediaKind, window: Endpoint.TrendingWindow) async throws -> Paged<MediaSummary> {
        try await trending(mediaKind: mediaKind, window: window, page: 1)
    }

    func searchMulti(query: String) async throws -> Paged<SearchResult> {
        try await searchMulti(query: query, page: 1)
    }

    func discover(mediaKind: MediaKind, query: DiscoverQuery) async throws -> Paged<MediaSummary> {
        try await discover(mediaKind: mediaKind, query: query, page: 1)
    }
}

/// 预览 / 单测用的假客户端：返回合成数据，不发网络请求。
struct MockTMDBClient: TMDBClientProtocol {
    var configuration = APIConfiguration.fallback
    var trendingPage = Paged(page: 1, items: MediaSummary.samples(count: 12, kind: .movie), totalPages: 3, totalResults: 36)
    var searchPage = Paged(page: 1, items: MockTMDBClient.sampleSearchResults, totalPages: 1, totalResults: 3)
    var movie: MovieDetail = .sample
    var show: TVShowDetail = .sample
    var season: SeasonDetail = .sample
    var person: PersonDetail = .sample
    var collection: MovieCollection = .sample
    var company: CompanyDetail = .sample
    var reviewsPage = Paged(page: 1, items: Review.samples, totalPages: 1, totalResults: Review.samples.count)
    var discoverPage = Paged(page: 1, items: MediaSummary.samples(count: 18, kind: .movie), totalPages: 2, totalResults: 36)
    var genres: [Genre] = Genre.samples
    var providers: [WatchProvider] = WatchProvider.samples
    /// 置为非空时，`searchMulti` 抛出该错误（单测「搜索失败不崩」用）。
    var searchError: APIError?

    func validateToken() async throws -> APIConfiguration { configuration }
    func trending(mediaKind: MediaKind, window: Endpoint.TrendingWindow, page: Int) async throws -> Paged<MediaSummary> { trendingPage }
    func searchMulti(query: String, page: Int) async throws -> Paged<SearchResult> {
        if let searchError { throw searchError }
        return searchPage
    }
    func movieDetail(id: Int) async throws -> MovieDetail { movie }
    func tvDetail(id: Int) async throws -> TVShowDetail { show }
    func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetail { season }
    func personDetail(id: Int) async throws -> PersonDetail { person }
    func collection(id: Int) async throws -> MovieCollection { collection }
    func company(id: Int) async throws -> CompanyDetail { company }
    func reviews(mediaKind: MediaKind, id: Int, page: Int) async throws -> Paged<Review> { reviewsPage }
    func discover(mediaKind: MediaKind, query: DiscoverQuery, page: Int) async throws -> Paged<MediaSummary> { discoverPage }
    func genreList(mediaKind: MediaKind) async throws -> [Genre] { genres }
    func watchProviders(mediaKind: MediaKind, region: String) async throws -> [WatchProvider] { providers }

    static var sampleSearchResults: [SearchResult] {
        [
            .movie(.sampleMovie(id: 1, title: "沙丘：第二部")),
            .tv(.sampleShow(id: 2, title: "怪奇物语")),
            .person(PersonSummary(id: 287, name: "布拉德·皮特", knownForDepartment: "Acting")),
        ]
    }
}

// MARK: - 预览 / 测试用合成数据

extension MediaSummary {
    static func sampleMovie(id: Int, title: String) -> MediaSummary {
        MediaSummary(
            id: id, mediaKind: .movie, title: title,
            originalTitle: title, overview: "这是一段用于预览的简介。",
            posterPath: nil, backdropPath: nil,
            dateString: "2024-03-01", voteAverage: 8.1, voteCount: 4210,
            popularity: 100, genreIDs: [878, 12]
        )
    }

    static func sampleShow(id: Int, title: String) -> MediaSummary {
        MediaSummary(
            id: id, mediaKind: .tv, title: title,
            originalTitle: title, overview: "这是一段用于预览的简介。",
            posterPath: nil, backdropPath: nil,
            dateString: "2016-07-15", voteAverage: 8.6, voteCount: 15000,
            popularity: 90, genreIDs: [18, 9648]
        )
    }

    static func samples(count: Int, kind: MediaKind) -> [MediaSummary] {
        (0..<count).map { index in
            kind == .tv
                ? .sampleShow(id: index + 100, title: "示例剧集 \(index + 1)")
                : .sampleMovie(id: index + 1, title: "示例电影 \(index + 1)")
        }
    }
}

extension Genre {
    static let samples: [Genre] = [
        Genre(id: 28, name: "动作"), Genre(id: 12, name: "冒险"),
        Genre(id: 878, name: "科幻"), Genre(id: 18, name: "剧情"),
        Genre(id: 35, name: "喜剧"), Genre(id: 9648, name: "悬疑"),
    ]
}

extension WatchProvider {
    static let samples: [WatchProvider] = [
        WatchProvider(providerID: 8, providerName: "Netflix", logoPath: "/netflix.jpg", displayPriority: 0),
        WatchProvider(providerID: 337, providerName: "Disney+", logoPath: "/disney.jpg", displayPriority: 1),
        WatchProvider(providerID: 1899, providerName: "HBO Max", logoPath: "/hbo.jpg", displayPriority: 2),
    ]
}

extension Review {
    static let samples: [Review] = [
        Review(
            id: "a1", author: "filmnerd",
            authorDetails: ReviewAuthor(name: "影迷老王", username: "filmnerd", avatarPath: nil, rating: 9),
            content: "维伦纽瓦把沙丘拍成了一场仪式。沙虫出场那一幕，整个影厅都屏住了呼吸。",
            createdAt: "2024-03-05T10:00:00.000Z", url: URL(string: "https://www.themoviedb.org/review/a1")
        ),
        Review(
            id: "a2", author: "quiet_observer",
            authorDetails: ReviewAuthor(name: nil, username: "quiet_observer", avatarPath: "/avatar.jpg", rating: nil),
            content: "视效与音效都是顶级，但节奏比第一部更慢。喜欢的人会觉得是史诗，不喜欢的人会觉得是折磨。",
            createdAt: "2024-03-01T08:30:00.000Z"
        ),
    ]
}

extension MovieDetail {
    static let sample = MovieDetail(
        id: 693134, title: "沙丘：第二部", originalTitle: "Dune: Part Two",
        overview: "保罗·厄崔迪与契妮和弗雷曼人并肩作战，踏上复仇之路。",
        posterPath: nil, backdropPath: nil, dateString: "2024-02-27",
        voteAverage: 8.1, voteCount: 4210, genres: Genre.samples,
        tagline: "长路漫漫", status: "已上映", originalLanguage: "en",
        externalIDs: ExternalIDs(imdbID: "tt15239678"),
        credits: Credits(cast: [
            CastMember(id: 1190668, name: "提莫西·查拉梅", character: "保罗·厄崔迪"),
            CastMember(id: 1373737, name: "赞达亚", character: "契妮"),
        ], crew: [CrewMember(id: 137427, name: "丹尼斯·维伦纽瓦", job: "Director")]),
        similar: MediaSummary.samples(count: 8, kind: .movie),
        recommendations: MediaSummary.samples(count: 10, kind: .movie),
        runtime: 166, budget: 190_000_000, revenue: 714_000_000
    )
}

extension TVShowDetail {
    static let sample = TVShowDetail(
        id: 66732, name: "怪奇物语", originalName: "Stranger Things",
        overview: "小镇少年发现超自然事件背后的秘密实验室。",
        firstAirDate: "2016-07-15", voteAverage: 8.6, voteCount: 15000,
        genres: Genre.samples, status: "已回归", originalLanguage: "en",
        numberOfSeasons: 4, numberOfEpisodes: 34,
        seasons: [
            Season(id: 1, seasonNumber: 1, name: "第 1 季", episodeCount: 8, voteAverage: 8.3),
            Season(id: 2, seasonNumber: 2, name: "第 2 季", episodeCount: 9, voteAverage: 8.0),
        ],
        episodeRunTime: [50], lastAirDate: "2022-07-01"
    )
}

extension SeasonDetail {
    static let sample = SeasonDetail(
        id: 1, seasonNumber: 1, name: "第 1 季", airDate: "2016-07-15",
        episodes: (1...8).map { number in
            Episode(
                id: number, episodeNumber: number, seasonNumber: 1,
                name: "第 \(number) 集", overview: number % 3 == 0 ? nil : "分集简介示例。",
                airDate: "2016-07-1\(number % 10)", stillPath: nil,
                voteAverage: 7.5 + Double(number) * 0.1, voteCount: 1000, runtime: 48
            )
        }
    )
}

extension PersonDetail {
    static let sample = PersonDetail(
        id: 1190668, name: "提莫西·查拉梅",
        biography: "美国演员，因《请以你的名字呼唤我》获得奥斯卡提名。",
        birthday: "1995-12-27", placeOfBirth: "美国纽约",
        knownForDepartment: "Acting",
        combinedCredits: CombinedCredits(cast: MediaSummary.samples(count: 12, kind: .movie))
    )
}

extension CompanyDetail {
    static let sample = CompanyDetail(
        id: 3_474, name: "传奇影业",
        description: "传奇影业是一家美国影视制作公司，以《沙丘》《哥斯拉》等系列著称。",
        headquarters: "美国加利福尼亚州伯班克",
        homepage: URL(string: "https://www.legendary.com"),
        originCountry: "US",
        parentCompany: ProductionCompany(id: 1, name: "传奇娱乐")
    )
}

extension MovieCollection {
    static let sample = MovieCollection(
        id: 726_871, name: "沙丘系列",
        overview: "保罗·厄崔迪的复仇与崛起。",
        parts: [
            MediaSummary(id: 438_631, mediaKind: .movie, title: "沙丘", dateString: "2021-10-22", voteAverage: 7.8),
            MediaSummary(id: 693_134, mediaKind: .movie, title: "沙丘：第二部", dateString: "2024-02-27", voteAverage: 8.1),
            MediaSummary(id: 999_001, mediaKind: .movie, title: "沙丘：救世主", dateString: "2027-03-18", voteAverage: nil),
        ]
    )
}
