import SwiftUI
import ImageIO

/// 海报 / 图片视图：骨架占位 → 150ms 淡入；失败静默保留占位（设计文档第 7 节）。
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

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .opacity(isLoaded ? 1 : 0)
            } else if path == nil {
                placeholder
            } else {
                Skeleton.block(cornerRadius: cornerRadius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: taskID) {
            await load()
        }
    }

    private var taskID: String {
        "\(path ?? "nil")|\(Int(displayWidth))"
    }

    private func load() async {
        image = nil
        isLoaded = false
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
            // 管线已自动重试一次；仍失败保持占位（静默）
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
    @State private var dimmed = false

    static func block(cornerRadius: CGFloat = UI.Radius.poster) -> some View {
        Skeleton()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 0, style: .continuous)
            .fill(UI.Palette.surfaceElevated)
            .opacity(dimmed ? 0.5 : 0.8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(UI.Motion.breathe.repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }

    /// 文本条（标题 / 元信息两行）。
    static func textLines(width: CGFloat, lines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<lines, id: \.self) { index in
                Skeleton()
                    .frame(width: index == 0 ? width : width * 0.6, height: 9)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .opacity(0.6)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
