import Foundation

/// 分享卡上的一行字段（`value` 为空则该行不出现）。
struct ReceiptField: Sendable, Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }
}

/// 分享卡数据（设计文档第 8.10 节）。
///
/// 只做元数据映射：**字段缺失即省略该行，绝不伪造数值**（没有预算就不印「预算」）。
struct ReceiptData: Sendable, Equatable {
    let title: String
    let originalTitle: String?
    /// 页脚标语：优先 tagline，缺则取简介前 60 字，仍缺则省略。
    let tagline: String?
    let posterPath: String?
    let rating: String?
    let voteCount: String?
    let fields: [ReceiptField]

    /// 入口只挂电影详情（剧集不做）。
    static func build(from detail: MovieDetail) -> ReceiptData {
        var fields: [ReceiptField] = []

        if let year = Formatters.year(from: detail.dateString) {
            fields.append(ReceiptField(label: "年份", value: "\(year)"))
        }
        if let date = Formatters.fullDate(detail.dateString) {
            fields.append(ReceiptField(label: "上映", value: date))
        }
        if let runtime = Formatters.runtime(minutes: detail.runtime) {
            fields.append(ReceiptField(label: "时长", value: runtime))
        }
        if let genres = detail.genres, !genres.isEmpty {
            fields.append(ReceiptField(label: "类型", value: genres.map(\.name).joined(separator: " / ")))
        }
        let directors = Array((detail.credits?.directors ?? []).prefix(2).map(\.name))
        if !directors.isEmpty {
            fields.append(ReceiptField(label: "导演", value: directors.joined(separator: " / ")))
        }
        let cast = Array((detail.credits?.cast ?? []).prefix(3).map(\.name))
        if !cast.isEmpty {
            fields.append(ReceiptField(label: "主演", value: cast.joined(separator: " / ")))
        }

        return ReceiptData(
            title: detail.title,
            originalTitle: originalTitle(of: detail),
            tagline: tagline(of: detail),
            posterPath: detail.posterPath,
            rating: Formatters.rating(detail.voteAverage),
            voteCount: detail.voteCount.flatMap { $0 > 0 ? "\($0) 人评分" : nil },
            fields: fields
        )
    }

    /// 原文片名：与中文名相同或为空则省略。
    private static func originalTitle(of detail: MovieDetail) -> String? {
        guard let original = detail.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !original.isEmpty, original != detail.title else { return nil }
        return original
    }

    private static func tagline(of detail: MovieDetail) -> String? {
        if let tagline = detail.tagline?.trimmingCharacters(in: .whitespacesAndNewlines), !tagline.isEmpty {
            return tagline
        }
        guard let overview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overview.isEmpty else { return nil }
        return overview.count <= 60 ? overview : String(overview.prefix(60)) + "…"
    }
}
