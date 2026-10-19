import Testing
import SwiftUI
import CoreGraphics
@testable import Latent

/// 分享卡（设计文档第 8.10 节）测试。
@MainActor
struct ReceiptTests {

    // MARK: - 数据映射

    @Test("缺字段省略：无日期 / 时长 / 类型 / 演职员时不出现任何字段行")
    func omitsMissingFields() {
        let data = ReceiptData.build(from: MovieDetail(id: 1, title: "无数据"))

        #expect(data.fields.isEmpty)
        #expect(data.rating == nil)
        #expect(data.voteCount == nil)
        #expect(data.originalTitle == nil)
        #expect(data.tagline == nil)
    }

    @Test("完整映射：年份 / 上映 / 时长 / 类型 / 导演 / 主演")
    func mapsAvailableFields() {
        let detail = MovieDetail(
            id: 2,
            title: "沙丘：第二部",
            originalTitle: "Dune: Part Two",
            posterPath: "/dune.jpg",
            dateString: "2024-03-01",
            voteAverage: 8.1,
            voteCount: 12_345,
            genres: [Genre(id: 878, name: "科幻"), Genre(id: 12, name: "冒险")],
            tagline: "沙漠会吞噬一切",
            credits: Credits(
                cast: [
                    CastMember(id: 1, name: "提莫西·查拉梅"),
                    CastMember(id: 2, name: "赞达亚"),
                    CastMember(id: 3, name: "丽贝卡·弗格森"),
                    CastMember(id: 4, name: "奥斯汀·巴特勒"),
                ],
                crew: [
                    CrewMember(id: 9, name: "丹尼斯·维伦纽瓦", job: "Director", department: "Directing")
                ]
            ),
            runtime: 167
        )

        let data = ReceiptData.build(from: detail)

        #expect(data.title == "沙丘：第二部")
        #expect(data.originalTitle == "Dune: Part Two")
        #expect(data.rating == "8.1")
        #expect(data.voteCount == "12345 人评分")
        #expect(data.tagline == "沙漠会吞噬一切")
        #expect(data.fields.map(\.label) == ["年份", "上映", "时长", "类型", "导演", "主演"])
        #expect(data.fields.first(where: { $0.label == "类型" })?.value == "科幻 / 冒险")
        #expect(data.fields.first(where: { $0.label == "导演" })?.value == "丹尼斯·维伦纽瓦")
        // 主演最多 3 位。
        #expect(data.fields.first(where: { $0.label == "主演" })?.value == "提莫西·查拉梅 / 赞达亚 / 丽贝卡·弗格森")
    }

    @Test("页脚标语：无 tagline 时回退到简介前 60 字")
    func taglineFallsBackToOverview() {
        let longOverview = String(repeating: "字", count: 80)
        let data = ReceiptData.build(from: MovieDetail(id: 3, title: "无标语", overview: longOverview))

        #expect(data.tagline?.count == 61)
        #expect(data.tagline?.hasSuffix("…") == true)
    }

    // MARK: - 调色板

    @Test("七款固有调色板齐全：强调色互不相同")
    func palettesAreDistinct() {
        let styles = ReceiptStyle.allCases
        #expect(styles.count == 7)
        #expect(Set(styles.map(\.basePalette.accent)).count == styles.count)
    }

    @Test("强调色上的文字对比度全部达标（≥ 4.5）")
    func accentInkIsReadable() {
        for style in ReceiptStyle.allCases {
            let base = style.basePalette
            #expect(base.accent.bestContrastRatio >= 4.5, "\(style.displayName) 对比度不足")
        }
        // 咖啡杯贴：杨绿底 + 深墨字（设计文档第 8.10 节指定）。
        #expect(ReceiptStyle.cupSticker.basePalette.accentInk == ReceiptColor.darkInk)
    }

    // MARK: - 封面配色

