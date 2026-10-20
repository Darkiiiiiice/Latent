import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

/// 片单卡预览与导出（收藏 / 观看清单页唤起；设计文档第 8.10 节）。
///
/// 左侧是 0.6 缩放的卡片预览，右侧改标题、勾选作品、换风格。默认预选当前排序的
/// 前 12 部；最多 12 部。导出与预览共用 `PlaylistCardView`，所见即所得。
struct PlaylistSheet: View {
    let kind: LibraryKind
    /// 打开面板时的列表快照（已按页面当前排序）。
    let items: [LibrarySnapshot]

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedIDs: Set<String>
    @State private var style: ReceiptStyle = .thermal
    /// 海报保留封面原色（默认关：走该风格的固有双色调 / 灰度处理）。
    @State private var keepsPosterColors = false

    /// 原始海报（用于导出时按当前风格重新处理）。
    @State private var rawPosters: [String: CGImage] = [:]
    /// 预览用的已处理海报，避免标题输入时反复跑 Core Image。
    @State private var processedPosters: [String: CGImage] = [:]
    @State private var isLoadingPosters = true
    /// 连续勾选 / 取消时，只让最后一轮加载改写状态。
    @State private var loadGeneration = 0

    @State private var exportDocument: ReceiptImageDocument?
    @State private var isExporting = false
    /// 系统分享用的位图（`ShareLink` 需要一个现成的 `Transferable`）。
    @State private var shareImage: Image?

    private let previewScale: CGFloat = 0.6

    init(kind: LibraryKind, items: [LibrarySnapshot]) {
        self.kind = kind
        self.items = items
        _title = State(initialValue: kind == .favorites ? "我的收藏" : "我的观看清单")
        _selectedIDs = State(
            initialValue: Set(items.prefix(PlaylistCardData.maximumItems).map(\.id))
        )
    }

    // MARK: - 派生状态

    private var selectedItems: [LibrarySnapshot] {
        Array(
            items
                .filter { selectedIDs.contains($0.id) }
                .prefix(PlaylistCardData.maximumItems)
        )
    }

    private var cardData: PlaylistCardData {
        .build(title: title, kind: kind, items: selectedItems)
    }

    private var posterMode: ReceiptPosterMode {
        keepsPosterColors ? .original : style.posterMode
    }

    private var selectedKey: String {
        selectedItems.map(\.id).joined(separator: "|")
    }

    /// 预览重算键：选片 / 风格 / 原色开关 / 已加载海报数量。
    private var previewRenderKey: String {
        "\(selectedKey)|\(style.rawValue)|\(keepsPosterColors)|\(rawPosters.count)"
    }

    /// 分享图重算键：卡片内容 + 海报是否还在加载。
    private var shareKey: String {
        "\(previewRenderKey)|\(title)|\(isLoadingPosters)"
    }

    private var canExport: Bool {
        !cardData.items.isEmpty && !isLoadingPosters
    }

