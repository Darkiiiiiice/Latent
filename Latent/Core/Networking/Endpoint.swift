import Foundation

/// TMDB 接口定义（设计文档第 4 节端点表）。
///
/// 只负责拼 URL 与查询参数；认证、节流、重试由 `TMDBClient` 负责。
enum Endpoint: Sendable, Hashable {
    /// GET /3/configuration —— 连接验证 + 图片配置。
    case configuration
    /// GET /3/trending/{movie,tv,all}/{day,week}
    case trending(mediaKind: MediaKind, window: TrendingWindow)
    /// GET /3/search/multi
    case searchMulti(query: String, page: Int)
    /// GET /3/movie/{id}?append_to_response=…
    case movieDetail(id: Int)
    /// GET /3/tv/{id}?append_to_response=…
    case tvDetail(id: Int)
    /// GET /3/tv/{id}/season/{n}
    case tvSeason(id: Int, seasonNumber: Int)
    /// GET /3/person/{id}?append_to_response=…
    case personDetail(id: Int)
    /// GET /3/discover/{movie,tv}
    case discover(mediaKind: MediaKind, query: DiscoverQuery, page: Int)
    /// GET /3/genre/{movie,tv}/list
    case genreList(mediaKind: MediaKind)

    enum TrendingWindow: String, Sendable, CaseIterable, Hashable {
        case day
        case week

        var label: String {
            switch self {
            case .day: return "今日"
            case .week: return "本周"
            }
        }
    }

    /// 相对路径（不含查询串）。
    var path: String {
        switch self {
        case .configuration:
            return "/3/configuration"
        case .trending(let mediaKind, let window):
            let type = mediaKind == .movie ? "movie" : mediaKind == .tv ? "tv" : "all"
            return "/3/trending/\(type)/\(window.rawValue)"
        case .searchMulti:
            return "/3/search/multi"
        case .movieDetail(let id):
            return "/3/movie/\(id)"
        case .tvDetail(let id):
            return "/3/tv/\(id)"
        case .tvSeason(let id, let season):
            return "/3/tv/\(id)/season/\(season)"
        case .personDetail(let id):
            return "/3/person/\(id)"
        case .discover(let mediaKind, _, _):
            return "/3/discover/\(mediaKind == .tv ? "tv" : "movie")"
        case .genreList(let mediaKind):
            return "/3/genre/\(mediaKind == .tv ? "tv" : "movie")/list"
        }
    }

    /// 响应缓存 TTL（设计文档第 4 节「缓存」）。
    var cacheMaxAge: TimeInterval {
        switch self {
        case .configuration, .genreList:
            return CacheTTL.settings
        case .trending:
            return CacheTTL.trending
        case .searchMulti:
            return CacheTTL.search
        case .movieDetail, .tvDetail, .tvSeason, .personDetail, .discover:
            return CacheTTL.detail
        }
    }

    /// 查询参数（键排序后拼接，保证同一请求产出同一 URL——便于缓存键与测试断言）。
    ///
    /// `language` 仅由需要本地化的端点显式带上；configuration 与人物作品列表不需要。
    func queryItems(language: String) -> [URLQueryItem] {
        switch self {
        case .configuration:
            return []
        case .trending:
            return [URLQueryItem(name: "language", value: language)]
        case .searchMulti(let query, let page):
            return [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "page", value: String(page)),
            ]
        case .movieDetail:
            return [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "append_to_response", value: "credits,images,similar,recommendations,external_ids,release_dates,watch/providers"),
                URLQueryItem(name: "include_image_language", value: "zh,en,null"),
            ]
        case .tvDetail:
            return [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "append_to_response", value: "credits,images,similar,recommendations,external_ids,content_ratings,watch/providers"),
                URLQueryItem(name: "include_image_language", value: "zh,en,null"),
            ]
        case .tvSeason:
            return [URLQueryItem(name: "language", value: language)]
        case .personDetail:
            return [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "append_to_response", value: "combined_credits,images,external_ids"),
            ]
        case .discover(let mediaKind, let query, let page):
            let dateField = mediaKind == .tv ? "first_air_date" : "primary_release_date"
            var items: [URLQueryItem] = [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "sort_by", value: query.sortBy.rawValue),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "include_adult", value: "false"),
            ]
            if !query.genreIDs.isEmpty {
                items.append(URLQueryItem(name: "with_genres", value: query.genreIDs.map(String.init).sorted().joined(separator: ",")))
            }
            if let yearFrom = query.yearFrom {
                items.append(URLQueryItem(name: "\(dateField).gte", value: "\(yearFrom)-01-01"))
            }
            if let yearTo = query.yearTo {
                items.append(URLQueryItem(name: "\(dateField).lte", value: "\(yearTo)-12-31"))
            }
            if let minRating = query.minRating {
                items.append(URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minRating)))
                items.append(URLQueryItem(name: "vote_count.gte", value: "50"))
            }
            return items
        case .genreList:
            return [URLQueryItem(name: "language", value: language)]
        }
    }
}

/// 生成完整 URL 的辅助工具（纯函数，便于单测）。
enum EndpointURLBuilder {
    static let baseURLString = "https://api.themoviedb.org"

    static func url(for endpoint: Endpoint, language: String) -> URL {
        var components = URLComponents(string: baseURLString)! // 固定字符串，恒可解析
        components.path = endpoint.path
        let items = endpoint.queryItems(language: language).sorted { $0.name < $1.name }
        if !items.isEmpty {
            components.queryItems = items
        }
        return components.url!
    }
}
