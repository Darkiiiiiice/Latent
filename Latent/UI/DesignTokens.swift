import SwiftUI

/// 设计 tokens（设计文档第 8.2 节）。
///
/// 颜色全部来自 Asset Catalog 的 Any / Dark 两套——视图里不写死 hex。
enum UI {
    // MARK: - 颜色

    enum Palette {
        static var bg: Color { Color("Bg") }
        static var surface: Color { Color("Surface") }
        static var surfaceElevated: Color { Color("SurfaceElevated") }
        static var border: Color { Color("Border") }
        static var textPrimary: Color { Color("TextPrimary") }
        static var textSecondary: Color { Color("TextSecondary") }
        static var accent: Color { Color("AccentColor") }
        static var accentText: Color { Color("AccentText") }
        static var success: Color { Color("Success") }
        static var warning: Color { Color("Warning") }
        static var error: Color { Color("Error") }
    }

    // MARK: - 间距（4pt 网格）

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let contentMargin: CGFloat = 28
        static let gridSpacing: CGFloat = 20
    }

    // MARK: - 尺寸

    enum Sizes {
        static let windowDefault = CGSize(width: 1240, height: 800)
        static let windowMinimum = CGSize(width: 1040, height: 660)
        static let sidebarWidth: CGFloat = 220
        static let searchFieldWidth: CGFloat = 380
        static let posterCard = CGSize(width: 168, height: 252)
        static let posterAspect: CGFloat = 2.0 / 3.0
        static let factColumnWidth: CGFloat = 280
        static let detailHeroHeight: CGFloat = 400
        static let castAvatar: CGFloat = 64
        static let historyThumb = CGSize(width: 40, height: 60)
    }

    // MARK: - 圆角

    enum Radius {
        static let poster: CGFloat = 8
        static let button: CGFloat = 8
        static let input: CGFloat = 8
        static let chip: CGFloat = 5
    }

    // MARK: - 动效（120–220ms easeOut；无弹簧）

    enum Motion {
        static let hover: Animation = .easeOut(duration: 0.12)
        static let cardLift: Animation = .easeOut(duration: 0.14)
        static let imageFade: Animation = .easeOut(duration: 0.15)
        static let statusPulse: Animation = .easeInOut(duration: 0.8)
        /// 状态点呼吸 / 骨架呼吸
        static let breathe: Animation = .easeInOut(duration: 1.2)
    }

    // MARK: - 阴影（仅 hover 卡片与 Toast）

    enum Shadows {
        static let card = Shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
        static let toast = Shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
}

extension View {
    /// 统一的卡片 hover 阴影。
    func cardHoverShadow(_ enabled: Bool) -> some View {
        shadow(
            color: enabled ? .black.opacity(0.35) : .clear,
            radius: enabled ? 10 : 0,
            x: 0,
            y: enabled ? 8 : 0
        )
    }

    /// 1px 描边（设计系统统一 border）。
    func hairlineBorder(_ color: Color = UI.Palette.border, radius: CGFloat = UI.Radius.poster) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        }
    }
}

/// 等宽数字（评分、年份、时长、预算、TMDB ID 不跳动）。
struct NumericText: View {
    let text: String
    var size: CGFloat = 13
    var weight: Font.Weight = .medium
    var color: Color = UI.Palette.textSecondary

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}
