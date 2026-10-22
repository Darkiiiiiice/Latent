import Foundation

/// 影评（TMDB `/movie/{id}/reviews` 与 `/tv/{id}/reviews`，v1.23）。
///
/// 只读聚合：本应用不写评论、不回写评分（设计文档第 1 节非目标）。
struct Review: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let author: String
    let authorDetails: ReviewAuthor?
    let content: String
    let createdAt: String?
    let updatedAt: String?
    let url: URL?

    private enum CodingKeys: String, CodingKey {
        case id, author, content, url
        case authorDetails = "author_details"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String, author: String = "", authorDetails: ReviewAuthor? = nil,
        content: String = "", createdAt: String? = nil, updatedAt: String? = nil, url: URL? = nil
    ) {
        self.id = id
        self.author = author
        self.authorDetails = authorDetails
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let author = ((try? container.decodeIfPresent(String.self, forKey: .author)) ?? nil) ?? ""
        let createdAt = (try? container.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
        // id 缺失（少数老影评）时用「作者 + 时间」兜底，保证列表可去重、可 ForEach。
        let rawID = ((try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? ""
        self.id = rawID.isEmpty ? "\(author)#\(createdAt ?? "")" : rawID
        self.author = author
        self.authorDetails = (try? container.decodeIfPresent(ReviewAuthor.self, forKey: .authorDetails)) ?? nil
        self.content = ((try? container.decodeIfPresent(String.self, forKey: .content)) ?? nil) ?? ""
        self.createdAt = createdAt
        self.updatedAt = (try? container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil
        let urlString = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? nil
        self.url = urlString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    /// 展示用作者名：优先昵称，其次用户名，最后退回 `author`。
    var displayAuthor: String {
        let candidates = [authorDetails?.name, authorDetails?.username, author]
        for candidate in candidates {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return "匿名用户"
    }

    /// 头像首字（无头像时画字母圆）。
    var initial: String {
        String(displayAuthor.prefix(1)).uppercased()
    }

    /// TMDB 偶有 gravatar 这类绝对地址（形如 `/https://secure.gravatar.com/…`），
    /// 图片管线只认 `image.tmdb.org` 的相对路径，这类一律退回字母头像。
    var avatarPath: String? {
        guard let path = authorDetails?.avatarPath, !path.isEmpty, !path.contains("http") else { return nil }
        return path
    }

    /// 评分（作者自评，0–10）；没有则 nil。
    var ratingText: String? {
        guard let rating = authorDetails?.rating else { return nil }
        return Formatters.rating(rating)
    }

    /// 正文（去首尾空白）；全空白视为没有内容。
    var bodyText: String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 发表时间的相对说法（「3 天前」「2024 年 3 月 1 日」）。
    var relativeCreatedText: String? {
        guard let date = Formatters.isoDate(createdAt) else { return nil }
        return Formatters.relativeTime(date)
    }

    /// 正文超过这个长度就默认折叠。
    var isLong: Bool {
        (bodyText?.count ?? 0) > 240
    }
}

/// 影评作者信息（`author_details`）。
struct ReviewAuthor: Decodable, Sendable, Hashable {
    let name: String?
    let username: String?
    let avatarPath: String?
    let rating: Double?

    private enum CodingKeys: String, CodingKey {
        case name, username, rating
        case avatarPath = "avatar_path"
    }

    init(name: String? = nil, username: String? = nil, avatarPath: String? = nil, rating: Double? = nil) {
        self.name = name
        self.username = username
        self.avatarPath = avatarPath
        self.rating = rating
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? nil
        self.avatarPath = (try? container.decodeIfPresent(String.self, forKey: .avatarPath)) ?? nil
        self.rating = (try? container.decodeIfPresent(Double.self, forKey: .rating)) ?? nil
    }
}
