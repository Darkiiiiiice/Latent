import Foundation
import Testing
@testable import Latent

/// 片库统计（纯本地计算，设计文档第 14.3 节）。
@Suite("片库统计")
struct LibraryStatisticsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func snapshot(
        id: Int,
        kind: MediaKind = .movie,
        title: String = "作品",
        year: Int? = 2020,
        rating: Double? = 7.5,
        addedAt: Date = Date(timeIntervalSince1970: 0),
        genres: [String] = [],
        runtime: Int? = nil,
        director: String? = nil,
        cast: [String] = [],
        countries: [String] = [],
        budget: Int64? = nil,
        revenue: Int64? = nil,
        voteCount: Int? = nil,
        enriched: Bool = true
    ) -> LibrarySnapshot {
        LibrarySnapshot(
            mediaKind: kind,
            tmdbID: id,
            title: title,
            originalTitle: nil,
            year: year,
            posterPath: nil,
            voteAverage: rating,
            addedAt: addedAt,
            genreNames: genres,
            runtime: runtime,
            director: director,
            topCast: cast,
            countries: countries,
            budget: budget,
            revenue: revenue,
            detailFetchedAt: enriched ? addedAt : nil,
            voteCount: voteCount
        )
    }

    @Test("收藏与清单重复条目合并去重，但各自计数保留")
    func dedupeAcrossLists() {
        let shared = snapshot(id: 1)
        let other = snapshot(id: 2)
        let stats = LibraryStatistics(
            favorites: [shared],
            watchlist: [shared, other],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.totalTitles == 2)
        #expect(stats.favoriteCount == 1)
        #expect(stats.watchlistCount == 2)
        #expect(stats.movieCount == 2)
        #expect(stats.tvCount == 0)
    }

    @Test("电影与剧集分别计数，时长只累计电影")
    func kindCountsAndRuntime() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, kind: .movie, runtime: 120),
                snapshot(id: 2, kind: .movie, runtime: 90),
                snapshot(id: 3, kind: .tv, runtime: 45, enriched: false)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.movieCount == 2)
        #expect(stats.tvCount == 1)
        #expect(stats.movieMinutes == 210)
        #expect(stats.pendingCount == 1)
    }

    @Test("年代按十年分桶并升序排列")
    func decadeBuckets() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, year: 1994),
                snapshot(id: 2, year: 1999),
                snapshot(id: 3, year: 2024),
                snapshot(id: 4, year: 2021),
                snapshot(id: 5, year: nil)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.decades.map(\.year) == [1990, 2020])
        #expect(stats.decades.map(\.count) == [2, 2])
    }

    @Test("评分向下取整并夹在 0…10")
    func ratingBuckets() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, rating: 8.9),
                snapshot(id: 2, rating: 8.0),
                snapshot(id: 3, rating: 7.99),
                snapshot(id: 4, rating: -1)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.ratings.first { $0.score == 8 }?.count == 2)
        #expect(stats.ratings.first { $0.score == 7 }?.count == 1)
        #expect(stats.ratings.first { $0.score == 0 }?.count == 1)
        #expect(stats.ratings.allSatisfy { (0...10).contains($0.score) })
    }

    @Test("入库趋势补齐最近 12 个月，范围外不计")
    func monthlyBuckets() {
        let now = date(2026, 10, 15)
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, addedAt: date(2026, 10, 2)),
                snapshot(id: 2, addedAt: date(2026, 9, 9)),
                snapshot(id: 3, addedAt: date(2026, 9, 20)),
                snapshot(id: 4, addedAt: date(2025, 1, 1))
            ],
            watchlist: [],
            now: now,
            calendar: calendar
        )
        #expect(stats.monthly.count == 12)
        #expect(stats.monthly.last?.count == 1)
        #expect(stats.monthly.dropLast().last?.count == 2)
        #expect(stats.monthly.reduce(0) { $0 + $1.count } == 3)
    }

    @Test("Top 榜按数量降序、同数量按名称升序，并截断到上限")
    func topRanking() {
        var favorites = (0..<12).map { index in
            snapshot(id: index + 1, director: "导演\(String(format: "%02d", index))")
        }
        // 导演11 出现两次，应排在榜首。
        favorites.append(snapshot(id: 99, director: "导演11"))

        let stats = LibraryStatistics(
            favorites: favorites,
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.directors.count == 10)
        #expect(stats.directors.first?.name == "导演11")
        #expect(stats.directors.first?.count == 2)
        // 同数量按名称升序：导演00 在导演01 之前。
        #expect(stats.directors[1].name == "导演00")
        #expect(stats.directors[2].name == "导演01")
    }

    @Test("预算与票房：两者都有正值才进入，按利润降序")
    func budgetRevenue() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, title: "小成本", budget: 10_000_000, revenue: 190_000_000),
                snapshot(id: 2, title: "大片", budget: 200_000_000, revenue: 300_000_000),
                snapshot(id: 3, title: "缺票房", budget: 50_000_000),
                snapshot(id: 4, title: "零预算", budget: 0, revenue: 80_000_000)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.budgetRevenue.map(\.title) == ["小成本", "大片"])
        #expect(stats.budgetRevenue.first?.profit == 180_000_000)
        #expect(stats.budgetRevenue.first?.ratio == 19)
    }

    @Test("观影护照按代码聚合、转中文名、跳过未知地区")
    func passportAggregation() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, countries: ["US", "CN"]),
                snapshot(id: 2, countries: ["us"]),
                snapshot(id: 3, countries: ["ZZ"]),
                snapshot(id: 4, countries: ["JP"])
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.passport.map(\.name) == ["美国", "中国", "日本"])
        #expect(stats.passport.map(\.count) == [2, 1, 1])
        // 未收录的地区不进入地图，但仍以代码形式出现在国家榜单里。
        #expect(stats.countries.first { $0.name == "ZZ" }?.count == 1)
    }

    @Test("榜单里的国家显示中文名")
    func countryDisplayName() {
        let stats = LibraryStatistics(
            favorites: [snapshot(id: 1, countries: ["US"]), snapshot(id: 2, countries: ["CN"])],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.countries.map(\.name) == ["中国", "美国"])
    }

    @Test("收藏时间轴从最早到最晚逐年展开，空缺年份补 0")
    func timelineRange() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, year: 1994),
                snapshot(id: 2, year: 1999),
                snapshot(id: 3, year: 2024)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.timeline.count == 31)
        #expect(stats.timeline.first?.year == 1994)
        #expect(stats.timeline.last?.year == 2024)
        #expect(stats.timeline.first { $0.year == 1999 }?.count == 1)
        #expect(stats.timeline.first { $0.year == 2000 }?.count == 0)
    }

    @Test("时间轴过滤异常年份；没有年份时为空")
    func timelineFiltersInvalidYears() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, year: 0),
                snapshot(id: 2, year: 1700),
                snapshot(id: 3, year: 2020)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.timeline.map(\.year) == [2020])

        let empty = LibraryStatistics(
            favorites: [snapshot(id: 1, year: nil)],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(empty.timeline.isEmpty)
    }

    @Test("雷达固定八维顺序，别名合并且同一作品不重复计数")
    func radarAxes() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, genres: ["科幻", "科幻奇幻", "剧情"]),
                snapshot(id: 2, genres: ["Sci-Fi & Fantasy", "Action"]),
                snapshot(id: 3, genres: ["爱情", "未知类型"])
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.radar.map(\.name) == ["科幻", "剧情", "喜剧", "恐怖", "动作", "爱情", "动画", "纪录片"])
        #expect(stats.radar.first { $0.name == "科幻" }?.count == 2)
        #expect(stats.radar.first { $0.name == "剧情" }?.count == 1)
        #expect(stats.radar.first { $0.name == "动作" }?.count == 1)
        #expect(stats.radar.first { $0.name == "爱情" }?.count == 1)
        #expect(stats.radar.first { $0.name == "喜剧" }?.count == 0)
    }

    @Test("空片库标记为空；空白名字不进入榜单")
    func emptyAndBlank() {
        let empty = LibraryStatistics(
            favorites: [],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(empty.isEmpty)
        #expect(empty.genres.isEmpty)

        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, genres: ["  ", "动作"], cast: ["  "], countries: [])
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.genres.map(\.name) == ["动作"])
        #expect(stats.cast.isEmpty)
        #expect(stats.countries.isEmpty)
    }

    @Test("口味画像：前三类型、最常看年代（同数量取更近）、平均分")
    func tasteProfileSummary() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, year: 1994, rating: 8.0, genres: ["剧情"]),
                snapshot(id: 2, year: 2019, rating: 7.0, genres: ["剧情", "动作"]),
                snapshot(id: 3, year: 2021, rating: 9.0, genres: ["动作", "科幻"])
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(Set(stats.taste.topGenres.prefix(2).map(\.name)) == ["剧情", "动作"])
        #expect(stats.taste.topGenres.last?.name == "科幻")
        #expect(stats.taste.favoriteDecade?.year == 2020)
        #expect(abs((stats.taste.averageRating ?? 0) - 8.0) < 0.001)
        #expect(stats.taste.poolIsWatchlist == false)
    }

    @Test("口味候选池优先观看清单，清单为空时退回片库")
    func tastePoolPreference() {
        let favorites = [
            snapshot(id: 1),
            snapshot(id: 2),
            snapshot(id: 3)
        ]
        let watchlistEmpty = LibraryStatistics(
            favorites: favorites,
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(Set(watchlistEmpty.taste.pool.map(\.id)) == ["movie-1", "movie-2", "movie-3"])
        #expect(watchlistEmpty.taste.poolIsWatchlist == false)

        let withWatchlist = LibraryStatistics(
            favorites: favorites,
            watchlist: [snapshot(id: 2)],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(withWatchlist.taste.pool.map(\.id) == ["movie-2"])
        #expect(withWatchlist.taste.poolIsWatchlist)
    }

    @Test("按口味随机：避开上一次、单条时原地返回、空池返回 nil")
    func tastePick() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, genres: ["动作"]),
                snapshot(id: 2, genres: ["剧情"])
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        var rng = SeededGenerator(seed: 7)
        #expect(stats.taste.pick(excluding: "movie-1", using: &rng)?.id == "movie-2")

        let single = LibraryStatistics(
            favorites: [snapshot(id: 1)],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        var singleRNG = SeededGenerator(seed: 1)
        #expect(single.taste.pick(excluding: "movie-1", using: &singleRNG)?.id == "movie-1")

        let empty = LibraryStatistics(
            favorites: [],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        var emptyRNG = SeededGenerator(seed: 1)
        #expect(empty.taste.pick(using: &emptyRNG) == nil)
    }

    @Test("命中偏好类型的条目权重更高")
    func tastePickFavorsPreferredGenres() {
        // 6 部动作（每部权重 1+2×1=3）+ 5 部各不相同的类型（多数权重 3、少数 1），
        // 命中偏好的概率明显高于均分（1/11 ≈ 9%），预期落在六成上下。
        var favorites: [LibrarySnapshot] = (1...6).map { snapshot(id: $0, genres: ["动作"]) }
        favorites += [
            snapshot(id: 7, genres: ["剧情"]),
            snapshot(id: 8, genres: ["喜剧"]),
            snapshot(id: 9, genres: ["恐怖"]),
            snapshot(id: 10, genres: ["纪录片"]),
            snapshot(id: 11, genres: ["动画"])
        ]
        let stats = LibraryStatistics(
            favorites: favorites,
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        var rng = SeededGenerator(seed: 42)
        var actionHit = 0
        for _ in 0..<200 {
            if stats.taste.pick(using: &rng)?.genreNames.contains("动作") == true {
                actionHit += 1
            }
        }
        #expect(actionHit > 80)
    }

    @Test("冷门指数：评分人数越少分数越高，按分数降序、只取前 6")
    func obscurityRanking() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, title: "大片", voteCount: 50_000),
                snapshot(id: 2, title: "冷门 A", voteCount: 12),
                snapshot(id: 3, title: "冷门 B", voteCount: 300),
                snapshot(id: 4, title: "中间", voteCount: 2_000)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.obscure.map(\.title) == ["冷门 A", "冷门 B", "中间", "大片"])
        #expect(stats.obscure.map(\.score) == stats.obscure.map(\.score).sorted(by: >))
        // 12 人评分 → 约 74 分；5 万人评分已超过「主流」基准，压到 0 分。
        #expect(stats.obscure.first?.score == 74)
        #expect(stats.obscure.last?.score == 0)
    }

    @Test("冷门指数：缺少 voteCount 的条目缺席，人数相同按标题稳定排序")
    func obscurityMissingData() {
        let stats = LibraryStatistics(
            favorites: [
                snapshot(id: 1, title: "B", voteCount: 5_000),
                snapshot(id: 2, title: "A", voteCount: 5_000),
                snapshot(id: 3, title: "无数据", voteCount: nil)
            ],
            watchlist: [],
            now: date(2026, 10, 15),
            calendar: calendar
        )
        #expect(stats.obscure.map(\.title) == ["A", "B"])
    }

    @Test("评分人数格式：千分位 / 万 / 亿")
    func voteCountFormatting() {
        #expect(Formatters.voteCount(32) == "32")
        #expect(Formatters.voteCount(1_234) == "1,234")
        #expect(Formatters.voteCount(23_456) == "2.3 万")
        #expect(Formatters.voteCount(120_000_000) == "1.2 亿")
    }
}

/// 可复现的随机源（xorshift64），避免统计类测试随系统随机数抖动。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
