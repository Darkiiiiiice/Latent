import SwiftUI
import CoreImage

/// 分享卡配色（设计文档第 8.10 节）。
///
/// **十八款风格的固有调色板（v1.2 的七款 + v1.26 的三款 + v1.27 的八款编辑器主题）**。双层机制：
/// ① 固有调色板（`ReceiptStyle.basePalette`）；
/// ② 海报驱动动态取色（`ReceiptPalette.dynamic(base:poster:)` —— 色相取自海报主色，
/// 饱和度 / 明度约束在风格固有区间内，因此十八款仍互相可辨识）。
enum ReceiptStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case thermal
    case ticketStub
    case darkroom
    case letterpress
    case ledger
    case modern
    case cupSticker
    case midnight
    case sunset
    case clapper
    // v1.27：编辑器主题（配色取自常见的代码配色方案）
    case dracula
    case nord
    case monokai
    case oneDark
    case solarized
    case gruvbox
    case catppuccin
    case tokyoNight

    var id: String { rawValue }

    /// 风格分组：界面按组展示，`allCases` 顺序仍是持久化与导出的唯一键。
    enum Family: Hashable, Sendable {
        /// 电影感（票据、胶片、印刷等实体意象）。
        case cinematic
        /// 编辑器主题（取自常见代码配色，无实体装饰）。
        case editor
    }

    var family: Family {
        switch self {
        case .dracula, .nord, .monokai, .oneDark, .solarized, .gruvbox, .catppuccin, .tokyoNight:
            .editor
        default:
            .cinematic
        }
    }

    static var cinematic: [ReceiptStyle] { allCases.filter { $0.family == .cinematic } }
    static var editorThemes: [ReceiptStyle] { allCases.filter { $0.family == .editor } }

    /// 界面显示名（`allCases` 顺序即界面顺序）。
    var displayName: String {
        switch self {
        case .thermal: "热敏小票"
        case .ticketStub: "电影票根"
        case .darkroom: "暗房底片"
        case .letterpress: "铅字报头"
        case .ledger: "账本发票"
        case .modern: "现代票据"
        case .cupSticker: "咖啡杯贴"
        case .midnight: "午夜场"
        case .sunset: "落日放映"
        case .clapper: "场记板"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .monokai: "Monokai"
        case .oneDark: "One Dark"
        case .solarized: "Solarized"
        case .gruvbox: "Gruvbox"
        case .catppuccin: "Catppuccin"
        case .tokyoNight: "Tokyo Night"
        }
    }

    /// 固有调色板（纸底 / 墨色 / 强调 / 双色调暗部与亮部）。
    var basePalette: ReceiptPalette {
        switch self {
        case .thermal:
            ReceiptPalette(paper: ReceiptColor(hex: 0xFFFFFF), ink: ReceiptColor(hex: 0x1A1A20),
                           accent: ReceiptColor(hex: 0x6C4CF1),
                           duoDark: ReceiptColor(hex: 0x2B1D6B), duoLight: ReceiptColor(hex: 0xFF7AD9))
        case .ticketStub:
            ReceiptPalette(paper: ReceiptColor(hex: 0x4A1024), ink: ReceiptColor(hex: 0xF6E7C6),
                           accent: ReceiptColor(hex: 0xE8B54A),
                           duoDark: ReceiptColor(hex: 0x4A1024), duoLight: ReceiptColor(hex: 0xF3C465))
        case .darkroom:
            ReceiptPalette(paper: ReceiptColor(hex: 0x0A0C10), ink: ReceiptColor(hex: 0xE6F2F6),
                           accent: ReceiptColor(hex: 0xFF3B3B),
                           duoDark: ReceiptColor(hex: 0x062A3C), duoLight: ReceiptColor(hex: 0x7FE9FF))
        case .letterpress:
            ReceiptPalette(paper: ReceiptColor(hex: 0xDDE5D2), ink: ReceiptColor(hex: 0x1D2620),
                           accent: ReceiptColor(hex: 0xB43325),
                           duoDark: ReceiptColor(hex: 0x2A3A24), duoLight: ReceiptColor(hex: 0xE9DFA8))
        case .ledger:
            ReceiptPalette(paper: ReceiptColor(hex: 0xFFFFFF), ink: ReceiptColor(hex: 0x10203C),
                           accent: ReceiptColor(hex: 0xC4362B),
                           duoDark: ReceiptColor(hex: 0x16305A), duoLight: ReceiptColor(hex: 0xCFE0F5))
        case .modern:
            ReceiptPalette(paper: ReceiptColor(hex: 0x080A14), ink: ReceiptColor(hex: 0xEDEEF5),
                           accent: ReceiptColor(hex: 0x7C6CFF),
                           duoDark: ReceiptColor(hex: 0x241B54), duoLight: ReceiptColor(hex: 0xB9A8FF))
        case .cupSticker:
            ReceiptPalette(paper: ReceiptColor(hex: 0x0C0C0E), ink: ReceiptColor(hex: 0xEAF8E6),
                           accent: ReceiptColor(hex: 0xB8FF3D),
                           duoDark: ReceiptColor(hex: 0x0C1406), duoLight: ReceiptColor(hex: 0xD6FF7A))
        case .midnight:
            ReceiptPalette(paper: ReceiptColor(hex: 0x05070C), ink: ReceiptColor(hex: 0xEAF7FF),
                           accent: ReceiptColor(hex: 0x19E3FF),
                           duoDark: ReceiptColor(hex: 0x02202E), duoLight: ReceiptColor(hex: 0x9AF4FF))
        case .sunset:
            ReceiptPalette(paper: ReceiptColor(hex: 0x150A08), ink: ReceiptColor(hex: 0xFFF0E2),
                           accent: ReceiptColor(hex: 0xFF6B1A),
                           duoDark: ReceiptColor(hex: 0x3D0A12), duoLight: ReceiptColor(hex: 0xFFB07A))
        case .clapper:
            ReceiptPalette(paper: ReceiptColor(hex: 0x0B0B0C), ink: ReceiptColor(hex: 0xF4F4F0),
                           accent: ReceiptColor(hex: 0xFFC400),
                           duoDark: ReceiptColor(hex: 0x1A1A1A), duoLight: ReceiptColor(hex: 0xE6E6E6))
        // 编辑器主题：纸底取各自背景色，墨色取前景色（必要时提亮到可读），
        // 强调色取各自的关键字 / 强调色，双色调取「注释 / 字符串」这类次要色彩。
        case .dracula:
            ReceiptPalette(paper: ReceiptColor(hex: 0x282A36), ink: ReceiptColor(hex: 0xF8F8F2),
                           accent: ReceiptColor(hex: 0xBD93F9),
                           duoDark: ReceiptColor(hex: 0x44475A), duoLight: ReceiptColor(hex: 0xFF79C6))
        case .nord:
            ReceiptPalette(paper: ReceiptColor(hex: 0x2E3440), ink: ReceiptColor(hex: 0xECEFF4),
                           accent: ReceiptColor(hex: 0x88C0D0),
                           duoDark: ReceiptColor(hex: 0x4C566A), duoLight: ReceiptColor(hex: 0x8FBCBB))
        case .monokai:
            ReceiptPalette(paper: ReceiptColor(hex: 0x272822), ink: ReceiptColor(hex: 0xF8F8F2),
                           accent: ReceiptColor(hex: 0xA6E22E),
                           duoDark: ReceiptColor(hex: 0x3E3D32), duoLight: ReceiptColor(hex: 0xF92672))
        case .oneDark:
            ReceiptPalette(paper: ReceiptColor(hex: 0x282C34), ink: ReceiptColor(hex: 0xD7DAE0),
                           accent: ReceiptColor(hex: 0x61AFEF),
                           duoDark: ReceiptColor(hex: 0x3E4451), duoLight: ReceiptColor(hex: 0x98C379))
        case .solarized:
            ReceiptPalette(paper: ReceiptColor(hex: 0x002B36), ink: ReceiptColor(hex: 0xEEE8D5),
                           accent: ReceiptColor(hex: 0xB58900),
                           duoDark: ReceiptColor(hex: 0x073642), duoLight: ReceiptColor(hex: 0x2AA198))
        case .gruvbox:
            ReceiptPalette(paper: ReceiptColor(hex: 0x282828), ink: ReceiptColor(hex: 0xEBDBB2),
                           accent: ReceiptColor(hex: 0xFABD2F),
                           duoDark: ReceiptColor(hex: 0x3C3836), duoLight: ReceiptColor(hex: 0xD3869B))
        case .catppuccin:
            ReceiptPalette(paper: ReceiptColor(hex: 0x1E1E2E), ink: ReceiptColor(hex: 0xCDD6F4),
                           accent: ReceiptColor(hex: 0xCBA6F7),
                           duoDark: ReceiptColor(hex: 0x45475A), duoLight: ReceiptColor(hex: 0xF5C2E7))
        case .tokyoNight:
            ReceiptPalette(paper: ReceiptColor(hex: 0x1A1B26), ink: ReceiptColor(hex: 0xC0CAF5),
                           accent: ReceiptColor(hex: 0x7AA2F7),
                           duoDark: ReceiptColor(hex: 0x414868), duoLight: ReceiptColor(hex: 0xBB9AF7))
        }
    }

    /// 海报处理方式（随风格）。
    var posterMode: ReceiptPosterMode {
        switch self {
        case .darkroom: .invertedDuotone
        case .letterpress, .clapper: .grayscale
        default: .duotone
        }
    }

    /// 海报块形状。
    var posterShape: ReceiptPosterShape {
        switch self {
        case .cupSticker: .circle
        default: .rounded
        }
    }

    /// 海报块尺寸（pt，画布为 540×720）。默认 2:3 竖版。
    var posterSize: CGSize {
        switch self {
        case .cupSticker: CGSize(width: 150, height: 150)
        case .ledger: CGSize(width: 134, height: 200)
        default: CGSize(width: 160, height: 240)
        }
    }

    /// 风格装饰（顶部色带 / 齿孔 / 片孔 / 报头双线 / 印章）。
    var decoration: ReceiptDecoration {
        switch self {
        case .thermal: .none
        case .ticketStub: .stub
        case .darkroom: .sprockets
        case .letterpress: .masthead
        case .ledger: .ledgerStamp
        case .modern: .none
        case .cupSticker: .band
        case .midnight: .neonFrame
        case .sunset: .horizon
        case .clapper: .slate
        // 编辑器主题只换配色，不加实体装饰（保持干净的「代码页」观感）。
        case .dracula, .nord, .monokai, .oneDark,
             .solarized, .gruvbox, .catppuccin, .tokyoNight: .none
        }
    }
}