    // MARK: - 页面

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: UI.Spacing.s6) {
                preview
                controls
            }
            .padding(UI.Spacing.s6)
            Divider()
            actions
        }
        .frame(width: 900)
        .background(UI.Palette.bg)
        .task(id: selectedKey) { await loadPosters(for: selectedItems) }
        .task(id: previewRenderKey) { rebuildProcessedPosters() }
        .task(id: shareKey) { await updateShareImage() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .png,
            defaultFilename: PlaylistRenderer.filename(title: cardData.title)
        ) { result in
            exportDocument = nil
            switch result {
            case .success:
                ToastCenter.shared.show("已保存片单卡")
            case .failure(let error):
                ToastCenter.shared.show("保存失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: UI.Spacing.s3) {
            Text("片单卡")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("\(kind.title) · \(cardData.items.count) 部")
                .font(.system(size: 12))
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
        PlaylistCardView(data: cardData, style: style, posters: processedPosters)
            .scaleEffect(previewScale, anchor: .topLeading)
            .frame(
                width: ReceiptCanvas.size.width * previewScale,
                height: ReceiptCanvas.size.height * previewScale,
                alignment: .topLeading
            )
            .background(UI.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .hairlineBorder(radius: UI.Radius.button)
            .overlay(alignment: .bottomTrailing) {
                if isLoadingPosters {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("加载封面")
                            .font(.system(size: 10))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                }
            }
    }

    // MARK: - 右侧控件

    private var controls: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s4) {
            titleEditor
            selectionEditor
            styleEditor

            Toggle("保留封面原色", isOn: $keepsPosterColors)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textPrimary)
                .help("所有海报都不套双色调 / 灰度 / 反相，直接印封面原色")
                .disabled(cardData.items.isEmpty)

            Text("缺海报的作品用该款双色调渐变占位，不伪造封面。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
        .frame(width: 480, alignment: .leading)
    }

    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            HStack {
                Text("片单标题")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(title.count) / 20")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary.opacity(0.75))
            }
            TextField("我的片单", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onChange(of: title) { _, newValue in
                    let limited = String(newValue.prefix(20))
                    if limited != newValue {
                        title = limited
                    }
                }
        }
    }

    private var selectionEditor: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            HStack {
                Text("选择作品")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Text("\(selectedIDs.count) / \(PlaylistCardData.maximumItems)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(
                        selectedIDs.count >= PlaylistCardData.maximumItems
                            ? UI.Palette.accent
                            : UI.Palette.textSecondary
                    )
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        selectionRow(item)
                        if item.id != items.last?.id {
                            Divider().overlay(UI.Palette.border)
                        }
                    }
                }
            }
            .frame(height: 220)
            .background(
                UI.Palette.surface,
                in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
            )
            .hairlineBorder(radius: UI.Radius.button)

            Text(selectionHint)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    private var selectionHint: String {
        if selectedIDs.count >= PlaylistCardData.maximumItems {
            return "已达 12 部上限；先取消一部再换。卡片顺序跟随列表当前排序。"
        }
        if items.count <= PlaylistCardData.maximumItems {
            return "已全选；取消勾选即可去掉不想放进卡片的作品。"
        }
        return "最多 12 部；卡片顺序跟随列表当前排序。"
    }

    private func selectionRow(_ item: LibrarySnapshot) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        let isDisabled = !isSelected && selectedIDs.count >= PlaylistCardData.maximumItems

        return Button {
            toggle(item)
        } label: {
            HStack(spacing: UI.Spacing.s2) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? UI.Palette.accent
                            : UI.Palette.textSecondary.opacity(0.55)
                    )
                    .frame(width: 14)

                PosterImage(path: item.posterPath, displayWidth: 24, cornerRadius: 3)
                    .frame(width: 24, height: 36)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(UI.Palette.border, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(UI.Palette.textPrimary)
                    HStack(spacing: 5) {
                        Text(item.mediaKind.label)
                        if let year = item.year {
                            Text(String(year)).monospacedDigit()
                        }
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(UI.Palette.textSecondary)
                }

                Spacer(minLength: 4)

                if let rating = item.voteAverage {
                    NumericText(text: String(format: "%.1f", rating), size: 10)
                }
            }
            .padding(.horizontal, UI.Spacing.s2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .opacity(isDisabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? "最多选 12 部" : "")
    }

    private var styleEditor: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            Text("风格")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(UI.Palette.textSecondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: UI.Spacing.s2),
                    count: 4
                ),
                spacing: UI.Spacing.s2
            ) {
                ForEach(ReceiptStyle.allCases) { item in
                    styleButton(item)
                }
            }
        }
    }

    private func styleButton(_ item: ReceiptStyle) -> some View {
        let base = item.basePalette
        return Button {
            style = item
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(base.paper.color)
                    .frame(width: 14, height: 20)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(base.accent.color).frame(height: 4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(UI.Palette.border, lineWidth: 1)
                    }
                Text(item.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(UI.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style == item ? UI.Palette.surfaceElevated : UI.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                    .strokeBorder(
                        style == item ? UI.Palette.accent : UI.Palette.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private var actions: some View {
        HStack(spacing: UI.Spacing.s3) {
            Button("复制到剪贴板") { copyToPasteboard() }
                .buttonStyle(.borderedProminent)
                .disabled(!canExport)
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("显影片单卡", image: shareImage)
                ) {
                    Label("分享…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!canExport)
                .help("用系统分享菜单发送 PNG（微信 / 备忘录 / AirDrop）")
            } else {
                Button("分享…") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
            Button("保存 PNG…") { save() }
                .buttonStyle(.bordered)
                .disabled(!canExport)

            if isLoadingPosters {
                ProgressView().controlSize(.small)
                Text("加载封面…")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            Spacer(minLength: 0)

            Text("\(cardData.items.count) 部")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(UI.Palette.textSecondary)
            Button("完成") { dismiss() }
        }
        .padding(.horizontal, UI.Spacing.s6)
        .padding(.vertical, UI.Spacing.s4)
    }

    // MARK: - 数据

    private func toggle(_ item: LibrarySnapshot) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else if selectedIDs.count < PlaylistCardData.maximumItems {
            selectedIDs.insert(item.id)
        }
    }

    private func loadPosters(for snapshots: [LibrarySnapshot]) async {
        loadGeneration += 1
        let generation = loadGeneration

        // 只保留当前选中的原始海报，避免连续换片把整库大图都留在内存里。
        let activeIDs = Set(snapshots.map(\.id))
        rawPosters = rawPosters.filter { activeIDs.contains($0.key) }

        let requests = snapshots.compactMap { item -> (id: String, path: String)? in
            guard let path = item.posterPath,
                  !path.isEmpty,
                  rawPosters[item.id] == nil else { return nil }
            return (item.id, path)
        }

        guard !requests.isEmpty else {
            isLoadingPosters = false
            return
        }

        isLoadingPosters = true
        let loaded = await withTaskGroup(
            of: (String, CGImage?).self,
            returning: [(String, CGImage?)].self
        ) { group in
            for request in requests {
                group.addTask {
                    // 1 部单列时海报宽 250pt（导出 @2x = 500px），统一按这个上限取图。
                    let image = try? await ImagePipeline.shared.image(
                        for: request.path,
                        displayWidth: 250
                    )
                    return (request.id, image)
                }
            }
            var result: [(String, CGImage?)] = []
            for await item in group {
                result.append(item)
            }
            return result
        }

        guard generation == loadGeneration, !Task.isCancelled else { return }
        for (id, image) in loaded {
            if let image {
                rawPosters[id] = image
            }
        }
        isLoadingPosters = false
    }

    /// 按当前风格重算预览海报；只在选片 / 风格 / 原色开关变化时执行。
    private func rebuildProcessedPosters() {
        let palette = style.basePalette
        var result: [String: CGImage] = [:]
        for item in cardData.items {
            guard let raw = rawPosters[item.id],
                  let processed = ReceiptPosterProcessor.processed(
                      raw,
                      mode: posterMode,
                      palette: palette
                  ) else { continue }
            result[item.id] = processed
        }
        processedPosters = result
    }

    // MARK: - 分享 / 导出

    /// 生成分享图；250ms 防抖，避免标题逐字输入时反复离屏渲染。
    private func updateShareImage() async {
        shareImage = nil
        guard canExport else { return }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, canExport else { return }

        guard let image = PlaylistRenderer.cgImage(
            data: cardData,
            style: style,
            posterMode: posterMode,
            posters: rawPosters
        ) else { return }

        shareImage = Image(nsImage: NSImage(cgImage: image, size: ReceiptCanvas.size))
    }

    private func copyToPasteboard() {
        guard let image = PlaylistRenderer.cgImage(
            data: cardData,
            style: style,
            posterMode: posterMode,
            posters: rawPosters
        ) else {
            ToastCenter.shared.show("片单卡生成失败")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: ReceiptCanvas.size)])
        ToastCenter.shared.show("已复制片单卡")
    }

    private func save() {
        guard let png = PlaylistRenderer.pngData(
            data: cardData,
            style: style,
            posterMode: posterMode,
            posters: rawPosters
        ) else {
            ToastCenter.shared.show("片单卡生成失败")
            return
        }
        exportDocument = ReceiptImageDocument(data: png)
        isExporting = true
    }
}
