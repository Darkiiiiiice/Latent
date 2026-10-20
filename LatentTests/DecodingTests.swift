import Foundation
import Testing
@testable import Latent

/// fixture 离线解码（设计文档 P0：用 fixture JSON 离线跑通端点解码）。
@Suite("DTO 解码容错")
struct DecodingTests {

    private let decoder = JSONDecoder()

    @Test("configuration：图片基准地址与尺寸")
    func configuration() throws {
        let config = try decoder.decode(APIConfiguration.self, from: Fixtures.data("configuration"))
        #expect(config.baseURL == "https://image.tmdb.org/t/p/")
        #expect(config.posterSizes?.contains("w342") == true)
        #expect(config.stillSizes?.contains("w780") == true)
    }

    @Test("多类型搜索：电影 / 剧集 / 人物分组；缺 media_type 推断；字段缺失容错")
    func searchMulti() throws {
        let page = try decoder.decode(Paged<SearchResult>.self, from: Fixtures.data("search_multi"))

        #expect(page.page == 1)
        #expect(page.totalPages == 12)
        #expect(page.items.count == 4)
        #expect(page.isLastPage == false)

        guard case .movie(let interstellar) = page.items[0] else {
            Issue.record("第 1 条应为电影")
            return
        }
        #expect(interstellar.title == "星际穿越")
        #expect(interstellar.originalTitle == "Interstellar")
        #expect(interstellar.year == 2014)
        #expect(interstellar.voteAverage == 8.447)

        guard case .tv(let stranger) = page.items[1] else {
            Issue.record("第 2 条应为剧集")
            return
        }
        #expect(stranger.title == "怪奇物语")
        #expect(stranger.dateString == "2016-07-15")

        guard case .person(let waddingham) = page.items[2] else {
            Issue.record("第 3 条应人物")
            return
        }
        #expect(waddingham.name == "Hannah Waddingham")
        #expect(waddingham.knownForDepartment == "Acting")

        // 第 4 条：无 media_type；有 title → 推断为电影；空日期与 nil 字段不崩溃
        guard case .movie(let inferred) = page.items[3] else {
            Issue.record("第 4 条应按 title 推断为电影")
            return
        }
        #expect(inferred.mediaKind == .movie)
        #expect(inferred.year == nil)
        #expect(inferred.posterPath == nil)
    }

    @Test("趋势：分页与末页判定")
    func trending() throws {
        let page = try decoder.decode(Paged<MediaSummary>.self, from: Fixtures.data("trending_movie_day"))
        #expect(page.items.count == 2)
        #expect(page.totalPages == 3)
        #expect(page.items[0].title == "头脑特工队2")
    }

    @Test("电影详情：fact 字段、导演、剧照过滤、外部 ID")
    func movieDetail() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        #expect(detail.title == "沙丘：第二部")
        #expect(detail.runtime == 166)
        #expect(detail.budget == 190_000_000)
        #expect(detail.revenue == 714_444_358)
        #expect(detail.credits?.directors.first?.name == "丹尼斯·维伦纽瓦")
        #expect(detail.externalIDs?.imdbID == "tt15239678")
        // 海报比例（0.667）的 backdrop 不应进入剧照 rail（fixture 里只有一张 1.778）
        #expect(detail.images?.stills.count == 1)
        #expect(detail.similar?.count == 1)
        #expect(detail.recommendations?.count == 1)
        #expect(detail.watchProviders?.region(for: nil)?.code == "CN")

