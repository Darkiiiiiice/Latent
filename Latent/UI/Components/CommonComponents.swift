import SwiftUI
import AppKit
import QuartzCore

/// 评分细环（设计文档第 8.4 节）：1.5px 细环 + 等宽数字；≥8.0 success，其余 accent。
struct RatingRing: View {
    let rating: Double?
    var size: CGFloat = 44

    private var value: Double? {
        guard let rating, rating > 0 else { return nil }
        return min(rating, 10)
    }

    private var ringColor: Color {
        (rating ?? 0) >= 8.0 ? UI.Palette.success : UI.Palette.accent
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(UI.Palette.border, lineWidth: 1.5)

            if let value {
                Circle()
                    .trim(from: 0, to: value / 10)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if let text = Formatters.rating(rating) {
                Text(text)
                    .font(.system(size: size * 0.30, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textPrimary)
            } else {
                Text("—")
                    .font(.system(size: size * 0.30, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Formatters.rating(rating).map { "评分 \($0) 分，满分 10 分" } ?? "暂无评分")
    }
}

/// 类型标签（10px Caption、1px border、无填充）。
struct GenreChips: View {
    let genres: [Genre]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(genres.prefix(4)) { genre in
                Text(genre.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: UI.Radius.chip, style: .continuous)
                            .strokeBorder(UI.Palette.border, lineWidth: 1)
                    }
            }
        }
    }
}

/// 事实栏一行：左 11px 大写 Secondary 标签，右 13px Primary 值；可选复制按钮。
struct FactRow: View {
    let label: String
    let value: String
    var copyText: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(UI.Palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let copyText {
                CopyButton(text: copyText)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 复制按钮（事实栏 TMDB ID 行、右键菜单共用同一反馈文案）。
struct CopyButton: View {
    let text: String
    var help: String = "复制"

    var body: some View {
        Button {
            Pasteboard.copy(text)
            ToastCenter.shared.show("已复制")
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 空状态：一句话 + 一个动作（设计文档第 8.4 节）。
struct EmptyState: View {
    let message: String
    var systemImage: String = "magnifyingglass"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: UI.Spacing.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(UI.Palette.textSecondary.opacity(0.7))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(UI.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(UI.Spacing.s8)
    }
}

/// 内联错误横幅 + 重试（断网 / 超时 / 服务端异常）。
struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: UI.Spacing.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.warning)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textPrimary)
            Spacer(minLength: 0)
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s2)
        .background(UI.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }
}

/// Toast（底部居中、3 秒自动消失、非阻塞）。
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    private(set) var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String) {
        message = text
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

/// Toast 承载视图（挂在窗口根视图上）。
struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var center

    var body: some View {
        VStack {
            Spacer()
            if let message = center.message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .padding(.horizontal, UI.Spacing.s3)
                    .padding(.vertical, UI.Spacing.s2)
                    .background(UI.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
                    .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
                    .padding(.bottom, UI.Spacing.s6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(UI.Motion.imageFade, value: center.message)
        .allowsHitTesting(false)
    }
}

/// 剪贴板（复制 TMDB ID / 链接用）。
enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// CA 驱动的呼吸色块（骨架屏 / 连接状态点共用）。
///
/// 不使用 SwiftUI 的 `repeatForever`：在 macOS 27 上无限动画会一直留在显示周期里，
/// 造成整窗每帧重排（实测：工具栏齿轮图标无限"飞行"、CPU 空转 40%+，且视图移除后仍不停）。
/// Core Animation 由渲染服务端驱动，空闲时不占主线程。
struct BreathingFill: NSViewRepresentable {
    var color: Color
    var cornerRadius: CGFloat = 0
    var lowOpacity: Double
    var highOpacity: Double
    /// 单程时长（autoreverses 后为往返周期的一半）。
    var duration: Double
    var animated: Bool
    /// 仅作为依赖项：外观切换时强制刷新动态颜色。
    var colorScheme: ColorScheme

    private let animationKey = "latent.breathe"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let layer = view.layer else { return }
        var resolved: NSColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color)
        }
        layer.backgroundColor = resolved?.cgColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        if animated {
            layer.opacity = Float(highOpacity)
            if layer.animation(forKey: animationKey) == nil {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = highOpacity
                animation.toValue = lowOpacity
                animation.duration = duration
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: animationKey)
            }
        } else {
            layer.removeAnimation(forKey: animationKey)
            layer.opacity = Float(highOpacity)
        }
    }
}