    @Test("封面配色：纸底跟随封面明暗，墨色 / 强调色对纸底始终达标")
    func posterDrivenPaletteStaysReadable() {
        let covers: [(dominant: ReceiptColor, secondary: ReceiptColor)] = [
            // 深色封面（暗纸 + 浅墨）
            (ReceiptColor(hue: 0.62, saturation: 0.85, brightness: 0.28),
             ReceiptColor(hue: 0.07, saturation: 0.95, brightness: 0.95)),
            // 亮色封面（亮纸 + 深墨）
            (ReceiptColor(hue: 0.14, saturation: 0.80, brightness: 0.95),
             ReceiptColor(hue: 0.99, saturation: 0.85, brightness: 0.80)),
            // 黑白封面：不许凭空添色
            (ReceiptColor(hue: 0, saturation: 0.0, brightness: 0.55),
             ReceiptColor(hue: 0, saturation: 0.0, brightness: 0.30)),
        ]

        for cover in covers {
            for style in ReceiptStyle.allCases {
                let palette = ReceiptPalette.posterDriven(
                    base: style.basePalette,
                    colors: ReceiptPosterColors(dominant: cover.dominant, secondary: cover.secondary)
                )
                #expect(palette.ink.contrast(with: palette.paper) >= 7.0, "\(style.displayName) 墨色对比度不足")
                #expect(palette.accent.contrast(with: palette.paper) >= 4.5, "\(style.displayName) 强调色对比度不足")
                #expect(palette.ink.contrast(with: palette.paper) > palette.paper.relativeLuminance)
            }
        }

        // 深色封面 → 暗纸；亮色封面 → 亮纸。
        let dark = ReceiptPalette.posterDriven(
            base: ReceiptStyle.thermal.basePalette,
            colors: ReceiptPosterColors(
                dominant: ReceiptColor(hue: 0.62, saturation: 0.85, brightness: 0.28),
                secondary: ReceiptColor(hue: 0.07, saturation: 0.95, brightness: 0.95)
            )
        )
        #expect(dark.paper.relativeLuminance < 0.2)
        #expect(abs(dark.paper.hsb.hue - 0.62) < 0.03)

        let light = ReceiptPalette.posterDriven(
            base: ReceiptStyle.thermal.basePalette,
            colors: ReceiptPosterColors(
                dominant: ReceiptColor(hue: 0.14, saturation: 0.80, brightness: 0.95),
                secondary: ReceiptColor(hue: 0.99, saturation: 0.85, brightness: 0.80)
            )
        )
        #expect(light.paper.relativeLuminance > 0.7)
        #expect(light.accent.contrast(with: light.paper) >= 4.5)
    }

    @Test("黑白封面不被凭空添色（强调色保持近中性）")
    func grayscaleCoverStaysNeutral() {
        let palette = ReceiptPalette.posterDriven(
            base: ReceiptStyle.modern.basePalette,
            colors: ReceiptPosterColors(
                dominant: ReceiptColor(hue: 0, saturation: 0.0, brightness: 0.55),
                secondary: ReceiptColor(hue: 0, saturation: 0.0, brightness: 0.30)
            )
        )
        #expect(palette.accent.hsb.saturation < 0.15)
        #expect(palette.paper.hsb.saturation < 0.05)
    }

    @Test("缺封面时退回固有调色板")
    func missingCoverFallsBack() {
        let base = ReceiptStyle.modern.basePalette
        #expect(ReceiptPalette.posterDriven(base: base, colors: nil) == base)
    }

    @Test("封面取色：主色取像素最多的色簇，辅色是够鲜艳、色相拉开的第二色")
    func extractsDominantAndSecondary() throws {
        let navy = ReceiptColor(hue: 0.62, saturation: 0.85, brightness: 0.28)
        let orange = ReceiptColor(hue: 0.07, saturation: 0.95, brightness: 0.95)
        let cover = try #require(Self.cover(background: navy, subject: orange))

        let colors = try #require(ReceiptPosterProcessor.colors(of: cover))

        #expect(abs(colors.dominant.hsb.hue - navy.hsb.hue) < 0.06, "主色应落在深底色簇")
        #expect(abs(colors.secondary.hsb.hue - orange.hsb.hue) < 0.06, "辅色应取到橙色主体而不是深底")
        #expect(colors.secondary.hsb.saturation > colors.dominant.hsb.saturation)
    }

    @Test("封面取色：单色封面退回主色的明度偏移（两者仍然拉开）")
    func monochromeCoverFallsBackToShift() throws {
        let flat = ReceiptColor(hue: 0.55, saturation: 0.6, brightness: 0.45)
        let cover = try #require(Self.cover(background: flat, subject: flat))

        let colors = try #require(ReceiptPosterProcessor.colors(of: cover))

        #expect(abs(colors.dominant.hsb.brightness - flat.hsb.brightness) < 0.12)
        #expect(abs(colors.secondary.hsb.brightness - colors.dominant.hsb.brightness) > 0.2)
    }

    @Test("缺封面时取色返回 nil")
    func missingCoverHasNoColors() {
        #expect(ReceiptPosterProcessor.colors(of: nil) == nil)
    }

    // MARK: - 海报处理

    @Test("双色调：亮暗两端必须映射到不同颜色（防止整张海报塌成单色）")
    func duotoneKeepsTonalRange() {
        // 左黑右白的测试图。
        guard let source = halfToneImage() else {
            Issue.record("测试图生成失败")
            return
        }
        let palette = ReceiptStyle.thermal.basePalette
        guard let mapped = ReceiptPosterProcessor.processed(source, mode: .duotone, palette: palette) else {
            Issue.record("双色调处理失败")
            return
        }

        let darkSide = ReceiptPosterProcessor.averageColor(of: mapped.cropping(to: CGRect(x: 4, y: 20, width: 40, height: 40)))
        let lightSide = ReceiptPosterProcessor.averageColor(of: mapped.cropping(to: CGRect(x: 60, y: 20, width: 40, height: 40)))
        #expect(darkSide != nil)
        #expect(lightSide != nil)
        // 亮端应明显亮于暗端（回归：曾因映射图方向错误而两端同色）。
        if let darkSide, let lightSide {
            #expect(lightSide.relativeLuminance - darkSide.relativeLuminance > 0.3)
        }
    }