        let facts = detail.facts
        #expect(facts.contains { $0.label == "时长" && $0.value == "2 小时 46 分" })
        #expect(facts.contains { $0.label == "预算" && $0.value == "$190M" })
    }

    @Test("剧集详情：季列表与季号")
    func tvDetail() throws {
        let detail = try decoder.decode(TVShowDetail.self, from: Fixtures.data("tv_detail"))
        #expect(detail.name == "怪奇物语")
        #expect(detail.numberOfSeasons == 4)
        #expect(detail.numberOfEpisodes == 34)
        #expect(detail.seasons?.count == 3)
        #expect(detail.seasons?[0].displayName == "第 1 季")
        #expect(detail.seasons?[2].displayName == "特别篇")
        #expect(detail.lastAirDate == "2022-07-01")
        #expect(detail.createdBy?.first?.name == "Duffer Brothers")
        #expect(detail.watchProviders?.region(for: nil)?.code == "US")
    }

    @Test("观看平台：地区排序、跳过空地区、分组去重")
    func watchProviders() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        let providers = try #require(detail.watchProviders)

        // JP 只有 link、没有渠道，不进入地区菜单。
        #expect(providers.availableRegions.map(\.code) == ["CN", "US"])
        #expect(providers.region(for: nil)?.code == "CN")
        #expect(providers.region(for: "US")?.code == "US")
        #expect(providers.region(for: "JP")?.code == "CN") // 无渠道 → 回退默认
        #expect(providers.region(for: "ZZ")?.code == "CN")

        let cn = try #require(providers.region(for: "CN"))
        #expect(cn.region.groups.map(\.kind) == [.stream, .rent])
        #expect(cn.region.groups[0].providers.map(\.providerName) == ["爱奇艺"])
        #expect(cn.region.link?.absoluteString.contains("locale=CN") == true)

        let us = try #require(providers.region(for: "US"))
        #expect(us.region.groups.map(\.kind) == [.stream, .buy])
        // free 与 ads 里的同一个平台合并，只出现一次；按 display_priority 排序。
        #expect(us.region.groups[0].providers.map(\.providerName) == ["YouTube", "Netflix"])
    }

    @Test("观看平台：空结果时整段隐藏")
    func watchProvidersEmpty() {
        let providers = WatchProviders(results: ["CN": WatchRegion()])
        #expect(providers.availableRegions.isEmpty)
        #expect(providers.region(for: nil) == nil)
    }

    @Test("分集：缺简介 / 缺剧照 / 部分字段缺失均不崩溃")
    func seasonEpisodes() throws {
        let season = try decoder.decode(SeasonDetail.self, from: Fixtures.data("tv_season"))
        #expect(season.episodes?.count == 3)

        let first = season.episodes![0]
        #expect(first.displayName == "威尔·拜尔斯失踪")
        #expect(first.stillPath == "/x.jpg")
        #expect(first.runtime == 49)

        let second = season.episodes![1]
        #expect(second.displayName == "第 2 集") // name 为空 → 回退集号
        #expect(second.overview?.isEmpty == true)
        #expect(second.stillPath == nil)
        #expect(second.runtime == nil)
        #expect(second.voteAverage == 0)

        let third = season.episodes![2] // 仅有集号
        #expect(third.displayName == "第 3 集")
        #expect(third.airDate == nil)
    }

    @Test("人物：作品年表去重、过滤人物条目、按日期降序")
    func personCredits() throws {
        let person = try decoder.decode(PersonDetail.self, from: Fixtures.data("person_detail"))
        #expect(person.name == "提莫西·查拉梅")
        #expect(person.lifeText == "1995-12-27")

        let filmography = person.combinedCredits?.filmography ?? []
        #expect(filmography.count == 2) // 电影 1 条（重复合并）+ 剧集 1 条；person 条目被过滤
        #expect(filmography[0].title == "沙丘：第二部") // 2024 排在 2022 前面
        #expect(filmography[1].mediaKind == .tv)
    }

    @Test("未知 media_type 兜底为 unknown")
    func unknownMediaKind() {
        #expect(MediaKind(tmdbValue: "person") == .person)
        #expect(MediaKind(tmdbValue: "collection") == .unknown)
        #expect(MediaKind(tmdbValue: nil) == .unknown)
        #expect(MediaKind(tmdbValue: "TV") == .tv)
    }

    @Test("缺字段的页面响应：容错为第 1 页 / 空结果")
    func emptyPage() throws {
        let page = try decoder.decode(Paged<MediaSummary>.self, from: Data("{}".utf8))
        #expect(page.page == 1)
        #expect(page.items.isEmpty)
        #expect(page.totalPages == 1)
        #expect(page.isLastPage == true)
    }
}
