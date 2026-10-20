import SwiftUI

/// 片单卡本体（设计文档第 8.10 节）：3:4；540×720pt，导出 1080×1440。
///
/// 与单部作品的票据卡共用七款调色板与封面处理方式，但版式是「多部海报网格」：
/// 顶部标题可编辑，中部 1/2/3/4 列自适应网格，底部品牌行。预览与导出共用本视图。
struct PlaylistCardView: View {
    let data: PlaylistCardData
    let style: ReceiptStyle
    /// 已按当前风格处理过的海报（原色 / 双色调 / 灰度 / 反相），按条目 id 索引。
    let posters: [String: CGImage]

    private var palette: ReceiptPalette { style.basePalette }
    private var layout: PlaylistGridLayout { .forCount(data.items.count) }

    var body: some View {
        ZStack {
            palette.paper.color
            VStack(spacing: 0) {
                Rectangle()
                    .fill(palette.accent.color)
                    .frame(height: 5)
                content
            }
        }
        .frame(width: ReceiptCanvas.size.width, height: ReceiptCanvas.size.height)
        .clipShape(Rectangle())
    }

    private var content: some View {
        VStack(spacing: 0) {
            header

            if data.items.isEmpty {
                Spacer(minLength: 0)
                Text("还没有选择作品")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink.color.opacity(0.42))
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 12)
                grid
                Spacer(minLength: 12)
            }

            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    // MARK: - 标题

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("LATENT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.4)
                Spacer(minLength: 8)
                Text("PLAYLIST")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.0)
            }
            .foregroundStyle(palette.ink.color.opacity(0.48))

            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(palette.accent.color)
                    .frame(width: 3, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(data.title)
                        .font(.system(size: 23, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .foregroundStyle(palette.ink.color)

                    Text(data.subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .tracking(0.8)
                        .lineLimit(1)
                        .foregroundStyle(palette.ink.color.opacity(0.56))
                }
            }
        }
    }

    // MARK: - 网格

    private var grid: some View {
        let rows = layout.rowIndices(for: data.items.count)
        return VStack(spacing: layout.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: layout.spacing) {
                    ForEach(rows[row], id: \.self) { index in
                        let item = data.items[index]
                        PlaylistPosterCell(
                            item: item,
                            number: index + 1,
                            size: layout.posterSize,
                            poster: posters[item.id],
                            palette: palette
                        )
                    }
                }
                // 最后一排不满时保持整排居中。
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(palette.ink.color.opacity(0.16))
                .frame(height: 1)
            HStack {
                Text("显影 · 片单 · 非商业分享")
                Spacer(minLength: 8)
                Text("LATENT")
            }
            .font(.system(size: 8, weight: .medium))
            .tracking(1.3)
            .foregroundStyle(palette.ink.color.opacity(0.4))
        }
        .padding(.top, 10)
    }
}

/// 片单网格中的一张海报：封面 + 底部渐变 + 片名 / 年份 + 序号徽标。
private struct PlaylistPosterCell: View {
    let item: PlaylistCardItem
    let number: Int
    let size: CGSize
    let poster: CGImage?
    let palette: ReceiptPalette

    var body: some View {
        ZStack(alignment: .topLeading) {
            fill

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.55)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: captionSize, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
                if let year = item.year {
                    Text(String(year))
                        .font(.system(size: 7.5, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.78)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            Text(number < 10 ? "0\(number)" : "\(number)")
                .font(.system(size: 7.5, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.accentInk.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(palette.accent.color, in: Capsule())
                .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette.ink.color.opacity(0.18), lineWidth: 1)
        }
    }

    private var captionSize: CGFloat {
        size.width >= 150 ? 10 : 8.5
    }

    @ViewBuilder
    private var fill: some View {
        if let poster {
            Image(decorative: poster, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            // 缺海报：该款双色调渐变占位，不伪造封面。
            LinearGradient(
                colors: [palette.duoDark.color, palette.duoLight.color],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
        }
    }
}

/// 片单卡渲染与导出。
@MainActor
enum PlaylistRenderer {
    static func cgImage(
        data: PlaylistCardData,
        style: ReceiptStyle,
        posterMode: ReceiptPosterMode,
        posters: [String: CGImage]
    ) -> CGImage? {
        let palette = style.basePalette
        let processed = posters.mapValues {
            ReceiptPosterProcessor.processed($0, mode: posterMode, palette: palette)
        }
        let renderer = ImageRenderer(
            content: PlaylistCardView(
                data: data,
                style: style,
                posters: processed.compactMapValues { $0 }
            )
        )
        renderer.scale = ReceiptCanvas.exportScale
        return renderer.cgImage
    }

    static func pngData(
        data: PlaylistCardData,
        style: ReceiptStyle,
        posterMode: ReceiptPosterMode,
        posters: [String: CGImage]
    ) -> Data? {
        guard let image = cgImage(
            data: data, style: style, posterMode: posterMode, posters: posters
        ) else { return nil }
        return ReceiptRenderer.pngData(from: image)
    }

    /// 保存文件名：`显影-<片单标题>-片单.png`（去掉路径非法字符）。
    static func filename(title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "显影-片单.png" }
        return "显影-\(cleaned)-片单.png"
    }
}
