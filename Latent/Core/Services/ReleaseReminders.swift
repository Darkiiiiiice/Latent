import Foundation
import UserNotifications

/// 一条「上映 / 开播」提醒（v1.34 上映日历）。
///
/// TMDB 只给上映**日期**、不给具体时刻；与剧集追更（当晚 20:00）区分，
/// 上映日提醒放在当天早上 9 点——「今天上映」要给人留出整天安排的时间。
/// 日期已经过去（含当天 9 点已过）时构造失败，调用方据此不显示提醒入口。
struct ReleaseReminder: Sendable, Equatable, Identifiable {
    /// 上映日当天的提醒时刻（本地时区）。
    static let hourOfDay = 9

    let mediaKind: MediaKind
    let tmdbID: Int
    let title: String
    /// 原始日期字符串（`yyyy-MM-dd`），用于文案回显。
    let dateString: String
    /// 实际触发时间。
    let fireDate: Date

    var id: String { identifier }

    /// 同一部片只有一条提醒：重复设置时按这个键覆盖，不会堆积。
    var identifier: String {
        "release-reminder-\(mediaKind.rawValue)-\(tmdbID)"
    }

    init?(
        mediaKind: MediaKind,
        tmdbID: Int,
        title: String,
        dateString: String?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        guard mediaKind == .movie || mediaKind == .tv else { return nil }
        guard let dateString, let day = Formatters.date(from: dateString) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = ReleaseReminder.hourOfDay
        components.minute = 0
        guard let fireDate = calendar.date(from: components), fireDate > now else { return nil }

        self.mediaKind = mediaKind
        self.tmdbID = tmdbID
        self.title = title
        self.dateString = dateString
        self.fireDate = fireDate
    }

    var notificationTitle: String {
        mediaKind == .tv ? "\(title) 今天开播" : "\(title) 今天上映"
    }

    var notificationBody: String {
        Formatters.fullDate(dateString) ?? dateString
    }
}

/// 授权状态与剧集追更共用同一套枚举（系统通知本来就只有一个开关）。
typealias ReminderAuthorization = EpisodeReminderAuthorization

/// 上映提醒调度抽象：视图只依赖协议，单测可换成假实现。
protocol ReleaseReminderScheduling: Sendable {
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async -> Bool
    func schedule(_ reminder: ReleaseReminder) async throws
    func cancel(identifier: String) async
    func isScheduled(identifier: String) async -> Bool
    /// 一次拿回全部已排期的上映提醒标识（日历页整页刷新按钮状态用）。
    func scheduledIdentifiers() async -> Set<String>
}

/// 真实实现：`UNUserNotificationCenter`，纯本地、不联网。
final class LiveReleaseReminderScheduler: ReleaseReminderScheduling, @unchecked Sendable {
    static let shared = LiveReleaseReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> ReminderAuthorization {
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

    func schedule(_ reminder: ReleaseReminder) async throws {
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

    func scheduledIdentifiers() async -> Set<String> {
        let pending = await center.pendingNotificationRequests()
        return Set(pending.map(\.identifier).filter { $0.hasPrefix("release-reminder-") })
    }
}
