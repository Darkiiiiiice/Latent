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
/// 电影 / 剧集 / 人物共用同一套卡面与渲染管线，差异只在字段与页脚的类型标注。
struct ReceiptData: Sendable, Equatable {
    let title: String
    let originalTitle: String?
    /// 页脚标语：优先 tagline，缺则取简介前 60 字，仍缺则省略。
    let tagline: String?
    let posterPath: String?
    let rating: String?
    let voteCount: String?
    let fields: [ReceiptField]
    /// 页脚的类型标注（剧集 / 人物）；电影为 nil，保持 v1.2 卡面不变。
    let subjectLabel: String?

    // MARK: - 电影

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
            originalTitle: originalTitle(detail.originalTitle, sameAs: detail.title),
            tagline: tagline(of: detail.tagline, fallback: detail.overview),
            posterPath: detail.posterPath,
            rating: Formatters.rating(detail.voteAverage),
            voteCount: voteCount(detail.voteCount),
            fields: fields,
            subjectLabel: nil
        )
    }

    // MARK: - 剧集

    static func build(from detail: TVShowDetail) -> ReceiptData {
        var fields: [ReceiptField] = []

        if let date = Formatters.fullDate(detail.firstAirDate) {
            fields.append(ReceiptField(label: "首播", value: date))
        }
        if let seasons = detail.numberOfSeasons, seasons > 0 {
            fields.append(ReceiptField(label: "季数", value: "\(seasons) 季"))
        }
        if let episodes = detail.numberOfEpisodes, episodes > 0 {
            fields.append(ReceiptField(label: "集数", value: "\(episodes) 集"))
        }
        if let genres = detail.genres, !genres.isEmpty {
            fields.append(ReceiptField(label: "类型", value: genres.map(\.name).joined(separator: " / ")))
        }
        var creators = Array((detail.createdBy ?? []).prefix(2).map(\.name))
        if creators.isEmpty {
            creators = Array((detail.credits?.directors ?? []).prefix(2).map(\.name))
        }
        if !creators.isEmpty {
            fields.append(ReceiptField(label: "主创", value: creators.joined(separator: " / ")))
        }
        let cast = Array((detail.credits?.cast ?? []).prefix(3).map(\.name))
        if !cast.isEmpty {
            fields.append(ReceiptField(label: "主演", value: cast.joined(separator: " / ")))
        }

        return ReceiptData(
            title: detail.title,
            originalTitle: originalTitle(detail.originalTitle, sameAs: detail.title),
            tagline: tagline(of: detail.tagline, fallback: detail.overview),
            posterPath: detail.posterPath,
            rating: Formatters.rating(detail.voteAverage),
            voteCount: voteCount(detail.voteCount),
            fields: fields,
            subjectLabel: "剧集"
        )
    }

    // MARK: - 人物

    static func build(from person: PersonDetail) -> ReceiptData {
        var fields: [ReceiptField] = []

        if let life = lifeText(of: person) {
            fields.append(ReceiptField(label: "生卒", value: life))
        }
        if let place = trimmed(person.placeOfBirth) {
            fields.append(ReceiptField(label: "出生地", value: place))
        }
        if let department = trimmed(person.knownForDepartment) {
            fields.append(ReceiptField(label: "领域", value: department))
        }
        let works = representativeWorks(of: person)
        if !works.isEmpty {
            fields.append(ReceiptField(label: "代表作", value: works.joined(separator: " / ")))
        }

        return ReceiptData(
            title: person.name,
            originalTitle: nil,
            // 人物没有 tagline：页脚取简介前 60 字。
            tagline: tagline(of: nil, fallback: person.biography),
            posterPath: person.profilePath,
            rating: nil,
            voteCount: nil,
            fields: fields,
            subjectLabel: "人物"
        )
    }

    // MARK: - 共用映射

    /// 原文名 / 原名：与本地化名相同或为空则省略。
    private static func originalTitle(_ original: String?, sameAs title: String) -> String? {
        guard let original = trimmed(original), original != title else { return nil }
        return original
    }

    private static func tagline(of tagline: String?, fallback overview: String?) -> String? {
        if let tagline = trimmed(tagline) {
            return tagline
        }
        guard let overview = trimmed(overview) else { return nil }
        return overview.count <= 60 ? overview : String(overview.prefix(60)) + "…"
    }

    private static func voteCount(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return "\(count) 人评分"
    }

    /// 生卒年：`1954 – 2023` / 在世 `1954 年生`（只有卒年时省略）。
    private static func lifeText(of person: PersonDetail) -> String? {
        let birth = Formatters.year(from: person.birthday)
        let death = Formatters.year(from: person.deathday)
        switch (birth, death) {
        case let (birth?, death?):
            return "\(birth) – \(death)"
        case let (birth?, nil):
            return "\(birth) 年生"
        default:
            return nil
        }
    }

    /// 代表作：作品年表里按人气取前三（同人气时取较新的）；没有作品则省略该行。
    private static func representativeWorks(of person: PersonDetail) -> [String] {
        let works = person.combinedCredits?.filmography ?? []
        let ranked = works.sorted { lhs, rhs in
            let left = lhs.popularity ?? 0
            let right = rhs.popularity ?? 0
            if left != right { return left > right }
            return (lhs.dateString ?? "0000") > (rhs.dateString ?? "0000")
        }
        return ranked.prefix(3).map(\.title)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
