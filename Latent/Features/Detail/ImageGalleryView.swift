import SwiftUI

/// 画廊图片来源：剧照（横图）或海报（竖图）。
enum GalleryKind: String, CaseIterable, Identifiable {
    case stills
    case posters

    var id: String { rawValue }
    var label: String { self == .stills ? "剧照" : "海报" }
}

/// 打开画廊的请求（`sheet(item:)` 用；索引在打开瞬间固定）。
struct GalleryRequest: Identifiable {
    let id = UUID()
    let title: String
    let stills: [ImageAsset]
    let posters: [ImageAsset]
    let initialKind: GalleryKind
    let initialIndex: Int
}

/// 缩放参数（纯函数，便于单测；v1.24）。
enum GalleryZoom {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 4
    static let step: CGFloat = 0.5
    /// 双击放大的档位。
    static let doubleTapScale: CGFloat = 2

    static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    /// 缩放后允许的平移上限：舞台尺寸 ×（缩放 − 1）/ 2，保证图片不会被拖出视野。
    static func clampedOffset(_ proposed: CGSize, scale: CGFloat, stage: CGSize) -> CGSize {
        guard scale > minScale else { return .zero }
        let maxX = max(0, stage.width * (scale - 1) / 2)
        let maxY = max(0, stage.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

/// 图片画廊（v1.22）：大图 + 缩略图条，左右方向键翻页，可按剧照 / 海报切换。
/// v1.24 支持缩放：捏合、双击、右上角 +/− 或缩放百分比旁按钮；放大后可拖动查看细节。
struct ImageGallerySheet: View {
    let request: GalleryRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind: GalleryKind
    @State private var index: Int
    @State private var scale: CGFloat = GalleryZoom.minScale
    @State private var baseScale: CGFloat = GalleryZoom.minScale
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    init(request: GalleryRequest) {
        self.request = request
        _kind = State(initialValue: request.initialKind)
        _index = State(initialValue: request.initialIndex)
    }

    private var assets: [ImageAsset] {
        kind == .stills ? request.stills : request.posters
    }

    private var current: ImageAsset? {
        assets.indices.contains(index) ? assets[index] : assets.first
    }

    private var hasBothKinds: Bool {
        !request.stills.isEmpty && !request.posters.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(UI.Palette.border)
            stage
            caption
            Divider().overlay(UI.Palette.border)
            thumbnails
        }
        .frame(width: 980, height: 720)
        .background(UI.Palette.bg)
        .onChange(of: index) { _, _ in resetZoom(animated: false) }
        .onChange(of: kind) { _, _ in resetZoom(animated: false) }
    }

    private var header: some View {
        HStack(spacing: UI.Spacing.s3) {
            Text(request.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
                .lineLimit(1)

            if hasBothKinds {
                Picker("", selection: $kind) {
                    ForEach(GalleryKind.allCases) { option in
                        let count = option == .stills ? request.stills.count : request.posters.count
                        Text("\(option.label) \(count)").tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: kind) { _, _ in
                    index = 0
                }
            } else {
                Text("\(kind.label) · \(assets.count) 张")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            Spacer()

            NumericText(text: "\(min(index + 1, assets.count)) / \(assets.count)", size: 11)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(UI.Palette.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭（Esc）")
        }
        .padding(.horizontal, UI.Spacing.s4)
        .padding(.vertical, UI.Spacing.s3)
    }

    private var stage: some View {
        GeometryReader { proxy in
            ZStack {
                UI.Palette.surface.opacity(0.4)

                if let current {
                    PosterImage(path: current.filePath, displayWidth: 640, cornerRadius: 4, contentMode: .fit)
                        .id(current.id)
                        .padding(UI.Spacing.s4)
                        .scaleEffect(scale)
                        .offset(offset)
                        .contentShape(Rectangle())
                        .gesture(magnifyGesture)
                        .simultaneousGesture(panGesture(in: proxy.size))
                        .onTapGesture(count: 2) { toggleZoom() }
                        .help(scale > GalleryZoom.minScale ? "拖动查看细节 · 双击还原" : "双击放大")
                        .transition(.opacity)
                }

                navButton(systemImage: "chevron.left", isEnabled: index > 0) { go(-1) }
                    .padding(.leading, UI.Spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                navButton(systemImage: "chevron.right", isEnabled: index < assets.count - 1) { go(1) }
                    .padding(.trailing, UI.Spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                zoomControls
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .focusable()
            .onKeyPress(.leftArrow) { go(-1); return .handled }
            .onKeyPress(.rightArrow) { go(1); return .handled }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 缩放（v1.24）

    private var zoomControls: some View {
        HStack(spacing: 2) {
            zoomButton(systemImage: "minus", isEnabled: scale > GalleryZoom.minScale + 0.001) {
                setScale(scale - GalleryZoom.step)
            }

            Text(String(format: "%.1f×", scale))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 34)

            zoomButton(systemImage: "plus", isEnabled: scale < GalleryZoom.maxScale - 0.001) {
                setScale(scale + GalleryZoom.step)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(UI.Palette.surface, in: Capsule())
        .hairlineBorder(UI.Palette.border, radius: 14)
        .opacity(scale > GalleryZoom.minScale + 0.001 ? 1 : 0.75)
        .padding(UI.Spacing.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func zoomButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isEnabled ? UI.Palette.textPrimary : UI.Palette.textSecondary.opacity(0.35))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(systemImage == "plus" ? "放大" : "缩小")
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = GalleryZoom.clampedScale(baseScale * value.magnification)
            }
            .onEnded { _ in
                baseScale = scale
                if scale <= GalleryZoom.minScale + 0.001 {
                    resetZoom(animated: true)
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > GalleryZoom.minScale + 0.001 else { return }
                let proposed = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                offset = GalleryZoom.clampedOffset(proposed, scale: scale, stage: size)
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }

    private func toggleZoom() {
        if scale > GalleryZoom.minScale + 0.001 {
            resetZoom(animated: true)
        } else {
            setScale(GalleryZoom.doubleTapScale)
        }
    }

    private func setScale(_ value: CGFloat) {
        let target = GalleryZoom.clampedScale(value)
        baseScale = target
        guard !reduceMotion else {
            scale = target
            if target <= GalleryZoom.minScale { offset = .zero; baseOffset = .zero }
            return
        }
        withAnimation(UI.Motion.hover) {
            scale = target
            if target <= GalleryZoom.minScale {
                offset = .zero
            }
        }
        if target <= GalleryZoom.minScale {
            baseOffset = .zero
        }
    }

    private func resetZoom(animated: Bool) {
        baseScale = GalleryZoom.minScale
        baseOffset = .zero
        guard animated && !reduceMotion else {
            scale = GalleryZoom.minScale
            offset = .zero
            return
        }
        withAnimation(UI.Motion.hover) {
            scale = GalleryZoom.minScale
            offset = .zero
        }
    }

    private func navButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? UI.Palette.textPrimary : UI.Palette.textSecondary.opacity(0.35))
                .frame(width: 30, height: 30)
                .background(UI.Palette.surface, in: Circle())
                .hairlineBorder(UI.Palette.border, radius: 15)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? (systemImage.contains("left") ? "上一张（←）" : "下一张（→）") : "")
    }

    @ViewBuilder
    private var caption: some View {
        if let caption = current?.galleryCaption {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
                .padding(.bottom, UI.Spacing.s3)
        }
    }

    private var thumbnails: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: UI.Spacing.s2) {
                    ForEach(Array(assets.enumerated()), id: \.element.id) { offset, asset in
                        thumbnail(asset, isSelected: offset == index)
                            .id(asset.id)
                            .onTapGesture {
                                withAnimation(reduceMotion ? nil : UI.Motion.hover) { index = offset }
                            }
                    }
                }
                .padding(.horizontal, UI.Spacing.s4)
                .padding(.vertical, UI.Spacing.s3)
            }
            .onChange(of: index) { _, newValue in
                guard assets.indices.contains(newValue) else { return }
                withAnimation(reduceMotion ? nil : UI.Motion.hover) {
                    proxy.scrollTo(assets[newValue].id, anchor: .center)
                }
            }
        }
        .frame(height: kind == .stills ? 88 : 110)
    }

    private func thumbnail(_ asset: ImageAsset, isSelected: Bool) -> some View {
        let size = kind == .stills ? CGSize(width: 118, height: 66) : CGSize(width: 60, height: 90)
        return PosterImage(path: asset.filePath, displayWidth: size.width, cornerRadius: 4)
            .frame(width: size.width, height: size.height)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? UI.Palette.accent : UI.Palette.border, lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isSelected ? 1 : 0.62)
            .contentShape(Rectangle())
            .help(asset.galleryCaption ?? "查看这张")
    }

    /// 翻页：首尾循环不越界；Reduce Motion 时不加过渡动画。
    private func go(_ delta: Int) {
        let next = index + delta
        guard assets.indices.contains(next) else { return }
        if reduceMotion {
            index = next
        } else {
            withAnimation(UI.Motion.imageFade) { index = next }
        }
    }
}
