import Testing
import Foundation
@testable import Latent

@Suite("上映日历")
struct CalendarTests {

    // MARK: - 测试用固定时间

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 15, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - 端点

    @Test("端点路径与查询：upcoming / on the air 只带 language + page")
    func endpointPathsAndQuery() throws {
        let upcomingURL = EndpointURLBuilder.url(for: .movieUpcoming(page: 2), language: "zh-CN")
        #expect(upcomingURL.path == "/3/movie/upcoming")
        let upcomingItems = try #require(URLComponents(url: upcomingURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(upcomingItems.count == 2)
        #expect(upcomingItems.contains(URLQueryItem(name: "language", value: "zh-CN")))
        #expect(upcomingItems.contains(URLQueryItem(name: "page", value: "2")))
        #expect(Endpoint.movieUpcoming(page: 2).cacheMaxAge == CacheTTL.trending)

        let onTheAirURL = EndpointURLBuilder.url(for: .tvOnTheAir(page: 1), language: "zh-CN")
        #expect(onTheAirURL.path == "/3/tv/on_the_air")
        let onTheAirItems = try #require(URLComponents(url: onTheAirURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(onTheAirItems.count == 2)
        #expect(onTheAirItems.contains(URLQueryItem(name: "page", value: "1")))
        #expect(Endpoint.tvOnTheAir(page: 1).cacheMaxAge == CacheTTL.trending)
    }

    // MARK: - 倒计时文案

    @Test("倒计时文案：今天 / 明天 / N 天后 / 过去与缺日期为 nil")
    func countdownText() {
        let now = date(2026, 10, 22, hour: 15)
        // 同一天（哪怕还没到零点之后的时间）都算「今天」。
        #expect(CalendarEntry.countdownText(for: "2026-10-22", now: now, calendar: calendar) == "今天")
        #expect(CalendarEntry.countdownText(for: "2026-10-23", now: now, calendar: calendar) == "明天")
        #expect(CalendarEntry.countdownText(for: "2026-10-27", now: now, calendar: calendar) == "5 天后")
        // 不设 13 天上限：两个月后照样给天数。
        #expect(CalendarEntry.countdownText(for: "2026-12-20", now: now, calendar: calendar) == "59 天后")
        // 已过：不伪造。
        #expect(CalendarEntry.countdownText(for: "2026-10-21", now: now, calendar: calendar) == nil)
        #expect(CalendarEntry.countdownText(for: nil, now: now, calendar: calendar) == nil)
        #expect(CalendarEntry.countdownText(for: "", now: now, calendar: calendar) == nil)
        #expect(CalendarEntry.countdownText(for: "not-a-date", now: now, calendar: calendar) == nil)
    }

    // MARK: - 合并去重

    @Test("合并去重与排序：过去与缺日期丢弃、同 ID 只留一条、日期升序")
    func mergeGlobal() {
        let now = date(2026, 10, 22)
        let a = MediaSummary(id: 1, mediaKind: .movie, title: "A", dateString: "2026-11-05", voteAverage: 7)
        let b = MediaSummary(id: 2, mediaKind: .movie, title: "B", dateString: "2026-11-01", voteAverage: 7)
        let bAgain = MediaSummary(id: 2, mediaKind: .movie, title: "B", dateString: "2026-11-01", voteAverage: 7)
        let c = MediaSummary(id: 3, mediaKind: .tv, title: "C", dateString: "2026-10-22", voteAverage: 7)
        let past = MediaSummary(id: 4, mediaKind: .movie, title: "Past", dateString: "2026-10-01", voteAverage: 7)
        let noDate = MediaSummary(id: 5, mediaKind: .movie, title: "NoDate", dateString: nil, voteAverage: 7)
        // 同日两条，按 stableID 升序兜底。
        let tie1 = MediaSummary(id: 9, mediaKind: .movie, title: "Tie1", dateString: "2026-11-05", voteAverage: 7)
        let tie2 = MediaSummary(id: 8, mediaKind: .movie, title: "Tie2", dateString: "2026-11-05", voteAverage: 7)

        let merged = CalendarModel.mergeGlobal(
            upcoming: [a, b, tie1, tie2],
            onTheAir: [bAgain, c, past, noDate],
            now: now,
            calendar: calendar
        )

        #expect(merged.map(\.id) == ["tv-3", "movie-2", "movie-1", "movie-8", "movie-9"])
        #expect(!merged.contains { $0.id == "movie-4" })
        #expect(!merged.contains { $0.id == "movie-5" })
        #expect(merged.allSatisfy { $0.libraryKinds.isEmpty })
    }

    // MARK: - 片库待映

