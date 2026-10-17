import Foundation

/// 作品类型（本应用可导航实体的统一标识：电影 / 剧集 / 人物）。
///
/// 未知值兜底为 `.unknown`（TMDB 字段变化不导致解码失败），与设计文档第 4 节一致。
enum MediaKind: String, Decodable, Sendable, CaseIterable, Hashable {
    case movie
    case tv
    case person
    case unknown

    init(tmdbValue: String?) {
        switch tmdbValue?.lowercased() {
        case "movie": self = .movie
        case "tv": self = .tv
        case "person": self = .person
        default: self = .unknown
        }
    }

    /// 参与库（收藏 / 清单 / 历史）的类型只有电影与剧集。
    var isLibraryEligible: Bool {
        self == .movie || self == .tv
    }

    /// TMDB 网页路径与 API 路径段。
    var pathSegment: String {
        switch self {
        case .movie: return "movie"
        case .tv: return "tv"
        case .person: return "person"
        case .unknown: return ""
        }
    }

    /// 界面标签。
    var label: String {
        switch self {
        case .movie: return "电影"
        case .tv: return "剧集"
        case .person: return "人物"
        case .unknown: return "未知"
        }
    }

    /// 分组标题用的复数标签。
    var groupLabel: String {
        switch self {
        case .movie: return "电影"
        case .tv: return "剧集"
        case .person: return "人物"
        case .unknown: return "其他"
        }
    }
}

/// 排序方式（库页面与发现页共用）。
enum SortOption: String, CaseIterable, Sendable {
    case addedAt     // 添加时间（新 → 旧）
    case rating      // 评分（高 → 低）
    case year        // 年份（新 → 旧）

    var label: String {
        switch self {
        case .addedAt: return "添加时间"
        case .rating: return "评分"
        case .year: return "年份"
        }
    }
}
