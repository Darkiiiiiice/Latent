import Foundation

/// 展示层格式化（设计文档第 11 节「格式化」测试点）。
///
/// 约定：所有输出直接面向界面，中文文案；数字一律等宽显示由视图负责。
enum Formatters {

    /// 电影时长：166 → 「2 小时 46 分」；< 60 分钟 → 「46 分」。
    static func runtime(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins) 分" }
        if mins == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(mins) 分"
    }

    /// 金钱：190_000_000 → 「$190M」；< 100 万 → 「$999K」；0 / nil → nil。
    static func money(_ amount: Int?) -> String? {
        guard let amount, amount > 0 else { return nil }
        if amount >= 1_000_000_000 {
            return "$" + trimUpTo1Decimal(Double(amount) / 1_000_000_000) + "B"
        }
        if amount >= 1_000_000 {
            return "$" + trimUpTo1Decimal(Double(amount) / 1_000_000) + "M"
        }
        if amount >= 1_000 {
            return "$" + trimUpTo1Decimal(Double(amount) / 1_000) + "K"
        }
        return "$\(amount)"
    }

    /// 评分：一位小数；0 / nil → nil（调用方决定是否显示「暂无评分」）。
    static func rating(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return String(format: "%.1f", value)
    }

    /// 评分人数：1_234 → 「1,234」；12_300 → 「1.2 万」；> 1 亿用「亿」。
    static func voteCount(_ count: Int) -> String {
        guard count > 0 else { return "0" }
        if count >= 100_000_000 {
            return trimUpTo1Decimal(Double(count) / 100_000_000) + " 亿"
        }
        if count >= 10_000 {
            return trimUpTo1Decimal(Double(count) / 10_000) + " 万"
        }
        return count.formatted(.number.grouping(.automatic))
    }

    /// 年份：1868（TMDB 对未知日期返回 1？不——TMDB 用空字符串；此处只兜底异常值）。
    static func year(from dateString: String?) -> Int? {
        guard let dateString, dateString.count >= 4 else { return nil }
        guard let year = Int(dateString.prefix(4)), year > 1800, year < 3000 else { return nil }
        return year
    }

    /// 日期：2024-03-01 → 「2024 年 3 月 1 日」；解析失败返回原文。
    static func fullDate(_ dateString: String?) -> String? {
        guard let dateString, !dateString.isEmpty else { return nil }
        guard let date = date(from: dateString) else { return dateString }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "yyyy 年 M 月 d 日"
        return output.string(from: date)
    }

    /// 播出日期的人话（v1.18 追更）：「今天」/「明天」/「3 天后」/「昨天」/ 更远或更早给「10 月 24 日」。
    ///
    /// 与 `relativeTime` 的区别：这里只按「天」算且允许未来时间；解析不出日期返回 nil，
    /// 由调用方决定是否整条隐藏。
    static func airDatePhrase(_ dateString: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = date(from: dateString) else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2...13: return "\(days) 天后"
        case -1: return "昨天"
        default: break
        }

        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "M 月 d 日"
        return output.string(from: date)
    }

    /// `yyyy-MM-dd` → `Date`（en_US_POSIX，与 TMDB 返回格式一致）。
    static func date(from dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: dateString)
    }

    /// 历史页相对时间：「12:30」/「昨天 12:30」/「3 天前」/「2026 年 1 月 5 日」。
    static func relativeTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "zh_CN")
        time.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: now) {
            return time.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + time.string(from: date)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if (2...6).contains(days) { return "\(days) 天前" }
        let full = DateFormatter()
        full.locale = Locale(identifier: "zh_CN")
        full.dateFormat = "yyyy 年 M 月 d 日"
        return full.string(from: date)
    }

    /// 字节数：512MB → 「512 MB」（设置页缓存占用）。
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }

    /// 语言标签：zh-CN → 「中文」，en-US → 「English」。
    static func languageLabel(_ code: String) -> String {
        switch code {
        case "zh-CN": return "中文"
        case "en-US": return "English"
        default: return code
        }
    }

    /// ISO 8601 时间戳（TMDB 的 `created_at` 等）；带毫秒与不带毫秒都认。
    static func isoDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func trimUpTo1Decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
