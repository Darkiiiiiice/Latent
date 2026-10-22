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

/// 分享卡版式（v1.28 起）：配色之外的第二个维度，只改排版，不改调色板。
enum ReceiptLayout: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// 海报居中、信息在下（v1.2 起的默认版式）。
    case classic
    /// 左海报、右信息，字段多也不挤。
    case split
    /// 海报铺满整卡，信息压在底部渐隐层上。
    case immersive
    /// 文字优先的档案卡：标题在左、封面作缩略图。
    case index
    /// 杂志跨页（v1.29）：顶部横幅出血海报，下半左右双栏。
    case magazine
    /// 文字海报（v1.29）：不放海报，纯排版大字。
    case billboard
    /// 竖排（v1.29）：标题逐字竖排，封面在左。
    case column

    var id: String { rawValue }

    /// 选择器标签（一律两字，七段在 340pt 宽的面板里才不会截断）。
    var displayName: String {
        switch self {
        case .classic: "经典"
        case .split: "侧栏"
        case .immersive: "全幅"
        case .index: "索引"
        case .magazine: "杂志"
        case .billboard: "大字"
        case .column: "竖排"
        }
    }

    var hint: String {
        switch self {
        case .classic: "海报居中，信息在下"
        case .split: "左图右文，字段多也不挤"
        case .immersive: "海报铺满，信息压底"
        case .index: "文字优先，封面作缩略图"
        case .magazine: "顶部横幅海报，下分两栏"
        case .billboard: "不放海报，纯排版大字"
        case .column: "标题逐字竖排，封面在左"
        }
    }
}

