import CoreGraphics
import Foundation

/// 片单卡上的一部作品（只带卡面需要的字段）。
struct PlaylistCardItem: Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let posterPath: String?

    init(id: String, title: String, year: Int? = nil, posterPath: String? = nil) {
        self.id = id
        self.title = title
        self.year = year
        self.posterPath = posterPath
    }

    init(snapshot: LibrarySnapshot) {
        self.init(
            id: snapshot.id,
            title: snapshot.title,
            year: snapshot.year,
            posterPath: snapshot.posterPath
        )
    }
}

/// 片单卡数据（v1.6，设计文档第 8.10 节）。
///
/// 与单部作品的 `ReceiptData` 分开：片单是「多部作品的集合」，没有评分 / 票数 /
/// 标语等单主体字段；标题可编辑，副标题固定标注来源与部数。
struct PlaylistCardData: Sendable, Equatable {
    /// 一张卡最多放 12 部（4 列 × 3 行）。
    static let maximumItems = 12
    /// 标题留空时的兜底。
    static let fallbackTitle = "我的片单"

    let title: String
    let subtitle: String
    let items: [PlaylistCardItem]

    init(title: String, subtitle: String, items: [PlaylistCardItem]) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? Self.fallbackTitle : trimmed
        self.subtitle = subtitle
        self.items = Array(items.prefix(Self.maximumItems))
    }

    /// 从「已选中的库条目」构建；顺序即卡片顺序（沿用列表当前排序）。
    static func build(title: String, kind: LibraryKind, items: [LibrarySnapshot]) -> PlaylistCardData {
        let mapped = items.prefix(Self.maximumItems).map(PlaylistCardItem.init(snapshot:))
        return PlaylistCardData(
            title: title,
            subtitle: "\(kind.title) · \(mapped.count) 部",
            items: mapped
        )
    }
}

/// 片单卡网格：按数量在 1 / 2 / 3 / 4 列之间切换，保证 1–12 部都不空、不挤。
///
/// 尺寸以 540×720 画布为基准；每张海报 2:3，行内居中（最后一排不满时也居中）。
struct PlaylistGridLayout: Sendable, Equatable {
    let columns: Int
    let posterSize: CGSize
    let spacing: CGFloat

    static func forCount(_ count: Int) -> PlaylistGridLayout {
        let clamped = min(max(count, 0), PlaylistCardData.maximumItems)
        switch clamped {
        case ...1:
            // 0–1 部：单列放大；一部片也能成为一张完整的封面卡。
            return PlaylistGridLayout(
                columns: 1,
                posterSize: CGSize(width: 250, height: 375),
                spacing: 0
            )
        case ...4:
            // 2–4 部：2 列，海报最大。
            return PlaylistGridLayout(
                columns: 2,
                posterSize: CGSize(width: 168, height: 252),
                spacing: 12
            )
        case ...9:
            // 5–9 部：3 列，九宫格。
            return PlaylistGridLayout(
                columns: 3,
                posterSize: CGSize(width: 114, height: 171),
                spacing: 10
            )
        default:
            // 10–12 部：4 列，支持「年度十佳」这类十部片单。
            return PlaylistGridLayout(
                columns: 4,
                posterSize: CGSize(width: 104, height: 156),
                spacing: 10
            )
        }
    }

    /// 每排对应的条目下标；空列表返回空数组。
    func rowIndices(for count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        let limited = min(count, PlaylistCardData.maximumItems)
        return stride(from: 0, to: limited, by: columns).map { start in
            Array(start..<min(start + columns, limited))
        }
    }
}
