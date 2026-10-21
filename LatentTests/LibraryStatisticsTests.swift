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
            detailFetchedAt: enriched ? addedAt : nil
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
}
