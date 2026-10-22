import Foundation
import UserNotifications

/// 追更提醒的授权状态：界面只区分这三种。
enum EpisodeReminderAuthorization: Sendable, Equatable {
    case notDetermined
    case allowed
    case denied
}

/// 一条「下一集」提醒（v1.25）。
///
/// TMDB 只给播出**日期**、不给具体时刻，因此统一在播出日当晚 20:00 提醒。
/// 播出日已经过去（含当天 20:00 已过）时构造失败，调用方据此隐藏入口。
struct EpisodeReminder: Sendable, Equatable, Identifiable {
    /// 播出口的提醒时刻（本地时区）。
    static let hourOfDay = 20

    let showID: Int
    let showTitle: String
    let seasonNumber: Int
    let episodeNumber: Int
    let episodeTitle: String?
    /// 原始播出日期字符串（`yyyy-MM-dd`），用于文案回显。
    let airDate: String
    /// 实际触发时间。
    let fireDate: Date

    var id: String { identifier }

    /// 同一集只有一条提醒：重复设置时按这个键覆盖，不会堆积。
    var identifier: String {
        "episode-reminder-\(showID)-s\(seasonNumber)e\(episodeNumber)"
    }

    init?(
        showID: Int,
        showTitle: String,
        seasonNumber: Int,
        episodeNumber: Int,
        episodeTitle: String?,
        airDate: String?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        guard let airDate, let day = Formatters.date(from: airDate) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = EpisodeReminder.hourOfDay
        components.minute = 0
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        self.showID = showID
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.airDate = airDate
        self.fireDate = fireDate
    }

    var notificationTitle: String {
        "\(showTitle) 有新一集"
    }

    var notificationBody: String {
        var parts: [String] = []
        if seasonNumber > 0 { parts.append("第 \(seasonNumber) 季") }
        if episodeNumber > 0 { parts.append("第 \(episodeNumber) 集") }
        var body = parts.joined()
        if let episodeTitle {
            let trimmed = episodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                body = body.isEmpty ? trimmed : "\(body) · \(trimmed)"
            }
        }
        return body.isEmpty ? "今晚播出，记得来看" : "\(body) 今晚播出"
    }
}

/// 提醒调度抽象：视图只依赖协议，单测可换成假实现。
protocol EpisodeReminderScheduling: Sendable {
    func authorizationStatus() async -> EpisodeReminderAuthorization
    func requestAuthorization() async -> Bool
    func schedule(_ reminder: EpisodeReminder) async throws
    func cancel(identifier: String) async
    func isScheduled(identifier: String) async -> Bool
}

enum EpisodeReminderError: Error {
    /// 触发时间已经过去（系统不会补发）。
    case tooLate
}

/// 真实实现：`UNUserNotificationCenter`，纯本地、不联网。
final class LiveEpisodeReminderScheduler: EpisodeReminderScheduling, @unchecked Sendable {
    static let shared = LiveEpisodeReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> EpisodeReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(_ reminder: EpisodeReminder) async throws {
        // 时间已过时系统不会补发，直接拒绝，避免界面显示「已提醒」却永远不响。
        guard reminder.fireDate > Date() else { throw EpisodeReminderError.tooLate }

        let content = UNMutableNotificationContent()
        content.title = reminder.notificationTitle
        content.body = reminder.notificationBody
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.identifier, content: content, trigger: trigger
        )
        try await center.add(request)
    }

    func cancel(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func isScheduled(identifier: String) async -> Bool {
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier }
    }
}

/// 应用在前台时也弹横幅（否则系统默认静默进通知中心）。
final class EpisodeNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = EpisodeNotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
