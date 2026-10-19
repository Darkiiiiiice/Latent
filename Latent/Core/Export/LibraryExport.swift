import Foundation
import UniformTypeIdentifiers

/// 导出范围（设计文档第 8.9 节）。
enum ExportScope: String, CaseIterable, Sendable {
    case favorites
    case watchlist
    case history
    case all

    var title: String {
        switch self {
        case .favorites: return "收藏"
        case .watchlist: return "观看清单"
        case .history: return "历史"
        case .all: return "全部库"
        }
    }
}

/// 导出格式。
enum ExportFormat: String, CaseIterable, Sendable {
    case json
    case markdown

    var title: String {
        switch self {
        case .json: return "JSON"
        case .markdown: return "Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .json: return .json
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

/// 本地库导出快照（JSON / Markdown 共用的中间结构）。
///
/// 只包含库里已有的字段：不读取网络、不包含 Token / 代理 / 缓存 / 最近搜索。
struct LibraryExport: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let tmdbID: Int
        let mediaType: String
        let title: String
        let originalTitle: String?
        let year: Int?
        let voteAverage: Double?
        let posterPath: String?
        let posterURL: String?
        /// 收藏 / 观看清单的加入时间。
        let addedAt: Date?
        /// 历史的最近查看时间。
        let viewedAt: Date?

        var tmdbURL: String {
            "https://www.themoviedb.org/\(mediaType)/\(tmdbID)"
        }
    }

    let app: String
    let schemaVersion: Int
    let scope: String
    let exportedAt: Date
    let language: String
    let favorites: [Entry]
    let watchlist: [Entry]
    let history: [Entry]

    var totalCount: Int {
        favorites.count + watchlist.count + history.count
    }

    var isEmpty: Bool {
        totalCount == 0
    }
}

/// 把 `LibrarySnapshot` 转成导出条目，并生成 JSON / Markdown。
enum LibraryExportBuilder {
    static let appName = "显影（Latent）"
    static let schemaVersion = 1

    /// 单张海报的公开地址（导出文件里给外部工具用，不做图片下载）。
    static func posterURL(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/w342\(path)"
    }

    static func build(
        scope: ExportScope,
        favorites: [LibrarySnapshot],
        watchlist: [LibrarySnapshot],
        history: [LibrarySnapshot],
        language: String,
        exportedAt: Date = Date()
    ) -> LibraryExport {
        let includeFavorites = scope == .favorites || scope == .all
        let includeWatchlist = scope == .watchlist || scope == .all
        let includeHistory = scope == .history || scope == .all

        return LibraryExport(
            app: appName,
            schemaVersion: schemaVersion,
            scope: scope.rawValue,
            exportedAt: exportedAt,
            language: language,
            favorites: includeFavorites ? favorites.map { entry($0, isHistory: false) } : [],
            watchlist: includeWatchlist ? watchlist.map { entry($0, isHistory: false) } : [],
            history: includeHistory ? history.map { entry($0, isHistory: true) } : []
        )
    }

    static func jsonData(_ export: LibraryExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    static func markdown(_ export: LibraryExport, calendar: Calendar = .current) -> String {
        var lines: [String] = []
        lines.append("# 显影 · \(ExportScope(rawValue: export.scope)?.title ?? "全部库")")
        lines.append("")
        lines.append("> 导出时间：\(dateText(export.exportedAt, calendar: calendar)) · 元数据语言：\(export.language) · 共 \(export.totalCount) 项")
        lines.append("")

        appendSection(
            title: "收藏",
            entries: export.favorites,
            marker: { _ in "★" },
            dateLabel: "收藏于",
            to: &lines,
            calendar: calendar
        )
        appendSection(
            title: "观看清单",
            entries: export.watchlist,
            marker: { _ in "[ ]" },
            dateLabel: "加入于",
            to: &lines,
            calendar: calendar
        )
        appendSection(
            title: "浏览历史",
            entries: export.history,
            marker: { _ in "·" },
            dateLabel: "查看于",
            to: &lines,
            calendar: calendar
        )

        return lines.joined(separator: "\n") + "\n"
    }

    static func suggestedFilename(scope: ExportScope, format: ExportFormat, date: Date = Date()) -> String {
        "显影-\(scope.title)-\(fileDate(date))"
    }

    // MARK: - 内部

    private static func entry(_ snapshot: LibrarySnapshot, isHistory: Bool) -> LibraryExport.Entry {
        LibraryExport.Entry(
            tmdbID: snapshot.tmdbID,
            mediaType: snapshot.mediaKind.rawValue,
            title: snapshot.title,
            originalTitle: snapshot.originalTitle,
            year: snapshot.year,
            voteAverage: snapshot.voteAverage,
            posterPath: snapshot.posterPath,
            posterURL: posterURL(path: snapshot.posterPath),
            addedAt: isHistory ? nil : snapshot.addedAt,
            viewedAt: isHistory ? snapshot.addedAt : nil
        )
    }

    private static func appendSection(
        title: String,
        entries: [LibraryExport.Entry],
        marker: (LibraryExport.Entry) -> String,
        dateLabel: String,
        to lines: inout [String],
        calendar: Calendar
    ) {
        guard !entries.isEmpty else { return }
        lines.append("## \(title)（\(entries.count)）")
        lines.append("")
        for entry in entries {
            let year = entry.year.map { "（\($0)）" } ?? ""
            let kind = kindLabel(entry.mediaType)
            let rating = entry.voteAverage.flatMap(Formatters.rating).map { " · ★ \($0)" } ?? ""
            let original = originalTitleSuffix(entry)
            let date = entry.viewedAt ?? entry.addedAt
            let dateSuffix = date.map { " · \(dateLabel) \(dateText($0, calendar: calendar))" } ?? ""
            let link = "[TMDB \(entry.tmdbID)](\(entry.tmdbURL))"
            lines.append("- \(marker(entry)) **\(escape(entry.title))**\(year) · \(kind)\(rating)\(original) · \(link)\(dateSuffix)")
        }
        lines.append("")
    }

    private static func originalTitleSuffix(_ entry: LibraryExport.Entry) -> String {
        guard let original = entry.originalTitle,
              !original.isEmpty,
              original != entry.title else { return "" }
        return " · 原名 \(escape(original))"
    }

    private static func kindLabel(_ raw: String) -> String {
        MediaKind(tmdbValue: raw).label
    }

    /// Markdown 行内转义：标题里出现 `*`、`[`、`]` 等字符时不破坏列表 / 链接。
    private static func escape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\\", with: "\\\\")
        for character in ["`", "*", "_", "[", "]", "<", ">", "#", "|"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result
    }

    private static func dateText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
