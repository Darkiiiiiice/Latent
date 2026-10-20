import Foundation

/// 观看平台（TMDB `watch/providers`，随详情接口以 append_to_response 返回）。
struct WatchProviders: Decodable, Sendable, Equatable {
    /// 国家 / 地区代码 → 该地区的观看渠道。
    let results: [String: WatchRegion]

    /// 默认排序：中国大陆优先，其次常见华语 / 英语地区；未列出的地区按代码排序。
    static let preferredRegionCodes = ["CN", "HK", "TW", "SG", "US", "JP", "GB"]

    private enum CodingKeys: String, CodingKey { case results }

    init(results: [String: WatchRegion] = [:]) {
        self.results = results
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.results = ((try? container.decodeIfPresent([String: WatchRegion].self, forKey: .results)) ?? nil) ?? [:]
    }

    /// 只保留真的含有观看渠道的地区，并按偏好排序。
    var availableRegions: [WatchRegionOption] {
        results.compactMap { code, region in
            guard region.hasOffers else { return nil }
            return WatchRegionOption(code: code, name: Self.regionName(code), region: region)
        }
        .sorted { lhs, rhs in
            let left = Self.preferenceIndex(lhs.code)
            let right = Self.preferenceIndex(rhs.code)
            if left != right { return left < right }
            return lhs.code < rhs.code
        }
    }

    /// 取指定地区；地区不存在或没有渠道时回退到默认地区。
    func region(for code: String?) -> WatchRegionOption? {
        if let code, let match = availableRegions.first(where: { $0.code == code }) {
            return match
        }
        return availableRegions.first
    }

    static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private static func preferenceIndex(_ code: String) -> Int {
        preferredRegionCodes.firstIndex(of: code) ?? preferredRegionCodes.count
    }
}

/// 菜单里的一个地区选项。
struct WatchRegionOption: Identifiable, Sendable, Equatable {
    let code: String
    let name: String
    let region: WatchRegion

    var id: String { code }
}

/// 单个地区的观看渠道（TMDB 把订阅 / 免费 / 广告 / 租借 / 购买分开返回）。
struct WatchRegion: Decodable, Sendable, Equatable {
    /// TMDB 的观看页（实际跳转到 JustWatch）。
    let link: URL?
    let flatrate: [WatchProvider]?
    let free: [WatchProvider]?
    let ads: [WatchProvider]?
    let rent: [WatchProvider]?
    let buy: [WatchProvider]?

    private enum CodingKeys: String, CodingKey {
        case link, flatrate, free, ads, rent, buy
    }

    init(
        link: URL? = nil,
        flatrate: [WatchProvider]? = nil,
        free: [WatchProvider]? = nil,
        ads: [WatchProvider]? = nil,
        rent: [WatchProvider]? = nil,
        buy: [WatchProvider]? = nil
    ) {
        self.link = link
        self.flatrate = flatrate
        self.free = free
        self.ads = ads
        self.rent = rent
        self.buy = buy
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.link = (try? container.decodeIfPresent(URL.self, forKey: .link)) ?? nil
        self.flatrate = (try? container.decodeIfPresent([WatchProvider].self, forKey: .flatrate)) ?? nil
        self.free = (try? container.decodeIfPresent([WatchProvider].self, forKey: .free)) ?? nil
        self.ads = (try? container.decodeIfPresent([WatchProvider].self, forKey: .ads)) ?? nil
        self.rent = (try? container.decodeIfPresent([WatchProvider].self, forKey: .rent)) ?? nil
        self.buy = (try? container.decodeIfPresent([WatchProvider].self, forKey: .buy)) ?? nil
    }

    /// 按用途分组：订阅 / 免费 / 广告合并为「在线看」，租借与购买各自成组。
    /// 组内按 provider_id 去重后，再按 TMDB 的 display_priority 排序。
    var groups: [WatchOfferGroup] {
        [
            WatchOfferGroup(kind: .stream, providers: merge([flatrate, free, ads])),
            WatchOfferGroup(kind: .rent, providers: merge([rent])),
            WatchOfferGroup(kind: .buy, providers: merge([buy])),
        ].filter { !$0.providers.isEmpty }
    }

    var hasOffers: Bool { !groups.isEmpty }

    private func merge(_ lists: [[WatchProvider]?]) -> [WatchProvider] {
        var seen = Set<Int>()
        var merged: [WatchProvider] = []
        for list in lists {
            for provider in list ?? [] where seen.insert(provider.id).inserted {
                merged.append(provider)
            }
        }
        return merged.sorted { lhs, rhs in
            let left = lhs.displayPriority ?? Int.max
            let right = rhs.displayPriority ?? Int.max
            if left != right { return left < right }
            return lhs.providerName.localizedStandardCompare(rhs.providerName) == .orderedAscending
        }
    }
}

/// 一组观看渠道（在线看 / 租借 / 购买）。
struct WatchOfferGroup: Identifiable, Sendable, Equatable {
    let kind: WatchOfferKind
    let providers: [WatchProvider]

    var id: String { kind.rawValue }
}

enum WatchOfferKind: String, Sendable, CaseIterable {
    case stream, rent, buy

    var label: String {
        switch self {
        case .stream: return "在线看"
        case .rent: return "租借"
        case .buy: return "购买"
        }
    }
}

/// 单个观看平台。
struct WatchProvider: Decodable, Sendable, Identifiable, Hashable {
    let providerID: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    var id: Int { providerID }

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }

    init(providerID: Int, providerName: String, logoPath: String? = nil, displayPriority: Int? = nil) {
        self.providerID = providerID
        self.providerName = providerName
        self.logoPath = logoPath
        self.displayPriority = displayPriority
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = (try? container.decode(Int.self, forKey: .providerID)) ?? 0
        self.providerName = ((try? container.decodeIfPresent(String.self, forKey: .providerName)) ?? nil) ?? "未知平台"
        self.logoPath = (try? container.decodeIfPresent(String.self, forKey: .logoPath)) ?? nil
        self.displayPriority = (try? container.decodeIfPresent(Int.self, forKey: .displayPriority)) ?? nil
    }
}
