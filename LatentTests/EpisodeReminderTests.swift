import Foundation
import Testing
@testable import Latent

/// 追更提醒（v1.25）：触发时刻计算、文案、幂等标识与调度流程。
@Suite("追更提醒")
struct EpisodeReminderTests {

    /// 固定日历与时区，避免测试依赖运行机器的本地时区。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }

    private func date(_ string: String) -> Date {
        Formatters.date(from: string) ?? .distantPast
    }

    @Test("未来播出日：提醒落在当天 20:00")
    func schedulesOnAirDate() throws {
        let now = date("2026-10-22")
        let reminder = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语",
            seasonNumber: 5, episodeNumber: 3, episodeTitle: "第三章",
            airDate: "2026-11-05", calendar: calendar, now: now
        ))

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        #expect(components.year == 2026)
        #expect(components.month == 11)
        #expect(components.day == 5)
        #expect(components.hour == EpisodeReminder.hourOfDay)
        #expect(components.minute == 0)
        #expect(reminder.airDate == "2026-11-05")
    }

    @Test("播出时间已过（含当天 20:00 之后）不生成提醒")
    func skipsPastAirdates() {
        // 昨天
        #expect(EpisodeReminder(
            showID: 1, showTitle: "示例", seasonNumber: 1, episodeNumber: 1,
            episodeTitle: nil, airDate: "2026-10-21", calendar: calendar, now: date("2026-10-22")
        ) == nil)
        // 当天 21:00（已过当晚 20:00）
        let lateToday = calendar.date(byAdding: .hour, value: 21, to: date("2026-10-22")) ?? .distantPast
        #expect(EpisodeReminder(
            showID: 1, showTitle: "示例", seasonNumber: 1, episodeNumber: 2,
            episodeTitle: nil, airDate: "2026-10-22", calendar: calendar, now: lateToday
        ) == nil)
        // 日期缺失或非法
        #expect(EpisodeReminder(
            showID: 1, showTitle: "示例", seasonNumber: 1, episodeNumber: 3,
            episodeTitle: nil, airDate: nil, calendar: calendar, now: date("2026-10-22")
        ) == nil)
        #expect(EpisodeReminder(
            showID: 1, showTitle: "示例", seasonNumber: 1, episodeNumber: 4,
            episodeTitle: nil, airDate: "待定", calendar: calendar, now: date("2026-10-22")
        ) == nil)
    }

    @Test("同一集只有一条提醒标识")
    func identifierIsStable() throws {
        let now = date("2026-10-22")
        let first = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章", airDate: "2026-11-05", calendar: calendar, now: now
        ))
        let second = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章（改）", airDate: "2026-11-05", calendar: calendar, now: now
        ))
        #expect(first.identifier == second.identifier)
        #expect(first.identifier.contains("1399"))
        #expect(first.identifier.contains("s5e3"))
    }

    @Test("通知文案：季集与集名拼接，缺集名不多余分隔符")
    func notificationText() throws {
        let now = date("2026-10-22")
        let withTitle = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章", airDate: "2026-11-05", calendar: calendar, now: now
        ))
        #expect(withTitle.notificationTitle == "怪奇物语 有新一集")
        #expect(withTitle.notificationBody == "第 5 季第 3 集 · 第三章 今晚播出")

        let withoutTitle = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 4,
            episodeTitle: "   ", airDate: "2026-11-12", calendar: calendar, now: now
        ))
        #expect(withoutTitle.notificationBody == "第 5 季第 4 集 今晚播出")
    }
}

/// 调度流程：授权分支、排入 / 取消、过期拒绝。
@Suite("追更提醒调度")
struct EpisodeReminderSchedulerTests {

    @Test("未授权 → 请求后允许 → 排入系统通知")
    func scheduleAfterGrant() async throws {
        let scheduler = FakeReminderScheduler(status: .notDetermined, grants: true)
        let reminder = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章", airDate: "2099-11-05"
        ))

        #expect(await scheduler.authorizationStatus() == .notDetermined)
        #expect(await scheduler.requestAuthorization())
        #expect(await scheduler.authorizationStatus() == .allowed)

        try await scheduler.schedule(reminder)
        #expect(await scheduler.isScheduled(identifier: reminder.identifier))
        #expect(await scheduler.scheduledIdentifiers == [reminder.identifier])
    }

    @Test("取消后不再处于已排期状态")
    func cancelRemovesPending() async throws {
        let scheduler = FakeReminderScheduler(status: .allowed, grants: true)
        let reminder = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章", airDate: "2099-11-05"
        ))

        try await scheduler.schedule(reminder)
        await scheduler.cancel(identifier: reminder.identifier)
        #expect(await scheduler.isScheduled(identifier: reminder.identifier) == false)
    }

    @Test("同一集重复设置只覆盖，不堆积")
    func scheduleIsIdempotent() async throws {
        let scheduler = FakeReminderScheduler(status: .allowed, grants: true)
        let reminder = try #require(EpisodeReminder(
            showID: 1399, showTitle: "怪奇物语", seasonNumber: 5, episodeNumber: 3,
            episodeTitle: "第三章", airDate: "2099-11-05"
        ))

        try await scheduler.schedule(reminder)
        try await scheduler.schedule(reminder)
        #expect(await scheduler.scheduledIdentifiers.count == 1)
    }

    @Test("授权被拒：请求返回 false，不排入任何通知")
    func deniedAuthorization() async throws {
        let scheduler = FakeReminderScheduler(status: .denied, grants: false)
        #expect(await scheduler.requestAuthorization() == false)
        #expect(await scheduler.authorizationStatus() == .denied)
        #expect(await scheduler.scheduledIdentifiers.isEmpty)
    }
}

/// 单测用假调度器：只记内存状态，不碰 `UNUserNotificationCenter`。
actor FakeReminderScheduler: EpisodeReminderScheduling {
    private var status: EpisodeReminderAuthorization
    private let grants: Bool
    private var identifiers: Set<String> = []

    init(status: EpisodeReminderAuthorization, grants: Bool) {
        self.status = status
        self.grants = grants
    }

    var scheduledIdentifiers: Set<String> { identifiers }

    func authorizationStatus() async -> EpisodeReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        if status == .notDetermined { status = grants ? .allowed : .denied }
        return status == .allowed
    }

    func schedule(_ reminder: EpisodeReminder) async throws {
        guard reminder.fireDate > Date() else { throw EpisodeReminderError.tooLate }
        identifiers.insert(reminder.identifier)
    }

    func cancel(identifier: String) async { identifiers.remove(identifier) }

    func isScheduled(identifier: String) async -> Bool { identifiers.contains(identifier) }
}