enum ReceiptPosterMode: Sendable {
    /// 灰度 → 双色调渐变映射（暗部 → 亮部）。
    case duotone
    /// 仅灰度（铅字报头）。
    case grayscale
    /// 双色调后反相（暗房底片）。
    case invertedDuotone
    /// 保留封面原色（不套双色调 / 灰度，界面上是「保留封面原色」开关）。
    case original
}

enum ReceiptPosterShape: Sendable {
    case circle
    case rounded
}

enum ReceiptDecoration: Hashable, Sendable {
    case none
    case band
    case stub
    case sprockets
    case masthead
    case ledgerStamp
    /// 午夜场：双线霓虹外框（v1.26）。
    case neonFrame
    /// 落日放映：顶部光谱渐变带（v1.26）。
    case horizon
    /// 场记板：顶部黑白斜条（v1.26）。
    case slate
}

/// 分享卡调色板（纸底 / 墨色 / 强调 / 强调上的文字 / 双色调两端）。
struct ReceiptPalette: Sendable, Equatable {
    var paper: ReceiptColor
    var ink: ReceiptColor
    var accent: ReceiptColor
    var accentInk: ReceiptColor
    var duoDark: ReceiptColor
    var duoLight: ReceiptColor

    init(
        paper: ReceiptColor,
        ink: ReceiptColor,
        accent: ReceiptColor,
        duoDark: ReceiptColor,
        duoLight: ReceiptColor
    ) {
        self.paper = paper
        self.ink = ink
        self.accent = accent
        self.accentInk = .contrastInk(on: accent)
        self.duoDark = duoDark
        self.duoLight = duoLight
    }