    @Test("反相双色调：整体亮度应高于正向双色调")
    func invertedDuotoneIsInverted() {
        guard let source = halfToneImage() else {
            Issue.record("测试图生成失败")
            return
        }
        let palette = ReceiptStyle.darkroom.basePalette
        let normal = ReceiptPosterProcessor.averageColor(
            of: ReceiptPosterProcessor.processed(source, mode: .duotone, palette: palette)
        )
        let inverted = ReceiptPosterProcessor.averageColor(
            of: ReceiptPosterProcessor.processed(source, mode: .invertedDuotone, palette: palette)
        )
        #expect(normal != nil)
        #expect(inverted != nil)
        if let normal, let inverted {
            #expect(inverted.relativeLuminance > normal.relativeLuminance)
        }
    }

    @Test("保留封面原色：不做灰度 / 双色调处理，整幅色彩原样保留")
    func originalModeKeepsCoverColors() {
        guard let source = Self.cover(
            background: ReceiptColor(hue: 0.60, saturation: 0.90, brightness: 0.62),
            subject: ReceiptColor(hue: 0.07, saturation: 0.95, brightness: 0.95)
        ) else {
            Issue.record("测试图生成失败")
            return
        }
        let palette = ReceiptStyle.thermal.basePalette
        let sourceAverage = ReceiptPosterProcessor.averageColor(of: source)
        let original = ReceiptPosterProcessor.averageColor(
            of: ReceiptPosterProcessor.processed(source, mode: .original, palette: palette)
        )
        let grayscale = ReceiptPosterProcessor.averageColor(
            of: ReceiptPosterProcessor.processed(source, mode: .grayscale, palette: palette)
        )

        #expect(original != nil)
        #expect(grayscale != nil)
        guard let sourceAverage, let original, let grayscale else { return }

        // 原色：平均色与源图一致（没有被任何滤镜改写）。
        #expect(abs(original.red - sourceAverage.red) < 0.05)
        #expect(abs(original.green - sourceAverage.green) < 0.05)
        #expect(abs(original.blue - sourceAverage.blue) < 0.05)
        // 而灰度模式会抽掉全部色彩。
        #expect(original.hsb.saturation > grayscale.hsb.saturation + 0.2)
        #expect(grayscale.hsb.saturation < 0.1)
    }

    /// 左半黑、右半白的测试图。
    private func halfToneImage() -> CGImage? {
        let width = 100, height = 80
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return context.makeImage()
    }

    /// 测试封面：整幅底色 + 居中主体方块（模拟「深色底 + 明亮主体」的海报）。
    private static func cover(background: ReceiptColor, subject: ReceiptColor) -> CGImage? {
        let width = 160
        let height = 240
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(
            red: background.red, green: background.green, blue: background.blue, alpha: 1
        ))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(
            red: subject.red, green: subject.green, blue: subject.blue, alpha: 1
        ))
        context.fill(CGRect(x: 45, y: 85, width: 70, height: 70))
        return context.makeImage()
    }

    // MARK: - 渲染导出

    @Test("七款风格都能导出 1080×1440 图像")
    func rendersExportSize() {
        let data = ReceiptData.build(from: MovieDetail(
            id: 1, title: "测试影片", dateString: "2024-01-01",
            voteAverage: 7.5, voteCount: 10, runtime: 100
        ))
        #expect(ReceiptCanvas.exportPixelSize == (1080, 1440))

        for style in ReceiptStyle.allCases {
            let image = ReceiptRenderer.cgImage(
                data: data, style: style, palette: style.basePalette, posterMode: style.posterMode, poster: nil
            )
            #expect(image != nil, "\(style.displayName) 渲染失败")
            #expect(image?.width == 1080)
            #expect(image?.height == 1440)
        }
    }

    @Test("导出 PNG：非空且带 PNG 签名")
    func exportsPNG() {
        let data = ReceiptData.build(from: MovieDetail(id: 1, title: "测试影片"))
        let png = ReceiptRenderer.pngData(
            data: data,
            style: .cupSticker,
            palette: ReceiptStyle.cupSticker.basePalette,
            posterMode: .original,
            poster: nil
        )

        #expect(png != nil)
        #expect((png?.count ?? 0) > 0)
        #expect(png?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("文件名清洗：去掉路径非法字符")
    func sanitizesFilename() {
        #expect(ReceiptRenderer.filename(title: "沙丘/第二部") == "显影-沙丘-第二部-分享卡.png")
        #expect(ReceiptRenderer.filename(title: "  ") == "显影-分享卡-分享卡.png")
    }
}
