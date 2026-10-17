import Foundation

/// URL 剪贴格式（右键菜单 / 事实栏复制）。
enum TMDBLinks {
    /// 网页链接：电影 → /movie/693134；剧集 → /tv/1399；人物 → /person/287。
    static func pageURL(mediaKind: MediaKind, tmdbID: Int) -> URL? {
        URL(string: "https://www.themoviedb.org/\(mediaKind.pathSegment)/\(tmdbID)")
    }

    /// IMDb 外链（来自 external_ids.imdb_id）。
    static func imdbURL(imdbID: String?) -> URL? {
        guard let imdbID, !imdbID.isEmpty else { return nil }
        return URL(string: "https://www.imdb.com/title/\(imdbID)/")
    }
}