    /// 封面配色渲染整卡（界面上是「卡片配色取自封面」开关，默认关）。
    ///
    /// 用封面提取出的主色 / 辅色**重算纸底、墨色、强调与双色调**：
    /// - 纸底取主色色相，明度按封面整体亮度二选一（亮纸 `0.96` / 暗纸 `0.10`），避免落在中间灰；
    /// - 墨色与强调色都会被推到与纸底达标为止（墨 ≥ 7:1、强调 ≥ 4.5:1），保证文字始终可读。
    ///
    /// 缺封面（或提取失败）时退回该风格的固有调色板。
    static func posterDriven(base: ReceiptPalette, colors: ReceiptPosterColors?) -> ReceiptPalette {
        guard let colors else { return base }

        let dominant = colors.dominant.hsb
        let secondary = colors.secondary.hsb
        // 封面整体偏亮 → 亮纸（深墨字），否则暗纸（浅墨字）。
        let isLightPaper = colors.dominant.relativeLuminance >= 0.32

        let paper = ReceiptColor(
            hue: dominant.hue,
            saturation: min(dominant.saturation * 0.30, 0.22),
            brightness: isLightPaper ? 0.96 : 0.10
        )
        let ink = ReceiptColor.ensureContrast(
            ReceiptColor(
                hue: dominant.hue,
                saturation: min(dominant.saturation * 0.45, 0.35),
                brightness: isLightPaper ? 0.10 : 0.95
            ),
            on: paper,
            minRatio: 7.0
        )
        let accent = ReceiptColor.ensureContrast(
            ReceiptColor(
                hue: secondary.hue,
                // 饱和度跟着封面辅色走：近灰 / 黑白封面不会被凭空添色（中性色的色相是 0，加饱和会变红）。
                saturation: min(secondary.saturation * 1.25, 0.95),
                brightness: isLightPaper
                    ? min(max(secondary.brightness * 0.78, 0.30), 0.72)
                    : min(max(secondary.brightness, 0.62), 0.95)
            ),
            on: paper,
            minRatio: 4.5
        )

        return ReceiptPalette(
            paper: paper,
            ink: ink,
            accent: accent,
            duoDark: ReceiptColor(
                hue: dominant.hue,
                saturation: min(dominant.saturation * 0.85, 0.80),
                brightness: isLightPaper ? 0.26 : 0.12
            ),
            duoLight: ReceiptColor(
                hue: secondary.hue,
                saturation: min(secondary.saturation * 1.10, 0.75),
                brightness: isLightPaper ? 0.94 : 0.82
            )
        )
    }
}

