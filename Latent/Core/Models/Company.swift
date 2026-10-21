import Foundation

/// 制片公司（详情里的 `production_companies`，随电影基础响应返回，v1.21）。
struct ProductionCompany: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logoPath: String?
    /// 公司所在国家 / 地区代码。
    let originCountry: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }

    init(id: Int, name: String, logoPath: String? = nil, originCountry: String? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.originCountry = originCountry
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = ((try? container.decodeIfPresent(Int.self, forKey: .id)) ?? nil) ?? 0
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知公司"
        self.logoPath = (try? container.decodeIfPresent(String.self, forKey: .logoPath)) ?? nil
        self.originCountry = (try? container.decodeIfPresent(String.self, forKey: .originCountry)) ?? nil
    }

    /// 公司所在国家 / 地区的中文名；无代码时返回 nil。
    var countryName: String? {
        guard let originCountry, !originCountry.isEmpty else { return nil }
        return WatchProviders.regionName(originCountry)
    }
}

/// 制片公司详情（GET /3/company/{id}，v1.21）。
struct CompanyDetail: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let headquarters: String?
    let homepage: URL?
    let logoPath: String?
    let originCountry: String?
    /// 母公司（如子品牌归属的大集团）。
    let parentCompany: ProductionCompany?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, headquarters, homepage
        case logoPath = "logo_path"
        case originCountry = "origin_country"
        case parentCompany = "parent_company"
    }

    init(
        id: Int, name: String, description: String? = nil, headquarters: String? = nil,
        homepage: URL? = nil, logoPath: String? = nil, originCountry: String? = nil,
        parentCompany: ProductionCompany? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.headquarters = headquarters
        self.homepage = homepage
        self.logoPath = logoPath
        self.originCountry = originCountry
        self.parentCompany = parentCompany
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = ((try? container.decodeIfPresent(Int.self, forKey: .id)) ?? nil) ?? 0
        self.name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "未知公司"
        self.description = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? nil
        self.headquarters = (try? container.decodeIfPresent(String.self, forKey: .headquarters)) ?? nil
        let homepageString = (try? container.decodeIfPresent(String.self, forKey: .homepage)) ?? nil
        self.homepage = homepageString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self.logoPath = (try? container.decodeIfPresent(String.self, forKey: .logoPath)) ?? nil
        self.originCountry = (try? container.decodeIfPresent(String.self, forKey: .originCountry)) ?? nil
        self.parentCompany = (try? container.decodeIfPresent(ProductionCompany.self, forKey: .parentCompany)) ?? nil
    }

    /// 简介正文（去空白）；空串按缺失处理。
    var biography: String? {
        guard let text = description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

    /// 国家 / 地区中文名。
    var countryName: String? {
        guard let originCountry, !originCountry.isEmpty else { return nil }
        return WatchProviders.regionName(originCountry)
    }
}
