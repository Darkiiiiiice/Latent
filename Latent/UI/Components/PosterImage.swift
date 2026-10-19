import SwiftUI
import ImageIO

/// 海报 / 图片视图：骨架占位 → 150ms 淡入；失败静默保留占位（设计文档第 7 节）。
///
/// 尺寸契约：**本视图不产生自己的尺寸**，完全由外部 `.frame(...)` 决定；
/// 图片以 overlay 铺满该尺寸，`contentMode = .fill` 时按容器裁切（不是溢出）。
/// 因此方形头像里的 2:3 竖图也只会被裁掉两侧，不会盖到相邻内容上。
///
/// 视图消失时取消加载（管线侧不产生缓存写入）。
struct PosterImage: View {
    let path: String?
    let displayWidth: CGFloat
    var cornerRadius: CGFloat = UI.Radius.poster
    var contentMode: ContentMode = .fill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    @State private var isLoaded = false
    @State private var didFail = false

    var body: some View {
        // Color.clear 只负责「取外部 frame 的尺寸」；图片与占位都画在 overlay 里。
        Color.clear
            .overlay { drawing }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: taskID) {
                await load()
            }
    }

    @ViewBuilder
    private var drawing: some View {
        if let image {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .opacity(isLoaded ? 1 : 0)
        } else if path == nil || didFail {
            placeholder
        } else {
            Skeleton.block(cornerRadius: cornerRadius)
        }
    }

    private var taskID: String {
        "\(path ?? "nil")|\(Int(displayWidth))"
    }

    private func load() async {
        image = nil
        isLoaded = false
        didFail = false
        guard let path, !path.isEmpty else { return }

        do {
            let loaded = try await ImagePipeline.shared.image(for: path, displayWidth: displayWidth)
            guard !Task.isCancelled else { return }
            image = loaded
            if reduceMotion {
                isLoaded = true
            } else {
                withAnimation(UI.Motion.imageFade) { isLoaded = true }
            }
        } catch {
            guard !Task.isCancelled else { return }
            // 管线已自动重试一次；仍失败则切静态占位（设计文档：失败静默保留占位）。
            didFail = true
        }
    }

    /// 失败 / 无图占位：胶片图标纹理（中性色，不用彩色插画）。
    private var placeholder: some View {
        ZStack {
            UI.Palette.surfaceElevated
            Image(systemName: "film")
                .font(.system(size: max(16, displayWidth * 0.16), weight: .light))
                .foregroundStyle(UI.Palette.textSecondary.opacity(0.55))
        }
    }
}

/// 骨架屏（1.2s 呼吸；Reduce Motion 时静止）。
struct Skeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 0

    static func block(cornerRadius: CGFloat = UI.Radius.poster) -> some View {
        Skeleton(cornerRadius: cornerRadius)
    }

    var body: some View {
        BreathingFill(
            color: UI.Palette.surfaceElevated,
            cornerRadius: cornerRadius,
            lowOpacity: 0.5,
            highOpacity: 0.8,
            duration: UI.Motion.Breath.skeleton,
            animated: !reduceMotion,
            colorScheme: colorScheme
        )
    }

    /// 文本条（标题 / 元信息两行）。
    static func textLines(width: CGFloat, lines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<lines, id: \.self) { index in
                Skeleton(cornerRadius: 2)
                    .frame(width: index == 0 ? width : width * 0.6, height: 9)
                    .opacity(0.6)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
