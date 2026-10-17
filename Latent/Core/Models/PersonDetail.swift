import Foundation

/// 人物详情（GET /3/person/{id}，append_to_response=combined_credits,images,external_ids）。
struct PersonDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?
    let homepage: URL?
    let externalIDs: ExternalIDs?
    let combinedCredits: CombinedCredits?

    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday, homepage
        case placeOfBirth = "place_of_birth"
        case knownForDepartment = "known_for_department"
        case profilePath = "profile_path"
        case externalIDs = "external_ids"
        case combinedCredits = "combined_credits"
    }

    init(id: Int, name: String, biography: String? = nil, birthday: String? = nil,
         deathday: String? = nil, placeOfBirth: String? = nil,
         knownForDepartment: String? = nil, profilePath: String? = nil,
         homepage: URL? = nil, externalIDs: ExternalIDs? = nil,
         combinedCredits: CombinedCredits? = nil) {
        self.id = id
        self.name = name
        self.biography = biography
        self.birthday = birthday
        self.deathday = deathday
        self.placeOfBirth = placeOfBirth
        self.knownForDepartment = knownForDepartment
        self.profilePath = profilePath
        self.homepage = homepage
        self.externalIDs = externalIDs
        self.combinedCredits = combinedCredits
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "（无名）"
        self.biography = (try? container.decodeIfPresent(String.self, forKey: .biography)) ?? nil
        self.birthday = (try? container.decodeIfPresent(String.self, forKey: .birthday)) ?? nil
        self.deathday = (try? container.decodeIfPresent(String.self, forKey: .deathday)) ?? nil
        self.placeOfBirth = (try? container.decodeIfPresent(String.self, forKey: .placeOfBirth)) ?? nil
        self.knownForDepartment = (try? container.decodeIfPresent(String.self, forKey: .knownForDepartment)) ?? nil
        self.profilePath = (try? container.decodeIfPresent(String.self, forKey: .profilePath)) ?? nil
        let homepageString = (try? container.decodeIfPresent(String.self, forKey: .homepage)) ?? nil
        self.homepage = homepageString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self.externalIDs = (try? container.decodeIfPresent(ExternalIDs.self, forKey: .externalIDs)) ?? nil
        self.combinedCredits = (try? container.decodeIfPresent(CombinedCredits.self, forKey: .combinedCredits)) ?? nil
    }

    /// 生卒：`1954-08-15` / `1954-08-15 – 2023-01-01`（在世显示生年与年龄）。
    var lifeText: String? {
        guard let birthday else { return nil }
        if let deathday {
            return "\(birthday) – \(deathday)"
        }
        return birthday
    }
}

/// combined_credits：电影与剧集出演合并列表（按人气降序的原始顺序）。
struct CombinedCredits: Decodable, Sendable {
    let cast: [MediaSummary]?
    let crew: [MediaSummary]?

    private enum CodingKeys: String, CodingKey { case cast, crew }

    init(cast: [MediaSummary]? = nil, crew: [MediaSummary]? = nil) {
        self.cast = cast
        self.crew = crew
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cast = (try? container.decodeIfPresent([MediaSummary].self, forKey: .cast)) ?? nil
        self.crew = (try? container.decodeIfPresent([MediaSummary].self, forKey: .crew)) ?? nil
    }

    /// 作品年表：去重（同类型同 id 保留一条）、过滤未知类型、按日期降序。
    var filmography: [MediaSummary] {
        let all = (cast ?? []) + (crew ?? [])
        var seen = Set<String>()
        let unique = all.filter { item in
            guard item.mediaKind.isLibraryEligible else { return false }
            let key = "\(item.mediaKind.rawValue)-\(item.id)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        return unique.sorted { lhs, rhs in
            (lhs.dateString ?? "0000") > (rhs.dateString ?? "0000")
        }
    }
}