/// 分享卡细节调节（v1.30）：字号 / 边距 / 页脚标语 / 水印，叠在版式与配色之上。
///
/// 只调文字与留白，不动海报尺寸与画布比例，因此七款版式 × 十八款配色都能沿用。
struct ReceiptTuning: Hashable, Sendable {
    /// 字号档位（百分比作用于标题、字段与页脚文字）。
    enum TypeScale: String, CaseIterable, Identifiable, Hashable, Sendable {
        case compact
        case regular
        case large

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .compact: "紧凑"
            case .regular: "标准"
            case .large: "放大"
            }
        }

        /// 放大上限压到 1.08：经典版式在六字段 + 放大时刚好填满画布，再大就会被裁。
        var factor: CGFloat {
            switch self {
            case .compact: 0.92
            case .regular: 1.0
            case .large: 1.08
            }
        }
    }

    /// 边距档位（左右内缩与上下留白）。
    enum Margin: String, CaseIterable, Identifiable, Hashable, Sendable {
        case tight
        case regular
        case roomy

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tight: "窄"
            case .regular: "标准"
            case .roomy: "宽"
            }
        }

        var horizontalInset: CGFloat {
            switch self {
            case .tight: 32
            case .regular: 44
            case .roomy: 56
            }
        }

        var verticalInset: CGFloat {
            switch self {
            case .tight: 20
            case .regular: 28
            case .roomy: 36
            }
        }
    }

    var typeScale: TypeScale = .regular
    var margin: Margin = .regular
    /// 自定义页脚标语（最多 24 字）；为空时用数据自带的 tagline。
    var customTagline: String = ""
    /// 页脚品牌行（"显影 · 本地元数据 · 非商业分享"）。
    var showsWatermark: Bool = true

    static let standard = ReceiptTuning()

    /// 按档位缩放字号；取整避免半像素在导出时糊边。
    func size(_ base: CGFloat) -> CGFloat {
        (base * typeScale.factor).rounded()
    }

    /// 页脚标语：自定义优先，空白视为未填。
    func tagline(fallback: String?) -> String? {
        let custom = customTagline.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? fallback : custom
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
    /// 版式（v1.28；默认经典版式）。
    var layout: ReceiptLayout = .classic
    /// 细节调节（v1.30；默认标准字号 + 标准边距 + 水印开）。
    var tuning: ReceiptTuning = .standard

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

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .classic: classicContent
        case .split: splitContent
        case .immersive: immersiveContent
        case .index: indexContent
        case .magazine: magazineContent
        case .billboard: billboardContent
        case .column: columnContent
        }
    }

    /// 经典：海报居中、信息在下（v1.2 起的版式）。
    private var classicContent: some View {
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
            .padding(.horizontal, tuning.margin.horizontalInset)
        }
        // 上下留白放在最外层：色带 / 报头等装饰同样内缩 28，四款观感一致。
        .padding(.vertical, tuning.margin.verticalInset)
    }

    /// 侧栏：左海报、右标题与字段。
    private var splitContent: some View {
        VStack(spacing: 0) {
            topDecoration
            HStack(alignment: .top, spacing: 30) {
                posterBlock(size: CGSize(width: 168, height: 252))
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.title)
                        .font(.system(size: tuning.size(23), weight: .bold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(palette.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let original = data.originalTitle {
                        Text(original.uppercased())
                            .font(.system(size: tuning.size(10), weight: .medium))
                            .tracking(1.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(palette.ink.color.opacity(0.55))
                            .padding(.top, 5)
                    }
                    if data.rating != nil || data.voteCount != nil {
                        ratingBadge
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    compactFields
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, tuning.margin.horizontalInset)
            .padding(.top, 22)
            Spacer(minLength: 12)
            footer
                .padding(.horizontal, tuning.margin.horizontalInset)
        }
        .padding(.vertical, tuning.margin.verticalInset)
    }

    /// 全幅：海报铺满整卡，信息压在底部渐隐层上。
    private var immersiveContent: some View {
        ZStack(alignment: .bottom) {
            fullBleedPoster
            LinearGradient(
                stops: [
                    .init(color: palette.paper.color.opacity(0), location: 0),
                    .init(color: palette.paper.color.opacity(0.82), location: 0.55),
                    .init(color: palette.paper.color.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(spacing: 0) {
                topDecoration
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.title)
                        .font(.system(size: tuning.size(24), weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(palette.ink.color)
                    if let original = data.originalTitle {
                        Text(original.uppercased())
                            .font(.system(size: tuning.size(10), weight: .medium))
                            .tracking(1.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(palette.ink.color.opacity(0.6))
                            .padding(.top, 4)
                    }
                    if data.rating != nil || data.voteCount != nil {
                        ratingBadge
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    compactFields
                    footer
                        .padding(.top, 8)
                }
                .padding(.horizontal, tuning.margin.horizontalInset)
                .padding(.bottom, tuning.margin.verticalInset)
            }
            .padding(.top, tuning.margin.verticalInset)
        }
    }

    /// 索引：文字优先的档案卡，封面缩略图在右上。
    private var indexContent: some View {
        VStack(spacing: 0) {
            topDecoration
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(indexLabel)
                            .font(.system(size: tuning.size(9), weight: .bold))
                            .tracking(2.4)
                            .foregroundStyle(palette.accent.color)
                        Text(data.title)
                            .font(.system(size: tuning.size(24), weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(palette.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                        if let original = data.originalTitle {
                            Text(original.uppercased())
                                .font(.system(size: tuning.size(10), weight: .medium))
                                .tracking(1.6)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(palette.ink.color.opacity(0.55))
                        }
                        if data.rating != nil || data.voteCount != nil {
                            ratingBadge
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 0)
                    posterBlock(size: CGSize(width: 108, height: 162))
                }
                .padding(.top, 18)

                Rectangle()
                    .fill(palette.ink.color.opacity(0.2))
                    .frame(height: 1)
                    .padding(.top, 16)

                compactFields

                Spacer(minLength: 10)
                footer
            }
            .padding(.horizontal, tuning.margin.horizontalInset)
        }
        .padding(.vertical, tuning.margin.verticalInset)
    }

    private var indexLabel: String {
        if let subject = data.subjectLabel {
            return "显影 · \(subject)档案"
        }
        return "显影 · 电影档案"
    }

    /// 杂志跨页（v1.29）：顶部横幅海报出血铺满左右，下半左标题右字段。
    private var magazineContent: some View {
        VStack(spacing: 0) {
            topDecoration
            bleedPoster(size: CGSize(width: ReceiptCanvas.size.width, height: 250))
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.title)
                        .font(.system(size: tuning.size(25), weight: .bold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(palette.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let original = data.originalTitle {
                        Text(original.uppercased())
                            .font(.system(size: tuning.size(10), weight: .medium))
                            .tracking(1.6)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(palette.ink.color.opacity(0.55))
                            .padding(.top, 6)
                    }
                    if data.rating != nil || data.voteCount != nil {
                        ratingBadge
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 196, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    compactFields
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, tuning.margin.horizontalInset)
            .padding(.top, 22)

            Spacer(minLength: 10)
            footer
                .padding(.horizontal, tuning.margin.horizontalInset)
        }
        .padding(.top, tuning.margin.verticalInset)
        .padding(.bottom, tuning.margin.verticalInset)
    }

    /// 文字海报（v1.29）：不放海报，用超大标题占住视觉重心。
    private var billboardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topDecoration
            VStack(alignment: .leading, spacing: 0) {
                Text(indexLabel)
                    .font(.system(size: tuning.size(9), weight: .bold))
                    .tracking(2.6)
                    .foregroundStyle(palette.accent.color)

                Spacer(minLength: 0)

                Text(data.title)
                    .font(.system(size: tuning.size(46), weight: .bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.42)
                    .foregroundStyle(palette.ink.color)
                    .fixedSize(horizontal: false, vertical: true)

                if let original = data.originalTitle {
                    Text(original.uppercased())
                        .font(.system(size: tuning.size(11), weight: .medium))
                        .tracking(2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(palette.ink.color.opacity(0.55))
                        .padding(.top, 10)
                }

                if data.rating != nil || data.voteCount != nil {
                    ratingBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }

                compactFields

                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, tuning.margin.horizontalInset)
        }
        .padding(.vertical, tuning.margin.verticalInset)
    }

    /// 竖排（v1.29）：封面在左、字段在其下，标题在右逐字向下排。
    private var columnContent: some View {
        VStack(spacing: 0) {
            topDecoration
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 0) {
                    posterBlock(size: CGSize(width: 150, height: 225))
                    compactFields
                    Spacer(minLength: 0)
                }
                .frame(width: 150, alignment: .leading)

                VStack(alignment: .trailing, spacing: 0) {
                    verticalTitle
                    if let original = data.originalTitle {
                        Text(original.uppercased())
                            .font(.system(size: tuning.size(10), weight: .medium))
                            .tracking(1.6)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(palette.ink.color.opacity(0.55))
                            .padding(.top, 14)
                    }
                    if data.rating != nil || data.voteCount != nil {
                        ratingBadge
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                // 给票根的虚线副券留出右边距，竖排字不压线。
                .padding(.trailing, 20)
            }
            .padding(.horizontal, tuning.margin.horizontalInset)
            .padding(.top, 18)

            Spacer(minLength: 12)
            footer
                .padding(.horizontal, tuning.margin.horizontalInset)
        }
        .padding(.vertical, tuning.margin.verticalInset)
    }

    /// 竖排标题：中日韩标题逐字向下排（最多 9 字），拉丁标题回退为横排换行。
    @ViewBuilder
    private var verticalTitle: some View {
        if fitsVerticalTypesetting {
            VStack(spacing: 0) {
                ForEach(Array(data.title.prefix(9).enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: tuning.size(26), weight: .bold))
                        .foregroundStyle(palette.ink.color)
                }
            }
        } else {
            Text(data.title)
                .font(.system(size: tuning.size(26), weight: .bold))
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .foregroundStyle(palette.ink.color)
        }
    }

    /// 标题是否适合竖排：中日韩字符过半才算（「Dune: Part Two」逐字竖排会很怪）。
    private var fitsVerticalTypesetting: Bool {
        let characters = data.title.filter { !$0.isWhitespace }
        guard !characters.isEmpty else { return false }
        let cjkCount = characters.filter { character in
            character.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                     0x3040...0x30FF, 0xAC00...0xD7AF:
                    true
                default:
                    false
                }
            }
        }.count
        return cjkCount * 2 >= characters.count
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
            .padding(.horizontal, tuning.margin.horizontalInset)
        case .horizon:
            horizonDecoration
        case .slate:
            slateDecoration
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var overlayDecoration: some View {
        switch style.decoration {
        case .stub: stubDecoration
        case .sprockets: sprocketDecoration
        case .neonFrame: neonFrame
        default: EmptyView()
        }
    }

    // MARK: 装饰

    /// 落日放映（v1.26）：顶部光谱带（亮部 → 强调 → 暗部）+ 一条细墨线收边。
    private var horizonDecoration: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    palette.duoLight.color,
                    palette.accent.color,
                    palette.duoDark.color,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 7)
            Rectangle()
                .fill(palette.ink.color.opacity(0.22))
                .frame(height: 1)
        }
    }

    /// 场记板（v1.26）：顶部黑白相间的打板条。
    private var slateDecoration: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<18, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2)
                              ? palette.accent.color
                              : palette.ink.color.opacity(0.92))
                }
            }
            .frame(height: 22)
            Rectangle()
                .fill(palette.ink.color.opacity(0.3))
                .frame(height: 1)
        }
    }

    /// 午夜场（v1.26）：双线霓虹外框，内线弱一档，避免抢海报。
    private var neonFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.accent.color, lineWidth: 2)
                .padding(14)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.accent.color.opacity(0.32), lineWidth: 1)
                .padding(21)
        }
    }

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
        posterBlock(size: style.posterSize)
    }

    private func posterBlock(size: CGSize) -> some View {
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
        .frame(width: size.width, height: size.height)
        .clipShape(posterShape)
        .overlay {
            posterShape.stroke(palette.accent.color, lineWidth: 2)
        }
    }

    /// 全幅版式用：海报铺满整卡（无海报时同样用双色调占位）。
    private var fullBleedPoster: some View {
        bleedPoster(size: ReceiptCanvas.size)
    }

    /// 出血海报：按给定尺寸铺满并裁切（杂志版式的横幅也走这一支）。
    private func bleedPoster(size: CGSize) -> some View {
        Group {
            if let processed = processedPoster {
                Image(decorative: processed, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [palette.duoDark.color, palette.duoLight.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
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
                .font(.system(size: tuning.size(26), weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .foregroundStyle(palette.ink.color)
            if let original = data.originalTitle {
                Text(original.uppercased())
                    .font(.system(size: tuning.size(11), weight: .medium))
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
                    .font(.system(size: tuning.size(14), weight: .heavy))
                    .foregroundStyle(palette.accentInk.color)
                    .padding(.horizontal, tuning.size(11))
                    .padding(.vertical, tuning.size(4))
                    .background(palette.accent.color, in: Capsule())
            }
            if let votes = data.voteCount {
                Text(votes)
                    .font(.system(size: tuning.size(11)))
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
                        .font(.system(size: tuning.size(11), weight: .bold))
                        .tracking(2)
                        .foregroundStyle(palette.accent.color)
                        .frame(width: tuning.size(62), alignment: .leading)
                    Text(field.value)
                        .font(.system(size: tuning.size(13), weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(palette.ink.color)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, tuning.size(7))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.ink.color.opacity(0.13))
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, 10)
    }

    /// 紧凑字段表（侧栏 / 全幅 / 索引用；行高比经典版式小一档）。
    private var compactFields: some View {
        VStack(spacing: 0) {
            if !data.fields.isEmpty {
                Rectangle()
                    .fill(palette.accent.color)
                    .frame(height: 2)
                    .padding(.bottom, 3)
            }
            ForEach(data.fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(field.label.uppercased())
                        .font(.system(size: tuning.size(10), weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(palette.accent.color)
                        .frame(width: tuning.size(48), alignment: .leading)
                    Text(field.value)
                        .font(.system(size: tuning.size(12), weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(palette.ink.color)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, tuning.size(5))
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
        let tagline = tuning.tagline(fallback: data.tagline)
        return VStack(spacing: tuning.size(7)) {
            Rectangle()
                .fill(palette.ink.color.opacity(0.16))
                .frame(height: 1)
            if let tagline {
                Text(tagline)
                    .font(.system(size: tuning.size(12)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(palette.ink.color.opacity(0.75))
            }
            if tuning.showsWatermark {
                Text(footerBrand)
                    .font(.system(size: tuning.size(9), weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(palette.ink.color.opacity(0.4))
            }
        }
        .padding(.top, tuning.size(8))
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
        poster: CGImage?,
        layout: ReceiptLayout = .classic,
        tuning: ReceiptTuning = .standard
    ) -> CGImage? {
        let renderer = ImageRenderer(
            content: ReceiptCardView(
                data: data, style: style, palette: palette, posterMode: posterMode,
                poster: poster, layout: layout, tuning: tuning
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
        poster: CGImage?,
        layout: ReceiptLayout = .classic,
        tuning: ReceiptTuning = .standard
    ) -> Data? {
        guard let image = cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, tuning: tuning
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
