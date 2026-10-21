import Foundation

/// 片库统计（设计文档第 14.3 节）。
///
/// 全部字段由本地快照计算，不发网络请求；未富化的旧条目在对应维度上自然缺席，
/// 视图用 `pendingCount` 提示还剩多少条待回填。
struct LibraryStatistics: Sendable, Equatable {
    struct Slice: Identifiable, Sendable, Equatable {
        let name: String
        let count: Int
        var id: String { name }
    }

    struct YearBucket: Identifiable, Sendable, Equatable {
        let year: Int
        let count: Int
        var id: Int { year }
    }

    struct RatingBucket: Identifiable, Sendable, Equatable {
        let score: Int
        let count: Int
        var id: Int { score }
        var label: String { "\(score)" }
    }

    struct MonthPoint: Identifiable, Sendable, Equatable {
        let month: Date
        let count: Int
        var id: Date { month }
    }

    /// 预算 / 票房散点（两者都有数据才进入）。
    struct BudgetPoint: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let budget: Int64
        let revenue: Int64

        var profit: Int64 { revenue - budget }
        /// 票房 / 预算；预算已保证 > 0。
        var ratio: Double { Double(revenue) / Double(budget) }
    }

    /// 观影护照：已点亮的国家 / 地区。
    struct CountryStamp: Identifiable, Sendable, Equatable {
        let code: String
        let name: String
        let count: Int
        var id: String { code }
    }

    /// 雷达图固定八维（名称规则见 `radarAxes`）。
    struct RadarAxis: Identifiable, Sendable, Equatable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let totalTitles: Int
    let favoriteCount: Int
    let watchlistCount: Int
    let movieCount: Int
    let tvCount: Int
    /// 电影时长合计（剧集只存单集时长，不计入，避免口径混淆）。
    let movieMinutes: Int
    let pendingCount: Int

    let genres: [Slice]
    let decades: [YearBucket]
    let ratings: [RatingBucket]
    let monthly: [MonthPoint]
    let directors: [Slice]
    let cast: [Slice]
    /// 国家 / 地区（中文名，按条数排序，最多 8 个）。
    let countries: [Slice]
    /// 预算 vs 票房（按利润降序）。
    let budgetRevenue: [BudgetPoint]
    /// 观影护照：有坐标的国家 / 地区（按条数降序）。
    let passport: [CountryStamp]
    /// 收藏时间轴：最早到最晚年份逐年连续，无作品的年份补 0。
    let timeline: [YearBucket]
    /// 类型雷达：固定八维，按设计顺序排列。
    let radar: [RadarAxis]

    var isEmpty: Bool { totalTitles == 0 }

    /// 收藏 + 观看清单合并去重后的统计。
    init(
        favorites: [LibrarySnapshot],
        watchlist: [LibrarySnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        var seen: Set<String> = []
        var items: [LibrarySnapshot] = []
        for item in favorites + watchlist where seen.insert(item.id).inserted {
            items.append(item)
        }

        totalTitles = items.count
        favoriteCount = favorites.count
        watchlistCount = watchlist.count
        movieCount = items.count { $0.mediaKind == .movie }
        tvCount = items.count { $0.mediaKind == .tv }
        pendingCount = items.count { !$0.isEnriched }
        movieMinutes = items
            .filter { $0.mediaKind == .movie }
            .compactMap(\.runtime)
            .reduce(0, +)

        genres = Self.top(items.flatMap { $0.genreNames }, limit: 8)
        directors = Self.top(items.compactMap { $0.director }, limit: 10)
        cast = Self.top(items.flatMap(\.topCast), limit: 10)
        countries = Self.top(
            items.flatMap(\.countries).map(CountryDirectory.name(for:)),
            limit: 8
        )

        budgetRevenue = items.compactMap { item in
            guard let budget = item.budget, budget > 0,
                  let revenue = item.revenue, revenue > 0 else { return nil }
            return BudgetPoint(
                id: item.id,
                title: item.title,
                budget: budget,
                revenue: revenue
            )
        }
        .sorted { ($0.profit, $0.title) > ($1.profit, $1.title) }

        passport = Self.passport(from: items)
        timeline = Self.timeline(from: items)
        radar = Self.radar(from: items)

        decades = Self.histogram(
            items.compactMap(\.year).map { $0 / 10 * 10 },
            make: { YearBucket(year: $0, count: $1) },
            sort: { $0.year < $1.year }
        )

        ratings = Self.histogram(
            items.compactMap(\.voteAverage).map { min(max(Int($0.rounded(.down)), 0), 10) },
            make: { RatingBucket(score: $0, count: $1) },
            sort: { $0.score < $1.score }
        )

        monthly = Self.months(items: items, now: now, calendar: calendar)
    }

    // MARK: - 计算

    private static func top(_ values: [String], limit: Int) -> [Slice] {
        var counts: [String: Int] = [:]
        for value in values {
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        return counts
            .map { Slice(name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(limit)
            .map { $0 }
    }

    private static func histogram(
        _ values: [Int],
        make: (Int, Int) -> YearBucket,
        sort: (YearBucket, YearBucket) -> Bool
    ) -> [YearBucket] {
        var counts: [Int: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.map { make($0.key, $0.value) }.sorted(by: sort)
    }

    private static func histogram(
        _ values: [Int],
        make: (Int, Int) -> RatingBucket,
        sort: (RatingBucket, RatingBucket) -> Bool
    ) -> [RatingBucket] {
        var counts: [Int: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.map { make($0.key, $0.value) }.sorted(by: sort)
    }

    /// 按国家代码聚合，只保留有坐标的；未知代码不进入地图（也不计入点亮数）。
    private static func passport(from items: [LibrarySnapshot]) -> [CountryStamp] {
        var counts: [String: Int] = [:]
        for code in items.flatMap(\.countries) {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { continue }
            counts[normalized, default: 0] += 1
        }
        return counts
            .compactMap { code, count in
                guard let info = CountryDirectory.info(for: code) else { return nil }
                return CountryStamp(code: code, name: info.name, count: count)
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    /// 作品年份的有效区间：过滤脏数据，避免异常年份把时间轴拉到几百年。
    private static let validYearRange = 1888...2100

    /// 最早到最晚年份逐年展开；无作品的年份保留 0，让长廊保持真实间距。
    private static func timeline(from items: [LibrarySnapshot]) -> [YearBucket] {
        var counts: [Int: Int] = [:]
        for year in items.compactMap(\.year) where validYearRange.contains(year) {
            counts[year, default: 0] += 1
        }
        guard let earliest = counts.keys.min(), let latest = counts.keys.max() else { return [] }
        return (earliest...latest).map { YearBucket(year: $0, count: counts[$0] ?? 0) }
    }

    /// 八维类型：名称可能随 TMDB 语言变化（如 TV 的「科幻奇幻」），用别名合并。
    private static let radarAxes: [(name: String, aliases: Set<String>)] = [
        ("科幻", ["科幻", "科幻奇幻", "Science Fiction", "Sci-Fi & Fantasy"]),
        ("剧情", ["剧情", "Drama"]),
        ("喜剧", ["喜剧", "Comedy"]),
        ("恐怖", ["恐怖", "Horror"]),
        ("动作", ["动作", "动作冒险", "Action", "Action & Adventure"]),
        ("爱情", ["爱情", "Romance"]),
        ("动画", ["动画", "Animation"]),
        ("纪录片", ["纪录片", "Documentary"])
    ]

    private static func radar(from items: [LibrarySnapshot]) -> [RadarAxis] {
        var counts = Array(repeating: 0, count: radarAxes.count)
        for item in items {
            let names = Set(item.genreNames.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            // 同一部作品在同一维度只计一次：即使同时带「科幻」与「科幻奇幻」。
            for (index, axis) in radarAxes.enumerated()
            where axis.aliases.contains(where: { names.contains($0.lowercased()) }) {
                counts[index] += 1
            }
        }
        return zip(radarAxes, counts).map { RadarAxis(name: $0.0.name, count: $0.1) }
    }

    /// 最近 12 个月（含当月）的入库条数；空缺月份补 0，曲线连续。
    private static func months(
        items: [LibrarySnapshot],
        now: Date,
        calendar: Calendar
    ) -> [MonthPoint] {
        let currentMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var buckets: [Date: Int] = [:]
        for offset in stride(from: 11, through: 0, by: -1) {
            if let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth) {
                buckets[month] = 0
            }
        }
        for item in items {
            let month = calendar.dateInterval(of: .month, for: item.addedAt)?.start
                ?? calendar.dateInterval(of: .month, for: now)?.start ?? now
            if buckets[month] != nil { buckets[month, default: 0] += 1 }
        }
        return buckets.keys.sorted().map { MonthPoint(month: $0, count: buckets[$0] ?? 0) }
    }
}
