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

    @Test("发现端点：时长上限只对电影下发，上映日期排序在剧集换成首播日期")
    func discoverRuntimeAndTVSort() {
        var query = DiscoverQuery()
        query.maxRuntime = 90

        let movieItems = URLComponents(
            url: EndpointURLBuilder.url(for: .discover(mediaKind: .movie, query: query, page: 1), language: "zh-CN"),
            resolvingAgainstBaseURL: false
        )!.queryItems!
        #expect(movieItems.contains { $0.name == "with_runtime.lte" && $0.value == "90" })

        // 剧集端点没有 `with_runtime` 参数。
        let tvItems = URLComponents(
            url: EndpointURLBuilder.url(for: .discover(mediaKind: .tv, query: query, page: 1), language: "zh-CN"),
            resolvingAgainstBaseURL: false
        )!.queryItems!
        #expect(!tvItems.contains { $0.name == "with_runtime.lte" })

        query.maxRuntime = nil
        query.sortBy = .newest
        let tvSorted = URLComponents(
            url: EndpointURLBuilder.url(for: .discover(mediaKind: .tv, query: query, page: 1), language: "zh-CN"),
            resolvingAgainstBaseURL: false
        )!.queryItems!
        #expect(tvSorted.contains { $0.name == "sort_by" && $0.value == "first_air_date.desc" })

        let movieSorted = URLComponents(
            url: EndpointURLBuilder.url(for: .discover(mediaKind: .movie, query: query, page: 1), language: "zh-CN"),
            resolvingAgainstBaseURL: false
        )!.queryItems!
        #expect(movieSorted.contains { $0.name == "sort_by" && $0.value == "primary_release_date.desc" })
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

/// 一句话筛选：本地规则解析（`NLQueryParser`）。
@Suite("一句话筛选")
struct NLQueryParserTests {

    private let genres = Genre.samples
    private let providers = WatchProvider.samples

    private func parse(_ text: String, base: DiscoverQuery = DiscoverQuery(), mediaKind: MediaKind = .movie) -> NLQueryParser.Result {
        NLQueryParser.parse(text, genres: genres, providers: providers, base: base, mediaKind: mediaKind)
    }

    @Test("「90 分钟以内的科幻片」→ 科幻 + 时长上限 90")
    func runtimeAndGenre() {
        let result = parse("90 分钟以内的科幻片")
        #expect(result.query.genreIDs == [878])
        #expect(result.query.maxRuntime == 90)
        #expect(result.mediaKind == nil)
        #expect(result.matched == ["科幻", "≤90 分钟"])
    }

    @Test("「评分 8 分以上的 2020 年后动作片」→ 类型 + 年份 + 评分下限")
    func ratingAndYear() {
        let result = parse("评分 8 分以上的 2020 年后动作片")
        #expect(result.query.genreIDs == [28])
        #expect(result.query.yearFrom == 2020)
        #expect(result.query.yearTo == nil)
        #expect(result.query.minRating == 8.0)
        #expect(result.matched == ["动作", "2020 年后", "评分 ≥8"])
    }

    @Test("「高低分」写法：高分给下限，低于 6 分给上限")
    func looseRatingPhrases() {
        #expect(parse("高分的科幻片").query.minRating == 7.5)
        #expect(parse("低于 6 分的喜剧").query.maxRating == 6.0)
    }

    @Test("年份：年代区间与四位数区间")
    func yearForms() {
        let decade = parse("90 年代的老片")
        #expect(decade.query.yearFrom == 1990)
        #expect(decade.query.yearTo == 1999)
        // 「老片」同时被识别为排序偏好，这不冲突。
        #expect(decade.query.sortBy == .oldest)

        let range = parse("2020-2024 的悬疑片")
        #expect(range.query.genreIDs == [9648])
        #expect(range.query.yearFrom == 2020)
        #expect(range.query.yearTo == 2024)
    }

    @Test("时长：中文数字与小时换算")
    func runtimeForms() {
        #expect(parse("两小时以内").query.maxRuntime == 120)
        #expect(parse("一个半小时").query.maxRuntime == 90)
        #expect(parse("100 分钟以内的电影").query.maxRuntime == 100)
    }

    @Test("「5 分钟以内」不得被当成评分区间")
    func runtimeIsNotRating() {
        let result = parse("5 分钟以内")
        #expect(result.query.minRating == nil)
        #expect(result.query.maxRating == nil)
    }

    @Test("平台：英文名与中文别名都能命中")
    func providerNames() {
        // 中文别名经 `providerAliases` 映射到英文名后再匹配已加载清单。
        let alias = parse("网飞上的科幻片", mediaKind: .movie)
        #expect(alias.query.providerIDs == [8])

        let extra = [WatchProvider(providerID: 169, providerName: "iQIYI", logoPath: nil, displayPriority: 1)]
        let chinese = NLQueryParser.parse("爱奇艺的喜剧", genres: genres, providers: extra)
        #expect(chinese.query.providerIDs == [169])
    }

    @Test("排序：高分 → 评分最高；剧集句子里点名作品类型")
    func sortAndMediaKind() {
        let high = parse("高分最新的")
        #expect(high.query.minRating == 7.5)
        #expect(high.query.sortBy == .rating)

        let tv = parse("近年的高分剧集")
        #expect(tv.mediaKind == .tv)
        #expect(tv.query.sortBy == .rating)

        // 剧集不支持按时长筛选，命中说明里会点出来。
        let tvRuntime = parse("90 分钟以内的剧集")
        #expect(tvRuntime.mediaKind == .tv)
        #expect(tvRuntime.query.maxRuntime == 90)
        #expect(tvRuntime.matched.contains { $0.contains("剧集不支持") })
    }

    @Test("未提及的条件保持 base 值不变")
    func keepsBase() {
        var base = DiscoverQuery()
        base.minRating = 7.0
        base.yearFrom = 2015
        base.sortBy = .revenue

        let result = parse("科幻片", base: base)
        #expect(result.query.genreIDs == [878])
        #expect(result.query.minRating == 7.0)
        #expect(result.query.yearFrom == 2015)
        #expect(result.query.sortBy == .revenue)
    }

    @Test("识别不出条件：matched 为空，query 原样返回")
    func unrecognized() {
        var base = DiscoverQuery()
        base.maxRating = 8.0
        let result = parse("随便看看", base: base)
        #expect(result.isEmpty)
        #expect(result.query == base)
        #expect(result.mediaKind == nil)
    }

    @Test("空输入不崩，按未识别处理")
    func emptyInput() {
        #expect(parse("").isEmpty)
        #expect(parse("   \n").isEmpty)
        #expect(parse("").query == DiscoverQuery())
    }
}

