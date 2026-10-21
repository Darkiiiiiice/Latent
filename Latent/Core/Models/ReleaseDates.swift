import Foundation

/// 分地区发行信息（TMDB `release_dates`，随电影详情以 append_to_response 返回，v1.20）。
struct ReleaseDatesResponse: Decodable, Sendable, Equatable {
    let results: [RegionReleaseDates]

    private enum CodingKeys: String, CodingKey { case results }

    init(results: [RegionReleaseDates] = []) {
        self.results = results
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = ((try? container.decodeIfPresent([RegionReleaseDates].self, forKey: .results)) ?? nil) ?? []
    }
}

/// 单个地区的发行信息。
struct RegionReleaseDates: Decodable, Sendable, Equatable, Identifiable {
    /// ISO 3166-1 国家 / 地区代码（如 `CN`、`US`）。
    let countryCode: String
    let releaseDates: [ReleaseDateEntry]

    var id: String { countryCode }

    private enum CodingKeys: String, CodingKey {
        case countryCode = "iso_3166_1"
        case releaseDates = "release_dates"
    }

    init(countryCode: String, releaseDates: [ReleaseDateEntry] = []) {
        self.countryCode = countryCode
        self.releaseDates = releaseDates
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.countryCode = ((try? container.decodeIfPresent(String.self, forKey: .countryCode)) ?? nil) ?? ""
        self.releaseDates = ((try? container.decodeIfPresent([ReleaseDateEntry].self, forKey: .releaseDates)) ?? nil) ?? []
    }

    /// 该地区的分级（certification，如 `PG-13` / `IIA`）；TMDB 多数地区为空。
    var certification: String? {
        releaseDates
            .map { $0.certification.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// 最早的一条院线 / 点映日期，用作地区行上的摘要。
    var earliestDate: String? {
        releaseDates
            .compactMap(\.dayString)
            .min()
    }
}

/// 一条发行记录。
struct ReleaseDateEntry: Decodable, Sendable, Equatable, Identifiable {
    /// TMDB 的 ISO8601 时间戳（如 `2024-02-27T00:00:00.000Z`）；也兼容纯日期。
    let releaseDate: String?
    /// 分级；无分级时为空串。
    let certification: String
    /// 发行类型（1 首映 / 2 点映 / 3 院线 / 4 数字 / 5 实体 / 6 电视）。
    let type: Int
    /// 备注（如「导演剪辑版」）。
    let note: String

    var id: String { "\(type)-\(releaseDate ?? "")-\(note)" }

    private enum CodingKeys: String, CodingKey {
        case releaseDate = "release_date"
        case certification, type, note
    }

    init(releaseDate: String? = nil, certification: String = "", type: Int = 3, note: String = "") {
        self.releaseDate = releaseDate
        self.certification = certification
        self.type = type
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.releaseDate = (try? container.decodeIfPresent(String.self, forKey: .releaseDate)) ?? nil
        self.certification = ((try? container.decodeIfPresent(String.self, forKey: .certification)) ?? nil) ?? ""
        self.type = ((try? container.decodeIfPresent(Int.self, forKey: .type)) ?? nil) ?? 3
        self.note = ((try? container.decodeIfPresent(String.self, forKey: .note)) ?? nil) ?? ""
    }

    /// 只取日期部分（`2024-02-27`），供 `Formatters` 统一格式化。
    var dayString: String? {
        guard let releaseDate, releaseDate.count >= 10 else { return nil }
        return String(releaseDate.prefix(10))
    }

    /// 发行类型的中文名；未知类型返回「其它」。
    var typeLabel: String {
        switch type {
        case 1: return "首映"
        case 2: return "点映"
        case 3: return "院线"
        case 4: return "数字"
        case 5: return "实体"
        case 6: return "电视"
        default: return "其它"
        }
    }

    /// 下拉行上的说明：「院线 · 2024 年 2 月 27 日」+ 备注。
    var summary: String {
        let date = Formatters.fullDate(dayString) ?? "日期待定"
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return noteText.isEmpty ? "\(typeLabel) · \(date)" : "\(typeLabel) · \(date) · \(noteText)"
    }
}

// MARK: - 展示用聚合

/// 一个地区在界面上要展示的一行。
struct RegionReleaseRow: Identifiable, Sendable, Equatable {
    let code: String
    let name: String
    let certification: String?
    let entries: [ReleaseDateEntry]

    var id: String { code }

    /// 标题右侧的摘要：分级 + 上映日期；两者都没有时返回 nil。
    var summary: String? {
        var parts: [String] = []
        if let certification { parts.append(certification) }
        if let date = Formatters.fullDate(entries.compactMap(\.dayString).min()) {
            parts.append(date)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension MovieDetail {
    /// 按「中国大陆 → 出品国 → 美 / 英 / 港 / 台 → 其余按名称」排序的地区列表（v1.20）。
    ///
    /// 无发行记录、或所有地区都没有日期的条目会被过滤掉，避免出现空行。
    var releaseRegions: [RegionReleaseRow] {
        guard let releaseDates else { return [] }
        let origin = Set(productionCountries?.compactMap(\.iso3166_1) ?? [])

        return releaseDates.results
            .filter { $0.releaseDates.contains { $0.dayString != nil } }
            .map { region in
                RegionReleaseRow(
                    code: region.countryCode,
                    name: WatchProviders.regionName(region.countryCode),
                    certification: region.certification,
                    entries: region.releaseDates
                        .filter { $0.dayString != nil }
                        .sorted { ($0.dayString ?? "") < ($1.dayString ?? "") }
                )
            }
            .sorted { lhs, rhs in
                let left = Self.regionRank(lhs.code, origin: origin)
                let right = Self.regionRank(rhs.code, origin: origin)
                if left != right { return left < right }
                return lhs.name < rhs.name
            }
    }

    private static func regionRank(_ code: String, origin: Set<String>) -> Int {
        if code == "CN" { return 0 }
        if origin.contains(code) { return 1 }
        switch code {
        case "US": return 2
        case "GB": return 3
        case "HK": return 4
        case "TW": return 5
        default: return 10
        }
    }

    /// 默认展开的地区：中国大陆有记录就展开它，否则展开第一个。
    var defaultReleaseRegion: String? {
        let regions = releaseRegions
        guard !regions.isEmpty else { return nil }
        return regions.first { $0.code == "CN" }?.code ?? regions.first?.code
    }
}
