import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 分享卡预览与导出（电影 / 剧集 / 人物详情页工具栏唤起；设计文档第 8.10 节）。
///
/// 预览与导出是同一张 `ReceiptCardView`：预览按 0.6 缩放，导出走 `ImageRenderer` 出 1080×1440 PNG。
struct ReceiptSheet: View {
    let data: ReceiptData

    @Environment(\.dismiss) private var dismiss
    @State private var style: ReceiptStyle = .thermal
    /// 版式（v1.28）：经典 / 侧栏 / 全幅 / 索引。
    @State private var layout: ReceiptLayout = .classic
    /// 画布比例（v1.33）：3:4 / 1:1 / 9:16。
    @State private var aspect: ReceiptAspect = .portrait
    /// 海报保留封面原色（默认关：走该风格的固有双色调 / 灰度处理）。
    @State private var keepsPosterColors = false
    /// 卡片配色取自封面（默认关：保持十八款锁定配色）。开启后用封面主色 / 辅色重算整卡配色。
    @State private var followsPoster = false
    /// 细节调节（v1.30）：字号 / 边距 / 页脚标语 / 水印。
    @State private var tuning = ReceiptTuning.standard
    @State private var poster: CGImage?
    @State private var posterColors: ReceiptPosterColors?
    @State private var exportDocument: ReceiptImageDocument?
    @State private var isExporting = false
    /// 系统分享用的位图（`ShareLink` 需要一个现成的 `Transferable`）。
    @State private var shareImage: Image?

    private var palette: ReceiptPalette {
        followsPoster
            ? ReceiptPalette.posterDriven(base: style.basePalette, colors: posterColors)
            : style.basePalette
    }
    private var posterMode: ReceiptPosterMode {
        keepsPosterColors ? .original : style.posterMode
    }

    /// 重新生成系统分享图的触发键：比例 / 版式 / 风格 / 两个开关 / 细节调节 / 海报是否就位。
    private var shareKey: String {
        "\(aspect.rawValue)|\(layout.rawValue)|\(style.rawValue)|\(keepsPosterColors)|\(followsPoster)"
            + "|\(tuning.typeScale.rawValue)|\(tuning.margin.rawValue)"
            + "|\(tuning.customTagline)|\(tuning.showsWatermark)|\(poster != nil)"
            + "|\(tuning.customNote)|\(tuning.showsWatchDate)|\(tuning.watchDate.timeIntervalSince1970)"
    }

    /// 预览缩放：宽高各自受限于 420×432 的展示盒，三款比例都完整可见。
    private var previewScale: CGFloat {
        min(420 / aspect.size.width, 432 / aspect.size.height)
    }

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
        .task(id: shareKey) { updateShareImage() }
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
            Text(data.subjectLabel.map { "分享卡 · \($0)" } ?? "分享卡")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text(data.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(UI.Palette.textSecondary)
            Spacer(minLength: 0)
            Text(aspect.exportText)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
        .padding(.horizontal, UI.Spacing.s6)
        .padding(.vertical, UI.Spacing.s4)
    }

    // MARK: - 预览

    private var preview: some View {
        ReceiptCardView(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, aspect: aspect, tuning: tuning
        )
            .scaleEffect(previewScale, anchor: .topLeading)
            .frame(
                width: aspect.size.width * previewScale,
                height: aspect.size.height * previewScale,
                alignment: .topLeading
            )
            .background(UI.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .hairlineBorder(radius: UI.Radius.button)
    }

    // MARK: - 风格

    private var styleList: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            aspectPicker
            layoutPicker

            HStack {
                Text("风格")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(ReceiptStyle.allCases.count) 款")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            // 十八款分两组；高度固定，避免风格变多后把面板撑长。
            ScrollView {
                VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                    styleGroup("电影感", styles: ReceiptStyle.cinematic)
                    styleGroup("主题", styles: ReceiptStyle.themes)
                }
                .padding(.trailing, 2)
            }
            .frame(height: 220)

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

            detailControls

            Text("缺字段的行不显示。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)

            Spacer(minLength: 0)
        }
        .frame(width: 340, alignment: .leading)
    }