/// 纯 Swift 的 sRGB 颜色（Core / 视图两侧都能用；不引 AppKit）。
struct ReceiptColor: Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// WCAG 相对亮度（sRGB 线性化后加权）。
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 与白色的对比度。
    var contrastWithWhite: Double { 1.05 / (relativeLuminance + 0.05) }
    /// 与深墨（`#0C1406`）的对比度。
    var contrastWithDarkInk: Double { (relativeLuminance + 0.05) / (ReceiptColor.darkInk.relativeLuminance + 0.05) }

    /// 两色之间的 WCAG 对比度。
    func contrast(with other: ReceiptColor) -> Double {
        let mine = relativeLuminance
        let theirs = other.relativeLuminance
        return (max(mine, theirs) + 0.05) / (min(mine, theirs) + 0.05)
    }

    /// 把颜色沿明度方向推到达标为止：与 `background` 的对比度 ≥ `minRatio`。
    ///
    /// 亮底往暗推、暗底往亮推，直到达标或明度用尽（用于封面配色下的可读性保护）。
    static func ensureContrast(
        _ color: ReceiptColor,
        on background: ReceiptColor,
        minRatio: Double,
        step: Double = 0.03
    ) -> ReceiptColor {
        guard color.contrast(with: background) < minRatio else { return color }

        let darker = background.relativeLuminance > 0.5
        var result = color
        for _ in 0..<34 {
            let hsb = result.hsb
            let brightness = darker ? max(hsb.brightness - step, 0) : min(hsb.brightness + step, 1)
            result = ReceiptColor(hue: hsb.hue, saturation: hsb.saturation, brightness: brightness)
            if result.contrast(with: background) >= minRatio || brightness == 0 || brightness == 1 { break }
        }
        return result
    }

    /// 该底色上文字的最大可用对比度（对比度优先取深墨或白）。
    var bestContrastRatio: Double { max(contrastWithWhite, contrastWithDarkInk) }

    static let darkInk = ReceiptColor(hex: 0x0C1406)

    /// 该底色上的文字色：取对比度更高的一侧（深墨或白）。
    static func contrastInk(on background: ReceiptColor) -> ReceiptColor {
        background.contrastWithDarkInk >= background.contrastWithWhite ? .darkInk : ReceiptColor(hex: 0xFFFFFF)
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let s = min(max(saturation, 0), 1)
        let v = min(max(brightness, 0), 1)
        let sector = Int(h)
        let f = h - Double(sector)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        switch sector % 6 {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    func mixed(with other: ReceiptColor, ratio: Double) -> ReceiptColor {
        let r = min(max(ratio, 0), 1)
        return ReceiptColor(
            red: red * (1 - r) + other.red * r,
            green: green * (1 - r) + other.green * r,
            blue: blue * (1 - r) + other.blue * r
        )
    }
}

/// 封面提取出的两种颜色：主色（整体基调）+ 辅色（最抢眼的第二色）。
struct ReceiptPosterColors: Sendable, Equatable {
    var dominant: ReceiptColor
    var secondary: ReceiptColor
}

/// 海报取色与处理（CoreImage）。
enum ReceiptPosterProcessor {
    nonisolated(unsafe) private static let context = CIContext()

    /// 海报平均主色（`CIAreaAverage`）。缺图 / 失败返回 nil，调用方退回固有调色板。
    static func averageColor(of image: CGImage?) -> ReceiptColor? {
        guard let image else { return nil }
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        pixel.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return ReceiptColor(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }

    /// 从封面提取主色 + 辅色（缺封面 / 提取失败返回 nil，调用方退回固有调色板）。
    ///
    /// 把封面降采样成 16×24 样本，按「色相 × 明度」分簇：
    /// 主色 = 像素最多的色簇均值（封面整体基调）；辅色 = 与主色色相拉开、够鲜艳的色簇里
    /// 平均鲜艳度最高者（占比过小的色簇忽略，避免噪点胜出）。单色封面退回整体均值 + 明度偏移。
    static func colors(of image: CGImage?) -> ReceiptPosterColors? {
        guard let image else { return nil }

        let samples = samples(of: image)
        guard !samples.isEmpty else {
            // 降采样失败：退回整体均值 + 明度偏移。
            guard let average = averageColor(of: image) else { return nil }
            return ReceiptPosterColors(dominant: average, secondary: shifted(average))
        }

        var buckets: [Int: Bucket] = [:]
        for sample in samples {
            let hsb = sample.hsb
            let hue = Int(hsb.hue * 12) % 12
            let lightness = min(Int(hsb.brightness * 3), 2)
            var bucket = buckets[hue * 3 + lightness] ?? Bucket()
            bucket.red += sample.red
            bucket.green += sample.green
            bucket.blue += sample.blue
            bucket.count += 1
            buckets[hue * 3 + lightness] = bucket
        }

        guard let heaviest = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let dominant = heaviest.mean
        let dominantHue = dominant.hsb.hue
        // 占比不足 4%（且少于 2 个样本）的色簇忽略。
        let threshold = max(Double(samples.count) * 0.04, 2)

        var secondary: (color: ReceiptColor, salience: Double)?
        for bucket in buckets.values where Double(bucket.count) >= threshold {
            let color = bucket.mean
            let hsb = color.hsb
            let distance = min(abs(hsb.hue - dominantHue), 1 - abs(hsb.hue - dominantHue))
            guard hsb.saturation >= 0.20, distance >= 0.06 else { continue }
            let salience = hsb.saturation * (0.30 + 0.70 * hsb.brightness)
            if secondary == nil || salience > secondary!.salience {
                secondary = (color, salience)
            }
        }

        return ReceiptPosterColors(dominant: dominant, secondary: secondary?.color ?? shifted(dominant))
    }

    /// 降采样样本（16×24）：一次缩放绘制拿到整幅的粗略色彩分布。
    private static func samples(of image: CGImage) -> [ReceiptColor] {
        let columns = 16
        let rows = 24
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress, let cgContext = CGContext(
                data: base,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            cgContext.interpolationQuality = .medium
            cgContext.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return [] }

        return (0..<(columns * rows)).map { index in
            let offset = index * 4
            return ReceiptColor(
                red: Double(pixels[offset]) / 255,
                green: Double(pixels[offset + 1]) / 255,
                blue: Double(pixels[offset + 2]) / 255
            )
        }
    }

    /// 单色封面的辅色：主色的明度偏移版本（保证强调色与纸底拉开）。
    private static func shifted(_ color: ReceiptColor) -> ReceiptColor {
        let hsb = color.hsb
        return ReceiptColor(
            hue: hsb.hue + 0.08,
            // 近灰封面不加饱和（中性色色相为 0，加饱和会凭空变红）。
            saturation: hsb.saturation < 0.12 ? hsb.saturation : min(hsb.saturation + 0.18, 0.85),
            brightness: hsb.brightness > 0.5
                ? max(hsb.brightness - 0.35, 0.20)
                : min(hsb.brightness + 0.45, 0.95)
        )
    }

    /// 色簇累加器（分簇求均值）。
    private struct Bucket {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0

        var mean: ReceiptColor {
            ReceiptColor(
                red: red / Double(count),
                green: green / Double(count),
                blue: blue / Double(count)
            )
        }
    }

    /// 按模式处理海报：原色 / 灰度 / 双色调（渐变映射）/ 反相双色调。
    static func processed(_ image: CGImage, mode: ReceiptPosterMode, palette: ReceiptPalette) -> CGImage? {
        let input = CIImage(cgImage: image)

        switch mode {
        case .original:
            // 保留封面原色：不做任何色彩处理。
            return render(input)
        case .grayscale:
            return render(input.applyingFilter("CIPhotoEffectMono"))
        case .duotone:
            guard let mapped = duotone(input.applyingFilter("CIPhotoEffectMono"), palette: palette) else { return nil }
            return render(mapped)
        case .invertedDuotone:
            guard let mapped = duotone(input.applyingFilter("CIPhotoEffectMono"), palette: palette) else { return nil }
            return render(mapped.applyingFilter("CIColorInvert"))
        }
    }

    /// 真·双色调：把灰度图当作索引，映射到 `duoDark → duoLight` 的渐变上。
    ///
    /// `CIColorMap` 沿映射图 **x 轴**按源像素亮度取样，因此映射图必须是**横向**渐变
    /// （曾误用 1px 宽的纵向渐变，导致整张海报塌成单一颜色——见 `ReceiptTests` 的双色调回归用例）。
    private static func duotone(_ grayscale: CIImage, palette: ReceiptPalette) -> CIImage? {
        let gradientWidth: CGFloat = 256
        guard let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: gradientWidth, y: 0),
            "inputColor0": CIColor(red: palette.duoDark.red, green: palette.duoDark.green, blue: palette.duoDark.blue),
            "inputColor1": CIColor(red: palette.duoLight.red, green: palette.duoLight.green, blue: palette.duoLight.blue),
        ])?.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: gradientWidth, height: 1)) else { return nil }

        return CIFilter(name: "CIColorMap", parameters: [
            kCIInputImageKey: grayscale,
            "inputGradientImage": gradient,
        ])?.outputImage?.cropped(to: grayscale.extent)
    }

    private static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}
