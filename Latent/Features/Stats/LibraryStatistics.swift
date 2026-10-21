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
    let countries: [Slice]

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
        countries = Self.top(items.flatMap(\.countries), limit: 8)

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
