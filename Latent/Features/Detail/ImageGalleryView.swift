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

/// 图片画廊（v1.22）：大图 + 缩略图条，左右方向键翻页，可按剧照 / 海报切换。
struct ImageGallerySheet: View {
    let request: GalleryRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind: GalleryKind
    @State private var index: Int

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
        ZStack {
            UI.Palette.surface.opacity(0.4)

            if let current {
                PosterImage(path: current.filePath, displayWidth: 640, cornerRadius: 4, contentMode: .fit)
                    .id(current.id)
                    .padding(UI.Spacing.s4)
                    .transition(.opacity)
            }

            navButton(systemImage: "chevron.left", isEnabled: index > 0) { go(-1) }
                .padding(.leading, UI.Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)

            navButton(systemImage: "chevron.right", isEnabled: index < assets.count - 1) { go(1) }
                .padding(.trailing, UI.Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .focusable()
        .onKeyPress(.leftArrow) { go(-1); return .handled }
        .onKeyPress(.rightArrow) { go(1); return .handled }
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
