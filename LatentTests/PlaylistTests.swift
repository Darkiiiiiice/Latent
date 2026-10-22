import Testing
import SwiftUI
import CoreGraphics
@testable import Latent

/// 片单卡（设计文档第 8.10 节）测试。
@MainActor
struct PlaylistTests {

    // MARK: - 数据映射

    private static func snapshots(_ count: Int) -> [LibrarySnapshot] {
        (1...count).map { index in
            LibrarySnapshot(
                mediaKind: .movie,
                tmdbID: index,
                title: "片名 \(index)",
                originalTitle: nil,
                year: 1999 + index,
                posterPath: "/poster\(index).jpg",
                voteAverage: 7.0,
                addedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }

    @Test("片单最多 12 部，保留列表顺序，标题留空有兜底")
    func buildsAndCapsItems() {
        let data = PlaylistCardData.build(
            title: "  ",
            kind: .favorites,
            items: Self.snapshots(14)
        )

        #expect(data.title == PlaylistCardData.fallbackTitle)
        #expect(data.items.count == 12)
        #expect(data.subtitle == "收藏 · 12 部")
        #expect(data.items.first?.title == "片名 1")
        #expect(data.items.last?.title == "片名 12")
        #expect(data.items.first?.year == 2000)
        #expect(data.items.first?.posterPath == "/poster1.jpg")
    }

    @Test("自定义标题保留，副标题跟随来源与选中数量")
    func keepsCustomTitle() {
        let data = PlaylistCardData.build(
            title: "我的年度十佳",
            kind: .watchlist,
            items: Self.snapshots(3)
        )

        #expect(data.title == "我的年度十佳")
        #expect(data.subtitle == "观看清单 · 3 部")
        #expect(data.items.count == 3)
    }

    // MARK: - 默认预选（v1.6.1「0 部」回归）

    @Test("快照为空时预选为空，不再误报「已全选」")
    func emptySnapshotHasNoSelection() {
        let selection = PlaylistCardData.initialSelection(from: [])
        #expect(selection.isEmpty)

        let data = PlaylistCardData.build(title: "我的收藏", kind: .favorites, items: [])
        #expect(data.items.isEmpty)
        #expect(data.subtitle == "收藏 · 0 部")
    }

    @Test("快照变化时按新列表重新预选前 12 部")
    func selectionFollowsSnapshot() {
        let fourteen = Self.snapshots(14)
        let all = PlaylistCardData.initialSelection(from: fourteen)
        #expect(all.count == 12)
        #expect(all.contains(fourteen[0].id))
        #expect(all.contains(fourteen[11].id))
        #expect(!all.contains(fourteen[12].id))

        // 从空的旧快照切到非空快照：预选必须补齐，而不是停留在空集合。
        let recovered = PlaylistCardData.initialSelection(from: Self.snapshots(3))
        #expect(recovered.count == 3)
    }

    // MARK: - 网格

    @Test("网格按数量切 2 / 3 / 4 列，最后一排下标正确")
    func adaptsGridColumns() {
        #expect(PlaylistGridLayout.forCount(0).columns == 1)
        #expect(PlaylistGridLayout.forCount(1).columns == 1)
        #expect(PlaylistGridLayout.forCount(2).columns == 2)
        #expect(PlaylistGridLayout.forCount(4).columns == 2)
        #expect(PlaylistGridLayout.forCount(5).columns == 3)
        #expect(PlaylistGridLayout.forCount(9).columns == 3)
        #expect(PlaylistGridLayout.forCount(10).columns == 4)
        #expect(PlaylistGridLayout.forCount(12).columns == 4)

        let single = PlaylistGridLayout.forCount(1)
        #expect(single.posterSize == CGSize(width: 250, height: 375))
        #expect(single.rowIndices(for: 1) == [[0]])

        let ten = PlaylistGridLayout.forCount(10)
        #expect(ten.rowIndices(for: 10) == [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9]])
        #expect(ten.posterSize == CGSize(width: 104, height: 156))

        #expect(PlaylistGridLayout.forCount(0).rowIndices(for: 0).isEmpty)
        #expect(PlaylistGridLayout.forCount(9).rowIndices(for: 9).count == 3)
    }

    // MARK: - 渲染导出

    @Test("空片单与 12 部片单都能导出 1080×1440")
    func rendersEmptyAndFull() throws {
        let empty = PlaylistCardData(title: "空片单", subtitle: "收藏 · 0 部", items: [])
        let emptyImage = try #require(PlaylistRenderer.cgImage(
            data: empty, style: .thermal, posterMode: .duotone, posters: [:]
        ))
        #expect(emptyImage.width == 1080)
        #expect(emptyImage.height == 1440)

        let full = PlaylistCardData.build(
            title: "我的年度十佳", kind: .favorites, items: Self.snapshots(12)
        )
        let fullImage = try #require(PlaylistRenderer.cgImage(
            data: full, style: .modern, posterMode: .duotone, posters: [:]
        ))
        #expect(fullImage.width == 1080)
        #expect(fullImage.height == 1440)
    }

    @Test("十款风格都能渲染片单卡")
    func rendersAllStyles() {
        let data = PlaylistCardData.build(
            title: "我的收藏", kind: .favorites, items: Self.snapshots(9)
        )
        for style in ReceiptStyle.allCases {
            let image = PlaylistRenderer.cgImage(
                data: data,
                style: style,
                posterMode: style.posterMode,
                posters: [:]
            )
            #expect(image != nil, "\(style.displayName) 片单卡渲染失败")
            #expect(image?.width == 1080)
            #expect(image?.height == 1440)
        }
    }

    @Test("有海报时按风格处理后仍能导出 PNG")
    func rendersWithPosterAndExportsPNG() throws {
        let data = PlaylistCardData.build(
            title: "沙丘片单", kind: .favorites, items: Self.snapshots(2)
        )
        let poster = try #require(Self.solidImage())
        let posters = [data.items[0].id: poster]

        let png = try #require(PlaylistRenderer.pngData(
            data: data, style: .darkroom, posterMode: .invertedDuotone, posters: posters
        ))
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(png.count > 0)
    }

    @Test("片单文件名清洗：去掉路径非法字符")
    func sanitizesFilename() {
        #expect(PlaylistRenderer.filename(title: "我的年度十佳") == "显影-我的年度十佳-片单.png")
        #expect(PlaylistRenderer.filename(title: "沙丘/第二部") == "显影-沙丘-第二部-片单.png")
        #expect(PlaylistRenderer.filename(title: "  ") == "显影-片单.png")
    }

    private static func solidImage() -> CGImage? {
        let width = 120
        let height = 180
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
