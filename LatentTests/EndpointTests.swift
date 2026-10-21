import Foundation
import Testing
@testable import Latent

/// Endpoint URL 与参数编码（设计文档第 11 节测试点）。
@Suite("Endpoint 编码")
struct EndpointTests {

    @Test("详情端点：append_to_response 与 include_image_language")
    func movieDetailQuery() {
        let url = EndpointURLBuilder.url(for: .movieDetail(id: 693134), language: "zh-CN")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!

        #expect(url.path == "/3/movie/693134")
        #expect(items.contains { $0.name == "language" && $0.value == "zh-CN" })
        #expect(items.contains { $0.name == "append_to_response" && $0.value == "credits,images,similar,recommendations,external_ids,release_dates,watch/providers" })
        #expect(items.contains { $0.name == "include_image_language" && $0.value == "zh,en,null" })
    }

    @Test("剧集详情端点：append 含观看平台")
    func tvDetailQuery() {
        let url = EndpointURLBuilder.url(for: .tvDetail(id: 66732), language: "zh-CN")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!

        #expect(url.path == "/3/tv/66732")
        #expect(items.contains {
            $0.name == "append_to_response"
                && $0.value == "credits,images,similar,recommendations,external_ids,content_ratings,watch/providers"
        })
    }

    @Test("搜索端点：query、分页、include_adult")
    func searchQuery() {
        let url = EndpointURLBuilder.url(for: .searchMulti(query: "沙丘 第二部", page: 3), language: "zh-CN")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!

        #expect(url.path == "/3/search/multi")
        #expect(items.contains { $0.name == "query" && $0.value == "沙丘 第二部" })
        #expect(items.contains { $0.name == "page" && $0.value == "3" })
        #expect(items.contains { $0.name == "include_adult" && $0.value == "false" })
    }

    @Test("趋势端点：路径含媒体类型与时间窗")
    func trendingPath() {
        let url = EndpointURLBuilder.url(for: .trending(mediaKind: .tv, window: .week), language: "en-US")
        #expect(url.path == "/3/trending/tv/week")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains { $0.name == "language" && $0.value == "en-US" })
    }

    @Test("发现端点：剧集用 first_air_date，电影用 primary_release_date")
    func discoverDateFields() {
        var query = DiscoverQuery()
        query.genreIDs = [878, 12]
        query.yearFrom = 2020
        query.yearTo = 2024
        query.minRating = 7.0

        let movieURL = EndpointURLBuilder.url(for: .discover(mediaKind: .movie, query: query, page: 1), language: "zh-CN")
        let movieItems = URLComponents(url: movieURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(movieItems.contains { $0.name == "primary_release_date.gte" && $0.value == "2020-01-01" })
        #expect(movieItems.contains { $0.name == "primary_release_date.lte" && $0.value == "2024-12-31" })
        #expect(movieItems.contains { $0.name == "with_genres" && $0.value == "12,878" })
        #expect(movieItems.contains { $0.name == "vote_count.gte" })

        let tvURL = EndpointURLBuilder.url(for: .discover(mediaKind: .tv, query: query, page: 1), language: "zh-CN")
        let tvItems = URLComponents(url: tvURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(tvItems.contains { $0.name == "first_air_date.gte" && $0.value == "2020-01-01" })
    }

    @Test("发现端点：评分上限与观看平台（平台必须带地区）")
    func discoverRatingAndProviders() {
        var query = DiscoverQuery()
        query.minRating = 7.0
        query.maxRating = 8.5
        query.providerIDs = [8, 337]
        query.region = "CN"

        let url = EndpointURLBuilder.url(for: .discover(mediaKind: .movie, query: query, page: 1), language: "zh-CN")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!

        #expect(items.contains { $0.name == "vote_average.gte" && $0.value == "7.0" })
        #expect(items.contains { $0.name == "vote_average.lte" && $0.value == "8.5" })
        // 平台 ID 按数值排序；`URLComponents` 会把并集分隔符 `|` 百分号编码（服务端照常解码）。
        #expect(items.contains { $0.name == "with_watch_providers" && $0.value?.removingPercentEncoding == "8|337" })
        #expect(items.contains { $0.name == "watch_region" && $0.value == "CN" })
        #expect(items.contains { $0.name == "with_watch_monetization_types" && $0.value?.removingPercentEncoding == "flatrate|free|ads" })

        // 未选平台时不应带地区（TMDB 要求两者同时出现）。
        var bare = DiscoverQuery()
        bare.region = "CN"
        let bareURL = EndpointURLBuilder.url(for: .discover(mediaKind: .movie, query: bare, page: 1), language: "zh-CN")
        let bareItems = URLComponents(url: bareURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(!bareItems.contains { $0.name == "watch_region" })
        #expect(!bareItems.contains { $0.name == "with_watch_providers" })
    }

    @Test("平台清单端点：路径与 watch_region")
    func watchProvidersEndpoint() {
        let movieURL = EndpointURLBuilder.url(for: .watchProviders(mediaKind: .movie, region: "CN"), language: "zh-CN")
        #expect(movieURL.path == "/3/watch/providers/movie")
        let items = URLComponents(url: movieURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains { $0.name == "watch_region" && $0.value == "CN" })
        #expect(items.contains { $0.name == "language" && $0.value == "zh-CN" })

        #expect(EndpointURLBuilder.url(for: .watchProviders(mediaKind: .tv, region: "US"), language: "zh-CN").path == "/3/watch/providers/tv")
    }

    @Test("季详情与类型列表路径")
    func seasonAndGenrePaths() {
        #expect(EndpointURLBuilder.url(for: .tvSeason(id: 66732, seasonNumber: 2), language: "zh-CN").path == "/3/tv/66732/season/2")
        #expect(EndpointURLBuilder.url(for: .genreList(mediaKind: .tv), language: "zh-CN").path == "/3/genre/tv/list")
        let config = EndpointURLBuilder.url(for: .configuration, language: "zh-CN")
        #expect(config.path == "/3/configuration")
        #expect(URLComponents(url: config, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }

    @Test("同一请求产出稳定 URL（缓存键依赖）")
    func stableURL() {
        let first = EndpointURLBuilder.url(for: .movieDetail(id: 1), language: "zh-CN")
        let second = EndpointURLBuilder.url(for: .movieDetail(id: 1), language: "zh-CN")
        #expect(first == second)
    }
}

/// 缓存键（SHA256）。
@Suite("缓存键")
struct CacheKeyTests {

    @Test("响应缓存键 = 完整 URL 哈希")
    func responseKey() {
        let url = EndpointURLBuilder.url(for: .trending(mediaKind: .movie, window: .day), language: "zh-CN")
        let key = CacheKey.responseKey(for: url)
        #expect(key.count == 64) // SHA256 hex
        #expect(key != CacheKey.responseKey(for: url.appending(queryItems: [.init(name: "page", value: "2")])))
    }

    @Test("图片缓存键含尺寸，同文件不同尺寸不同键")
    func imageKey() {
        let small = CacheKey.imageKey(path: "/abc.jpg", pixelSize: 185)
        let large = CacheKey.imageKey(path: "/abc.jpg", pixelSize: 1280)
        #expect(small != large)
    }
}

/// 发现页筛选条件与快捷入口。
@Suite("发现页筛选")
struct DiscoverQueryTests {

    @Test("isEmpty：只认真正收窄结果的条件，单独改地区不算")
    func isEmpty() {
        var query = DiscoverQuery()
        #expect(query.isEmpty)

        query.region = "US"
        #expect(query.isEmpty) // 未选平台时地区不参与请求

        query.providerIDs = [8]
        #expect(!query.isEmpty)

        query.providerIDs = []
        query.maxRating = 8.0
        #expect(!query.isEmpty)
    }

    @Test("摘要文本：类型 → 年份 → 评分 → 平台，全空回退排序名")
    func summaryLabel() {
        var query = DiscoverQuery()
        #expect(query.summaryLabel() == "人气")

        query.genreIDs = [878, 12]
        query.yearFrom = 2010
        query.yearTo = 2024
        query.maxRating = 7.0
        query.providerIDs = [8]

        let label = query.summaryLabel(genreNames: [878: "科幻", 12: "冒险"], providerNames: [8: "Netflix"])
        #expect(label == "冒险+科幻 · 2010–2024 · 评分 ≤7.0 · Netflix")

        // 查不到中文名时回退为「平台 N 个」，不显示数字 ID。
        var unknown = DiscoverQuery()
        unknown.providerIDs = [8, 337]
        #expect(unknown.summaryLabel() == "平台 2 个")
    }

    @Test("快捷入口：UUID 与查询条件经 JSON 往返不丢失")
    func presetRoundTrip() throws {
        var query = DiscoverQuery()
        query.genreIDs = [878]
        query.minRating = 7.0
        query.maxRating = 9.0
        query.providerIDs = [8, 337]
        query.region = "HK"
        query.sortBy = .rating
        let preset = DiscoverPreset(name: "科幻高分", mediaKind: .tv, query: query)

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(DiscoverPreset.self, from: data)

        #expect(decoded == preset)
        #expect(decoded.mediaKind == .tv)
        #expect(decoded.query.region == "HK")
        #expect(decoded.query.sortBy == .rating)
    }
}
