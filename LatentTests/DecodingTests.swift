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
        // 海报比例（0.667）的 backdrop 不应进入剧照 rail（fixture 里有两张横图）
        #expect(detail.images?.stills.count == 2)
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

    @Test("剧集追更：next_episode_to_air 与状态中文化")
    func tvNextEpisode() throws {
        let detail = try decoder.decode(TVShowDetail.self, from: Fixtures.data("tv_detail"))
        let next = try #require(detail.nextEpisodeToAir)
        #expect(next.airDate == "2026-01-05")
        #expect(next.seasonNumber == 5)
        #expect(next.episodeNumber == 5)
        #expect(next.displayName == "第一章：地狱火俱乐部")

        // 状态在 UI 里说中文；未知取值原样保留。
        #expect(detail.statusLabel == "连载中")
        #expect(detail.hasEnded == false)
        #expect(detail.facts.first?.value == "连载中")
    }

    @Test("电影详情：belongs_to_collection 定位系列（v1.19）")
    func movieCollectionLink() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        let collection = try #require(detail.belongsToCollection)
        #expect(collection.id == 726871)
        #expect(collection.name == "沙丘合集")
        #expect(collection.posterPath == "/lr11mCT85T1JanlgjMqgMhtEDby.jpg")
    }

    @Test("系列详情：parts 推断为电影；缺上映日期的排在最后")
    func collection() throws {
        let collection = try decoder.decode(MovieCollection.self, from: Fixtures.data("collection"))
        #expect(collection.id == 726871)
        #expect(collection.name == "沙丘合集")
        #expect(collection.parts.count == 3)
        #expect(collection.parts.allSatisfy { $0.mediaKind == .movie })

        // fixture 里第三部 release_date 为 null，应被排到末尾。
        let ordered = collection.orderedParts
        #expect(ordered.map(\.id) == [438631, 693134, 999001])
        #expect(ordered.last?.dateString == nil)
    }

    @Test("发行信息：分地区解析、过滤空地区、CN 优先（v1.20）")
    func releaseDates() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        let regions = detail.releaseRegions

        // JP 没有发行记录，整条被过滤掉。
        #expect(regions.map(\.code) == ["CN", "US", "GB"])

        // CN 无分级（空串按缺失处理），摘要只给日期。
        #expect(regions[0].certification == nil)
        #expect(regions[0].summary == "2024 年 3 月 8 日")

        // US 两条记录：院线 + 数字，带分级与备注。
        #expect(regions[1].certification == "PG-13")
        #expect(regions[1].entries.map(\.typeLabel) == ["院线", "数字"])
        #expect(regions[1].entries[1].summary == "数字 · 2024 年 3 月 12 日 · 导演剪辑版")

        #expect(detail.defaultReleaseRegion == "CN")
    }

    @Test("发行信息：无 release_dates 时为空且默认地区为 nil")
    func releaseDatesMissing() throws {
        let json = #"{"id": 1, "title": "独立电影"}"#
        let detail = try decoder.decode(MovieDetail.self, from: Data(json.utf8))
        #expect(detail.releaseDates == nil)
        #expect(detail.releaseRegions.isEmpty)
        #expect(detail.defaultReleaseRegion == nil)
    }

    @Test("发行类型：未知编号退化为「其它」，时间戳取日期部分")
    func releaseEntryHelpers() {
        let entry = ReleaseDateEntry(releaseDate: "2024-02-27T00:00:00.000Z", type: 99, note: "")
        #expect(entry.dayString == "2024-02-27")
        #expect(entry.typeLabel == "其它")

        let bare = ReleaseDateEntry(releaseDate: "2024-02-27", type: 3)
        #expect(bare.dayString == "2024-02-27")
        #expect(ReleaseDateEntry(releaseDate: nil).dayString == nil)
    }

    @Test("制作公司：详情里的 production_companies 解析（v1.21）")
    func movieProductionCompanies() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        let companies = try #require(detail.productionCompanies)
        #expect(companies.map(\.id) == [923, 174])
        #expect(companies.map(\.name) == ["传奇影业", "华纳兄弟影业"])
        #expect(companies[0].logoPath == "/8M99D8wDWbZmyLWZB2O19kxW1Jn.png")
        #expect(companies[1].logoPath == nil)
        #expect(companies[0].countryName != nil)
    }

    @Test("公司详情：总部 / 官网 / 母公司解析；缺字段不崩（v1.21）")
    func companyDetail() throws {
        let company = try decoder.decode(CompanyDetail.self, from: Fixtures.data("company"))
        #expect(company.id == 923)
        #expect(company.name == "传奇影业")
        #expect(company.headquarters == "美国加利福尼亚州伯班克")
        #expect(company.homepage?.absoluteString == "https://www.legendary.com")
        #expect(company.logoPath == "/8M99D8wDWbZmyLWZB2O19kxW1Jn.png")
        #expect(company.parentCompany?.name == "传奇娱乐")
        #expect(company.biography == "传奇影业是一家美国影视制作公司，以《沙丘》《哥斯拉》等系列著称。")

        let minimal = try decoder.decode(CompanyDetail.self, from: Data(#"{"id": 9, "description": "   "}"#.utf8))
        #expect(minimal.name == "未知公司")
        #expect(minimal.biography == nil)
        #expect(minimal.homepage == nil)
        #expect(minimal.parentCompany == nil)
        #expect(minimal.countryName == nil)
    }

    @Test("图片画廊：剧照 / 海报过滤与说明行（v1.22）")
    func imageGallery() throws {
        let detail = try decoder.decode(MovieDetail.self, from: Fixtures.data("movie_detail"))
        let images = try #require(detail.images)

        // 竖版 backdrop 不进剧照；1:1 的 poster 不进海报画廊。
        #expect(images.allStills.count == 2)
        #expect(images.allStills.map(\.filePath) == ["/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg", "/stillTwo.jpg"])
        #expect(images.stills.count == 2)
        #expect(images.galleryPosters.count == 3)
        #expect(images.galleryPosters.map(\.filePath) == ["/posterZh.jpg", "/posterNoText.jpg", "/posterEn.jpg"])

        let first = try #require(images.allStills.first)
        #expect(first.sizeLabel == "3840 × 2160")
        // 无语言标注按「无文字」处理（TMDB 用 null 表示图上没有文字）。
        #expect(first.galleryCaption == "3840 × 2160 · 无文字")
        #expect(first.languageLabel == nil)

        let translated = try #require(images.allStills.last)
        #expect(translated.languageLabel != nil)
        #expect(translated.galleryCaption?.hasPrefix("3000 × 2000 · ") == true)

        // 既无尺寸也无语言时不显示说明行。
        let bare = ImageAsset(filePath: "/bare.jpg")
        #expect(bare.galleryCaption == nil)
        #expect(bare.languageLabel == nil)
    }

    @Test("影评：作者回退 / 外部头像剔除 / 空白正文与非法时间容错（v1.23）")
    func reviews() throws {
        let page = try decoder.decode(Paged<Review>.self, from: Fixtures.data("reviews"))
        #expect(page.items.count == 3)
        #expect(page.page == 1)
        #expect(page.isLastPage)

        let first = page.items[0]
        #expect(first.id == "5f8a1b2c3d4e5f6a7b8c9d0e")
        #expect(first.displayAuthor == "影迷老王")
        #expect(first.ratingText == "9.0")
        #expect(first.relativeCreatedText != nil) // 带毫秒的时间戳也能解析
        #expect(first.url?.absoluteString == "https://www.themoviedb.org/review/5f8a1b2c3d4e5f6a7b8c9d0e")
        #expect(!first.isLong)

        let second = page.items[1]
        // name 为 null → 退回 username。
        #expect(second.displayAuthor == "quiet_observer")
        #expect(second.avatarPath == "/avatar.jpg")
        #expect(second.ratingText == nil)
        #expect(second.relativeCreatedText != nil) // 不带毫秒的时间戳

        let third = page.items[2]
        // 缺 id：用「作者 + 时间」兜底，保证 ForEach 可去重。
        #expect(third.id.hasPrefix("gravatar_user#"))
        #expect(third.displayAuthor == "外部头像")
        // gravatar 绝对地址不进图片管线。
        #expect(third.avatarPath == nil)
        #expect(third.bodyText == nil)            // 全空白正文
        #expect(third.relativeCreatedText == nil) // 非法时间
        #expect(third.url == nil)                 // 空串 url
        #expect(!third.isLong)
    }

    @Test("系列详情：缺 parts / 缺 id 不崩")
    func collectionTolerance() throws {
        let empty = try decoder.decode(MovieCollection.self, from: Data(#"{"name":"空系列"}"#.utf8))
        #expect(empty.parts.isEmpty)
        #expect(empty.id == 0)
        #expect(empty.orderedParts.isEmpty)
    }

    @Test("剧集追更：缺 next_episode_to_air 不报错")
    func tvWithoutNextEpisode() throws {
        // movie_detail.json 里没有该字段；换成 TV 端点数据的最小形态验证可选性。
        let json = """
        {"id": 1, "name": "无下一集", "status": "Ended", "number_of_seasons": 2, "number_of_episodes": 18}
        """
        let detail = try decoder.decode(TVShowDetail.self, from: Data(json.utf8))
        #expect(detail.nextEpisodeToAir == nil)
        #expect(detail.statusLabel == "已完结")
        #expect(detail.hasEnded)
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
