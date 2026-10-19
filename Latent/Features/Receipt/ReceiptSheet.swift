import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 分享卡预览与导出（电影详情页工具栏唤起；设计文档第 8.10 节）。
///
/// 预览与导出是同一张 `ReceiptCardView`：预览按 0.6 缩放，导出走 `ImageRenderer` 出 1080×1440 PNG。
struct ReceiptSheet: View {
    let movie: MovieDetail

    @Environment(\.dismiss) private var dismiss
    @State private var style: ReceiptStyle = .thermal
    /// 海报保留封面原色（默认关：走该风格的固有双色调 / 灰度处理）。
    @State private var keepsPosterColors = false
    /// 卡片配色取自封面（默认关：保持七款锁定配色）。开启后用封面主色 / 辅色重算整卡配色。
    @State private var followsPoster = false
    @State private var poster: CGImage?
    @State private var posterColors: ReceiptPosterColors?
    @State private var exportDocument: ReceiptImageDocument?
    @State private var isExporting = false

    private var data: ReceiptData { ReceiptData.build(from: movie) }
    private var palette: ReceiptPalette {
        followsPoster
            ? ReceiptPalette.posterDriven(base: style.basePalette, colors: posterColors)
            : style.basePalette
    }
    private var posterMode: ReceiptPosterMode {
        keepsPosterColors ? .original : style.posterMode
    }

    private let previewScale: CGFloat = 0.6

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: UI.Spacing.s6) {
                preview
                styleList
            }
            .padding(UI.Spacing.s6)
            Divider()
            actions
        }
        .frame(width: 760)
        .background(UI.Palette.bg)
        .task { await loadPoster() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .png,
            defaultFilename: ReceiptRenderer.filename(title: data.title)
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                ToastCenter.shared.show("已保存分享卡")
            case .failure(let error):
                ToastCenter.shared.show("保存失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: UI.Spacing.s3) {
            Text("分享卡")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text(movie.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(UI.Palette.textSecondary)
            Spacer(minLength: 0)
            Text("3:4 · 1080×1440")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
        .padding(.horizontal, UI.Spacing.s6)
        .padding(.vertical, UI.Spacing.s4)
    }

    // MARK: - 预览

    private var preview: some View {
        ReceiptCardView(
            data: data, style: style, palette: palette, posterMode: posterMode, poster: poster
        )
            .scaleEffect(previewScale, anchor: .topLeading)
            .frame(
                width: ReceiptCanvas.size.width * previewScale,
                height: ReceiptCanvas.size.height * previewScale,
                alignment: .topLeading
            )
            .background(UI.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .hairlineBorder(radius: UI.Radius.button)
    }

    // MARK: - 风格

    private var styleList: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            Text("风格")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(UI.Palette.textSecondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: UI.Spacing.s3),
                    GridItem(.flexible(), spacing: UI.Spacing.s3),
                ],
                spacing: UI.Spacing.s3
            ) {
                ForEach(ReceiptStyle.allCases) { item in
                    styleButton(item)
                }
            }

            Text("封面")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(UI.Palette.textSecondary)

            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                Toggle("保留封面原色", isOn: $keepsPosterColors)
                    .help("海报不做双色调 / 灰度处理，直接印封面原色")
                Toggle("卡片配色取自封面", isOn: $followsPoster)
                    .help("用封面主色 + 辅色重算纸底、墨色与强调色（自动保证文字可读）")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .foregroundStyle(UI.Palette.textPrimary)
            .disabled(poster == nil)

            Text("缺字段的行不显示。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)

            Spacer(minLength: 0)
        }
        .frame(width: 340, alignment: .leading)
    }

    private func styleButton(_ item: ReceiptStyle) -> some View {
        let base = followsPoster
            ? ReceiptPalette.posterDriven(base: item.basePalette, colors: posterColors)
            : item.basePalette
        return Button {
            style = item
        } label: {
            HStack(spacing: UI.Spacing.s2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(base.paper.color)
                    .frame(width: 22, height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(base.accent.color).frame(height: 6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(UI.Palette.border, lineWidth: 1)
                    }
                Text(item.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, UI.Spacing.s2)
            .padding(.vertical, UI.Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style == item ? UI.Palette.surfaceElevated : UI.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                    .strokeBorder(style == item ? UI.Palette.accent : UI.Palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private var actions: some View {
        HStack(spacing: UI.Spacing.s3) {
            Button("复制到剪贴板") { copyToPasteboard() }
                .buttonStyle(.borderedProminent)
            Button("保存 PNG…") { save() }
            Spacer(minLength: 0)
            Button("完成") { dismiss() }
        }
        .padding(.horizontal, UI.Spacing.s6)
        .padding(.vertical, UI.Spacing.s4)
    }

    private func copyToPasteboard() {
        guard let image = ReceiptRenderer.cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode, poster: poster
        ) else {
            ToastCenter.shared.show("分享卡生成失败")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: ReceiptCanvas.size)])
        ToastCenter.shared.show("已复制分享卡")
    }

    private func save() {
        guard let png = ReceiptRenderer.pngData(
            data: data, style: style, palette: palette, posterMode: posterMode, poster: poster
        ) else {
            ToastCenter.shared.show("分享卡生成失败")
            return
        }
        exportDocument = ReceiptImageDocument(data: png)
        isExporting = true
    }

    private func loadPoster() async {
        guard let path = data.posterPath, !path.isEmpty else { return }
        poster = try? await ImagePipeline.shared.image(for: path, displayWidth: ReceiptCanvas.size.width)
        posterColors = ReceiptPosterProcessor.colors(of: poster)
    }
}

/// PNG 文档包装（`FileExporter` 保存分享卡用）。
struct ReceiptImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