    /// 细节调节（v1.30）：字号 / 边距 / 页脚标语 / 水印。
    private var detailControls: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            HStack(spacing: UI.Spacing.s3) {
                VStack(alignment: .leading, spacing: UI.Spacing.s1) {
                    Text("字号")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                    Picker("字号", selection: $tuning.typeScale) {
                        ForEach(ReceiptTuning.TypeScale.allCases) { scale in
                            Text(scale.displayName).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: UI.Spacing.s1) {
                    Text("边距")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                    Picker("边距", selection: $tuning.margin) {
                        ForEach(ReceiptTuning.Margin.allCases) { margin in
                            Text(margin.displayName).tag(margin)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            TextField("页脚标语（留空用影片标语）", text: $tuning.customTagline)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onChange(of: tuning.customTagline) { _, newValue in
                    let limited = String(newValue.prefix(24))
                    if limited != newValue {
                        tuning.customTagline = limited
                    }
                }

            TextField("一句短评（可选，概括你的观影感受）", text: $tuning.customNote)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onChange(of: tuning.customNote) { _, newValue in
                    let limited = String(newValue.prefix(40))
                    if limited != newValue {
                        tuning.customNote = limited
                    }
                }

            HStack(spacing: UI.Spacing.s2) {
                Toggle("印观影日期", isOn: $tuning.showsWatchDate)
                    .help("在字段表末尾多印一行「观影 · 日期」")
                if tuning.showsWatchDate {
                    DatePicker("观影日期", selection: $tuning.watchDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            Toggle("显示页脚水印", isOn: $tuning.showsWatermark)
                .help("页脚那行「显影 · 本地元数据 · 非商业分享」")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
        .foregroundStyle(UI.Palette.textPrimary)
    }

    /// 画布比例选择（v1.33）。
    private var aspectPicker: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            HStack(spacing: UI.Spacing.s2) {
                Text("比例")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Text(aspect.hint)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Picker("比例", selection: $aspect) {
                ForEach(ReceiptAspect.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            HStack(spacing: UI.Spacing.s2) {
                Text("布局")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Text(layout.hint)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Picker("布局", selection: $layout) {
                ForEach(ReceiptLayout.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func styleGroup(_ title: String, styles: [ReceiptStyle]) -> some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary.opacity(0.75))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: UI.Spacing.s3),
                    GridItem(.flexible(), spacing: UI.Spacing.s3),
                ],
                spacing: UI.Spacing.s2
            ) {
                ForEach(styles) { item in
                    styleButton(item)
                }
            }
        }
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
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("显影分享卡", image: shareImage)
                ) {
                    Label("分享…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("用系统分享菜单发送 PNG（微信 / 备忘录 / AirDrop）")
            } else {
                Button("分享…") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
            Button("保存 PNG…") { save() }
            Spacer(minLength: 0)
            Button("完成") { dismiss() }
        }
        .padding(.horizontal, UI.Spacing.s6)
        .padding(.vertical, UI.Spacing.s4)
    }

    /// 生成 `ShareLink` 用的位图（与导出同一张卡、同一尺寸）。
    private func updateShareImage() {
        guard let image = ReceiptRenderer.cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, aspect: aspect, tuning: tuning
        ) else {
            shareImage = nil
            return
        }
        shareImage = Image(nsImage: NSImage(cgImage: image, size: aspect.size))
    }

    private func copyToPasteboard() {
        guard let image = ReceiptRenderer.cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, aspect: aspect, tuning: tuning
        ) else {
            ToastCenter.shared.show("分享卡生成失败")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: aspect.size)])
        ToastCenter.shared.show("已复制分享卡")
    }

    private func save() {
        guard let png = ReceiptRenderer.pngData(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, aspect: aspect, tuning: tuning
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
