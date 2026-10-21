import SwiftUI

/// 海报色板墙（设计文档第 14.3 节）。
///
/// 把片库海报交给现有图片管线（同一份内存 / 磁盘缓存），降采样后按封面取色，
/// 拼成一张色块马赛克。取色复用分享卡那套「色相 × 明度分簇」算法，
/// 不额外下载原图、不引入新依赖。
struct PosterPaletteWall: View {
    /// 候选条目（收藏 + 观看清单，调用方负责合并）。
    let items: [LibrarySnapshot]

    @State private var swatches: [Swatch] = []
    @State private var isLoaded = false

    struct Swatch: Identifiable, Equatable {
        let id: String
        let title: String
        let dominant: ReceiptColor
        let secondary: ReceiptColor
    }

    /// 去重后只取有封面的前 48 张——再多的色块也看不出差异，反而拖慢取色。
    private var source: [LibrarySnapshot] {
        var seen: Set<String> = []
        return Array(
            items
                .filter { $0.posterPath != nil && seen.insert($0.id).inserted }
                .prefix(48)
        )
    }

    var body: some View {
        ChartCard(title: "海报色板墙", caption: "取每张封面的主色与辅色") {
            Group {
                if !swatches.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 34, maximum: 46), spacing: 4)],
                        spacing: 4
                    ) {
                        ForEach(swatches) { swatch in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [swatch.dominant.color, swatch.secondary.color],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 46)
                                .help(swatch.title)
                                .accessibilityLabel("海报色板：\(swatch.title)")
                        }
                    }
                } else if isLoaded {
                    Text("暂无可取色的封面")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: source.map(\.id)) { await load() }
    }

    private func load() async {
        let targets = source
        guard !targets.isEmpty else {
            isLoaded = true
            return
        }

        var results: [(index: Int, swatch: Swatch)] = []
        // 分批并发：一次 6 张，既不让整面墙同时打满网络，也避开逐张等待的长耗时。
        for start in stride(from: 0, to: targets.count, by: 6) {
            let end = min(start + 6, targets.count)
            let batch = await withTaskGroup(of: (Int, Swatch?).self) { group in
                for index in start..<end {
                    let item = targets[index]
                    group.addTask { (index, await Self.swatch(for: item)) }
                }
                var collected: [(Int, Swatch?)] = []
                for await value in group { collected.append(value) }
                return collected
            }
            results.append(contentsOf: batch.compactMap { index, swatch in
                swatch.map { (index, $0) }
            })
        }

        swatches = results.sorted { $0.index < $1.index }.map(\.swatch)
        isLoaded = true
    }

    private nonisolated static func swatch(for item: LibrarySnapshot) async -> Swatch? {
        guard let path = item.posterPath,
              let image = try? await ImagePipeline.shared.image(for: path, pixelSize: 185),
              let colors = ReceiptPosterProcessor.colors(of: image)
        else { return nil }
        return Swatch(
            id: item.id,
            title: item.title,
            dominant: colors.dominant,
            secondary: colors.secondary
        )
    }
}
