import Foundation

/// TMDB 分页响应：`{ page, results, total_pages, total_results }`。
struct Paged<Item: Sendable>: Sendable {
    let page: Int
    let items: [Item]
    let totalPages: Int
    let totalResults: Int

    /// 是否已是最后一页（页码从 1 起，空结果也算末页）。
    var isLastPage: Bool {
        if items.isEmpty { return true }
        return page >= totalPages
    }
}

extension Paged: Decodable where Item: Decodable {
    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.page = (try? container.decode(Int.self, forKey: .page)) ?? 1
        self.items = (try? container.decode([Item].self, forKey: .results)) ?? []
        self.totalPages = (try? container.decode(Int.self, forKey: .totalPages)) ?? 1
        self.totalResults = (try? container.decode(Int.self, forKey: .totalResults)) ?? self.items.count
    }
}