    @Test("片库待映候选：年份过滤、去重、清单优先、上限")
    func pendingCandidates() {
        func snapshot(_ kind: MediaKind, _ id: Int, year: Int?) -> LibrarySnapshot {
            LibrarySnapshot(
                mediaKind: kind, tmdbID: id, title: "T\(id)", originalTitle: nil,
                year: year, posterPath: nil, voteAverage: nil, addedAt: Date(timeIntervalSince1970: 0)
            )
        }

        let watchlist = [
            snapshot(.movie, 1, year: 2026),
            snapshot(.movie, 2, year: 2025),  // 已过年份，跳过
        ]
        let favorites = [
            snapshot(.tv, 3, year: 2027),
            snapshot(.movie, 1, year: 2026),  // 与清单重复 → 归属合并
        ]

        let candidates = CalendarModel.pendingLibraryCandidates(
            favorites: favorites, watchlist: watchlist, currentYear: 2026
        )

        #expect(candidates.map(\.stableID) == ["movie-1", "tv-3"])
        #expect(candidates[0].kinds == [.watchlist, .favorites])
        #expect(candidates[1].kinds == [.favorites])

        // 上限：候选多于 limit 时截断。
        let many = (1...30).map { snapshot(.movie, $0, year: 2026) }
        #expect(
            CalendarModel.pendingLibraryCandidates(
                favorites: many, watchlist: [], currentYear: 2026, limit: 5
            ).count == 5
        )
    }

    @Test("buildMine：只保留拿到未来日期的候选，库归属徽标保留")
    func buildMine() throws {
        let watchlist = [
            LibrarySnapshot(
                mediaKind: .movie, tmdbID: 1, title: "A", originalTitle: nil,
                year: 2026, posterPath: "/a.jpg", voteAverage: 8, addedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let favorites = [
            LibrarySnapshot(
                mediaKind: .tv, tmdbID: 2, title: "B", originalTitle: nil,
                year: 2026, posterPath: nil, voteAverage: nil, addedAt: Date(timeIntervalSince1970: 0)
            ),
            LibrarySnapshot(
                mediaKind: .movie, tmdbID: 3, title: "C", originalTitle: nil,
                year: 2026, posterPath: nil, voteAverage: nil, addedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let candidates = CalendarModel.pendingLibraryCandidates(
            favorites: favorites, watchlist: watchlist, currentYear: 2026
        )
        #expect(candidates.count == 3)

        // A 拿到未来日期；B 日期已过；C 详情拉取失败（无记录）——都只留 A。
        let entries = CalendarModel.buildMine(
            candidates: candidates,
            dateByStableID: ["movie-1": "2026-11-05", "tv-2": "2026-10-01"]
        )

        #expect(entries.count == 1)
        let first = try #require(entries.first)
        #expect(first.id == "movie-1")
        #expect(first.summary.dateString == "2026-11-05")
        #expect(first.libraryKinds == [.watchlist])
        #expect(first.countdownText(now: date(2026, 10, 22), calendar: calendar) == "14 天后")
    }

    // MARK: - 上映提醒

    @Test("ReleaseReminder：当天 9 点触发、过期拒绝、标识幂等、通知文案")
    func releaseReminder() {
        let now = date(2026, 10, 22, hour: 15)

        // 明天上映 → 明天 09:00 触发。
        let tomorrow = ReleaseReminder(
            mediaKind: .movie, tmdbID: 5, title: "沙丘：第三部",
            dateString: "2026-10-23", calendar: calendar, now: now
        )
        #expect(tomorrow != nil)
        #expect(tomorrow?.fireDate == date(2026, 10, 23, hour: 9))

        // 当天上映但已过 9 点 → 拒绝（系统不会补发）。
        #expect(
            ReleaseReminder(
                mediaKind: .movie, tmdbID: 5, title: "沙丘：第三部",
                dateString: "2026-10-22", calendar: calendar, now: now
            ) == nil
        )

        // 当天上映且还没到 9 点 → 当天 09:00 触发。
        let early = ReleaseReminder(
            mediaKind: .movie, tmdbID: 5, title: "沙丘：第三部",
            dateString: "2026-10-22", calendar: calendar, now: date(2026, 10, 22, hour: 7)
        )
        #expect(early?.fireDate == date(2026, 10, 22, hour: 9))

        // 标识幂等：同一部片重复构造，identifier 一致；电影与剧集分命名空间。
        #expect(tomorrow?.identifier == "release-reminder-movie-5")
        #expect(
            ReleaseReminder(
                mediaKind: .movie, tmdbID: 5, title: "沙丘：第三部",
                dateString: "2026-11-01", calendar: calendar, now: now
            )?.identifier == "release-reminder-movie-5"
        )
        #expect(
            ReleaseReminder(
                mediaKind: .tv, tmdbID: 7, title: "怪奇物语",
                dateString: "2026-10-25", calendar: calendar, now: now
            )?.identifier == "release-reminder-tv-7"
        )

        // 通知文案：电影「今天上映」、剧集「今天开播」；正文给完整日期。
        #expect(tomorrow?.notificationTitle == "沙丘：第三部 今天上映")
        #expect(tomorrow?.notificationBody == "2026 年 10 月 23 日")
        #expect(
            ReleaseReminder(
                mediaKind: .tv, tmdbID: 7, title: "怪奇物语",
                dateString: "2026-10-25", calendar: calendar, now: now
            )?.notificationTitle == "怪奇物语 今天开播"
        )

        // 人物 / 缺日期 / 非法日期：都不构造。
        #expect(
            ReleaseReminder(
                mediaKind: .person, tmdbID: 9, title: "某人",
                dateString: "2026-10-25", calendar: calendar, now: now
            ) == nil
        )
        #expect(
            ReleaseReminder(
                mediaKind: .movie, tmdbID: 9, title: "某片",
                dateString: nil, calendar: calendar, now: now
            ) == nil
        )
        #expect(
            ReleaseReminder(
                mediaKind: .movie, tmdbID: 9, title: "某片",
                dateString: "nope", calendar: calendar, now: now
            ) == nil
        )
    }
}
