import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 分享卡画布（设计文档第 8.10 节）：3:4；画布 540×720pt，导出 @2x = 1080×1440。
enum ReceiptCanvas {
    static let size = CGSize(width: 540, height: 720)
    static let exportScale: CGFloat = 2

    static var exportPixelSize: (width: Int, height: Int) {
        (Int(size.width * exportScale), Int(size.height * exportScale))
    }
}

/// 分享卡本体：预览与导出共用同一张视图（所见即所得）。
struct ReceiptCardView: View {
    let data: ReceiptData
    let style: ReceiptStyle
    let palette: ReceiptPalette
    /// 海报处理方式：风格固有（双色调等）或「保留封面原色」。
    let posterMode: ReceiptPosterMode
    let poster: CGImage?

    var body: some View {
        ZStack {
            palette.paper.color
            overlayDecoration
            content
        }
        .frame(width: ReceiptCanvas.size.width, height: ReceiptCanvas.size.height)
        .clipShape(Rectangle())
    }

    // MARK: - 内容

    private var content: some View {
        VStack(spacing: 0) {
            topDecoration
            VStack(spacing: 0) {
                posterBlock
                titleBlock
                fieldsBlock
                Spacer(minLength: 10)
                if style.decoration == .ledgerStamp { ledgerStamp }
                footer
            }
            .padding(.horizontal, 44)
        }
        // 上下留白放在最外层：色带 / 报头等装饰同样内缩 28，四款观感一致。
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var topDecoration: some View {
        switch style.decoration {
        case .band:
            HStack {
                Text("LATENT")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.6)
                Spacer()
                Text("显影 · 元数据卡")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .opacity(0.78)
            }
            .foregroundStyle(palette.accentInk.color)
            .padding(.horizontal, 30)
            .padding(.vertical, 13)
            .background(palette.accent.color)
        case .masthead:
            VStack(spacing: 3) {
                Rectangle().fill(palette.ink.color).frame(height: 4)
                Rectangle().fill(palette.accent.color).frame(height: 2)
            }
            .padding(.horizontal, 44)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var overlayDecoration: some View {
        switch style.decoration {
        case .stub: stubDecoration
        case .sprockets: sprocketDecoration
        default: EmptyView()
        }
    }

    // MARK: 装饰

    /// 电影票根：上下齿孔 + 撕线 + 右侧竖排副券。
    private var stubDecoration: some View {
        ZStack {
            VStack {
                perforationRow
                Spacer(minLength: 0)
                perforationRow
            }
            .padding(.vertical, 12)

            HStack {
                Spacer(minLength: 0)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: 430))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .foregroundStyle(palette.ink.color.opacity(0.28))
                .frame(width: 1, height: 430)

                VStack(spacing: 8) {
                    Text("显影")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3)
                    Text(style.displayName)
                        .font(.system(size: 10))
                        .tracking(2)
                        .opacity(0.7)
                }
                .foregroundStyle(palette.ink.color)
                .fixedSize()
                .rotationEffect(.degrees(90))
            }
            .padding(.trailing, 56)
        }
    }

    private var perforationRow: some View {
        HStack(spacing: 17) {
            ForEach(0..<16, id: \.self) { _ in
                Circle()
                    .fill(palette.ink.color.opacity(0.15))
                    .frame(width: 9, height: 9)
            }
        }
    }

    /// 暗房底片：两侧片孔。
    private var sprocketDecoration: some View {
        HStack {
            sprocketColumn
            Spacer(minLength: 0)
            sprocketColumn
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 18)
    }

    private var sprocketColumn: some View {
        VStack(spacing: 15) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.ink.color.opacity(0.16))
                    .frame(width: 16, height: 22)
            }
        }
    }

    /// 账本发票：圆章。
    private var ledgerStamp: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.accent.color, lineWidth: 2.5)
                .frame(width: 64, height: 64)
            VStack(spacing: 2) {
                Text("显影")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.5)
                Text("SHARE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.4)
            }
            .foregroundStyle(palette.accent.color)
        }
        .rotationEffect(.degrees(-12))
        .padding(.top, 2)
    }

    // MARK: 海报

    private var posterBlock: some View {
        Group {
            if let processed = processedPoster {
                Image(decorative: processed, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 无海报：用该款双色调渐变占位（不伪造数据，也不留白块）。
                LinearGradient(
                    colors: [palette.duoDark.color, palette.duoLight.color],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: style.posterSize.width, height: style.posterSize.height)
        .clipShape(posterShape)
        .overlay {
            posterShape.stroke(palette.accent.color, lineWidth: 2)
        }
    }

    private var processedPoster: CGImage? {
        guard let poster else { return nil }
        return ReceiptPosterProcessor.processed(poster, mode: posterMode, palette: palette)
    }

    private var posterShape: AnyShape {
        switch style.posterShape {
        case .circle: AnyShape(Circle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: 文本

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(data.title)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .foregroundStyle(palette.ink.color)
            if let original = data.originalTitle {
                Text(original.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(palette.ink.color.opacity(0.55))
            }
            if data.rating != nil || data.voteCount != nil {
                ratingBadge
            }
        }
        .padding(.top, 14)
    }

    private var ratingBadge: some View {
        HStack(spacing: 8) {
            if let rating = data.rating {
                Text(rating)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.accentInk.color)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(palette.accent.color, in: Capsule())
            }
            if let votes = data.voteCount {
                Text(votes)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.ink.color.opacity(0.6))
            }
        }
        .padding(.top, 2)
    }

    private var fieldsBlock: some View {
        VStack(spacing: 0) {
            if !data.fields.isEmpty {
                Rectangle()
                    .fill(palette.accent.color)
                    .frame(height: 2)
                    .padding(.bottom, 4)
            }
            ForEach(data.fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(field.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(palette.accent.color)
                        .frame(width: 62, alignment: .leading)
                    Text(field.value)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(palette.ink.color)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.ink.color.opacity(0.13))
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, 10)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(palette.ink.color.opacity(0.16))
                .frame(height: 1)
            if let tagline = data.tagline {
                Text(tagline)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(palette.ink.color.opacity(0.75))
            }
            Text(footerBrand)
                .font(.system(size: 9, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(palette.ink.color.opacity(0.4))
        }
        .padding(.top, 8)
    }

    /// 页脚品牌行：电影保持 v1.2 文案；剧集 / 人物额外标注类型。
    private var footerBrand: String {
        if let subject = data.subjectLabel {
            return "显影 · \(subject) · 非商业分享"
        }
        return "显影 · 本地元数据 · 非商业分享"
    }
}

/// 分享卡渲染与导出（`ImageRenderer`）。
@MainActor
enum ReceiptRenderer {
    /// 导出尺寸的位图（1080×1440）。
    static func cgImage(
        data: ReceiptData,
        style: ReceiptStyle,
        palette: ReceiptPalette,
        posterMode: ReceiptPosterMode,
        poster: CGImage?
    ) -> CGImage? {
        let renderer = ImageRenderer(
            content: ReceiptCardView(
                data: data, style: style, palette: palette, posterMode: posterMode, poster: poster
            )
        )
        renderer.scale = ReceiptCanvas.exportScale
        return renderer.cgImage
    }

    static func pngData(
        data: ReceiptData,
        style: ReceiptStyle,
        palette: ReceiptPalette,
        posterMode: ReceiptPosterMode,
        poster: CGImage?
    ) -> Data? {
        guard let image = cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode, poster: poster
        ) else { return nil }
        return pngData(from: image)
    }

    static func pngData(from image: CGImage) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    /// 保存文件名：`显影-<片名>-分享卡.png`（去掉路径非法字符）。
    static func filename(title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "显影-\(cleaned.isEmpty ? "分享卡" : cleaned)-分享卡.png"
    }
}
