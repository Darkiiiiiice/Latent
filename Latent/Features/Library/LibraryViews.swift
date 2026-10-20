import SwiftUI
import AppKit

/// 片单卡 sheet 的携带数据：点按「片单卡」时把 `kind` 与当前排序的列表快照一起传入。
///
/// 每次点按都是新 `id`，`PlaylistSheet` 因此拿到全新状态，不会沿用上一次弹窗的
/// 勾选，也不会在列表尚未就绪时读到空数组。
private struct PlaylistPresentation: Identifiable {
    let id = UUID()
    let kind: LibraryKind
    let items: [LibrarySnapshot]
}

/// 收藏 / 观看清单页（设计文档第 8.6 节）：同款网格；排序（添加时间 / 评分 / 年份）。
struct LibraryView: View {
    let kind: LibraryKind
    let gridMode: Bool
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var sort: SortOption = .addedAt
    @State private var filter = ""
    @State private var playlistPresentation: PlaylistPresentation?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var selectionAnchorID: String?
    @State private var dismissedChangeID: UUID?
    @State private var undoKeyMonitor: Any?

    private var allItems: [LibrarySnapshot] {
        appEnv.library.items(kind: kind, sortedBy: sort)
    }

    /// 当前筛选结果（v1.8）：排序后按标题 / 原始标题匹配拼音、首字母或中英文直搜。
    private var items: [LibrarySnapshot] {
        let query = trimmedFilter
        guard !query.isEmpty else { return allItems }
        return allItems.filter {
            PinyinSearch.matches(query: query, title: $0.title, originalTitle: $0.originalTitle)
        }
    }

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var orderedIDs: [String] { items.map(\.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                HStack(spacing: UI.Spacing.s3) {
                    Text(kind.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(UI.Palette.textPrimary)

                    if !allItems.isEmpty {
                        NumericText(
                            text: trimmedFilter.isEmpty
                                ? "\(allItems.count)"
                                : "\(items.count) / \(allItems.count)",
                            size: 11
                        )
                    }

                    Spacer(minLength: 0)

                    if !allItems.isEmpty {
                        filterField
                    }

                    if !items.isEmpty && !isSelecting {
                        Button {
                            // 把点按瞬间的列表快照随 sheet 一起带上：用 `item` 而非
                            // `isPresented` + 另一个 @State，避免首次弹出读到空 / 旧数组
                            // （v1.6.1 修复：片单卡弹窗显示「0 部」）。
                            playlistPresentation = PlaylistPresentation(kind: kind, items: items)
                        } label: {
                            Label("片单卡", systemImage: "square.grid.3x3.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("把当前列表（含筛选）做成一张 3:4 片单分享卡")

                        ExportMenu(scope: kind == .favorites ? .favorites : .watchlist)

                        Picker("排序", selection: $sort) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        Button {
                            beginSelection()
                        } label: {
                            Label("选择", systemImage: "checklist")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("多选：批量移出或移到另一清单")
                    }
                }

                if isSelecting {
                    selectionBar
                } else if let change = appEnv.library.lastChange, change.id != dismissedChangeID {
                    undoBar(change)
                }

                if allItems.isEmpty {
                    EmptyState(
                        message: kind == .favorites ? "还没有收藏" : "观看清单是空的",
                        systemImage: kind == .favorites ? "star" : "bookmark",
                        actionTitle: "去趋势页逛逛",
                        action: { AppCommandBus.select(.trending) }
                    )
                } else if items.isEmpty {
                    EmptyState(
                        message: "没有找到「\(trimmedFilter)」",
                        systemImage: "magnifyingglass",
                        actionTitle: "清除筛选",
                        action: { filter = "" }
                    )
                } else {
                    MediaGrid(
                        items: items.map(\.asSummary),
                        gridMode: gridMode,
                        open: open,
                        onSelect: handleSelect,
                        isSelecting: isSelecting,
                        selectedIDs: selectedIDs,
                        allowsLibraryMove: true
                    )
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .sheet(item: $playlistPresentation) { presentation in
            PlaylistSheet(kind: presentation.kind, items: presentation.items)
        }
        .onChange(of: orderedIDs) { _, ids in
            let valid = Set(ids)
            selectedIDs = LibrarySelection.clamped(selectedIDs, to: valid)
            if let selectionAnchorID, !valid.contains(selectionAnchorID) {
                self.selectionAnchorID = nil
            }
            if ids.isEmpty {
                endSelection()
            }
        }
        .onChange(of: kind) { _, _ in
            filter = ""
            endSelection()
        }
        .onAppear {
            installUndoShortcut()
        }
        .onDisappear {
            removeUndoShortcut()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            // 库数据来自本地，刷新即重读（视图已有 @Observable 联动，这里仅作界面反馈）
            ToastCenter.shared.show("已刷新")
        }
    }

    // MARK: - 筛选（v1.8）

    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)

            TextField("拼音 / 首字母筛选", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .accessibilityLabel("筛选片库")

            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("清除筛选")
                .accessibilityLabel("清除筛选")
            }
        }
        .padding(.horizontal, UI.Spacing.s2)
        .frame(width: 180, height: 24)
        .background(
            UI.Palette.surfaceElevated,
            in: RoundedRectangle(cornerRadius: UI.Radius.input, style: .continuous)
        )
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.input)
        .help("支持中文、英文、拼音全拼与首字母")
    }

    // MARK: - 多选（v1.7）

    private var selectionBar: some View {
        HStack(spacing: UI.Spacing.s3) {
            HStack(spacing: 4) {
                Text("已选")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                NumericText(
                    text: "\(selectedIDs.count)",
                    size: 13,
                    weight: .semibold,
                    color: UI.Palette.textPrimary
                )
                Text("部")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            Button(selectedIDs.count == items.count ? "取消全选" : "全选") {
                toggleSelectAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("a", modifiers: .command)
            .help("全选 / 取消全选（⌘A）")

            Spacer(minLength: UI.Spacing.s2)

            Button(kind.opposite == .watchlist ? "移到观看清单" : "移到收藏") {
                moveSelected()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedIDs.isEmpty)

            Button(kind == .favorites ? "移出收藏" : "移出观看清单", role: .destructive) {
                removeSelected()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedIDs.isEmpty)
            .keyboardShortcut(.delete, modifiers: [])
            .help("移出当前清单（⌫）")

            Button("完成") {
                endSelection()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.escape, modifiers: [])
            .help("完成选择（Esc）")
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s2)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    private func undoBar(_ change: LibraryChange) -> some View {
        HStack(spacing: UI.Spacing.s3) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 13))
                .foregroundStyle(UI.Palette.textSecondary)

            Text(undoMessage(change))
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textPrimary)

            Spacer(minLength: UI.Spacing.s2)

            Button("撤销") {
                appEnv.library.undoLastChange()
                ToastCenter.shared.show("已撤销")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("撤销（⌘Z）")

            Button {
                dismissedChangeID = change.id
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(UI.Palette.textSecondary)
            .help("关闭")
            .accessibilityLabel("关闭撤销提示")
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s2)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
        .task(id: change.id) {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            // 只收起提示条；撤销记录保留，⌘Z 仍可用。
            dismissedChangeID = change.id
        }
    }

    private func beginSelection() {
        isSelecting = true
        selectedIDs = []
        selectionAnchorID = nil
    }

    private func endSelection() {
        isSelecting = false
        selectedIDs = []
        selectionAnchorID = nil
    }

    private func handleSelect(_ item: MediaSummary, _ gesture: MediaGridSelectionGesture) {
        if !isSelecting {
            beginSelection()
        }
        switch gesture {
        case .toggle:
            selectedIDs = LibrarySelection.toggled(item.stableID, in: selectedIDs)
            selectionAnchorID = item.stableID
        case .range:
            if let anchorID = selectionAnchorID {
                selectedIDs = LibrarySelection.range(
                    from: anchorID,
                    through: item.stableID,
                    in: orderedIDs
                )
            } else {
                selectedIDs = [item.stableID]
                selectionAnchorID = item.stableID
            }
        }
    }

    private func toggleSelectAll() {
        if selectedIDs.count == items.count {
            selectedIDs = []
            selectionAnchorID = nil
        } else {
            selectedIDs = Set(orderedIDs)
            selectionAnchorID = orderedIDs.first
        }
    }

    private func removeSelected() {
        guard let change = appEnv.library.removeItems(ids: selectedIDs, from: kind) else { return }
        ToastCenter.shared.show("已从\(kind.title)移出 \(change.snapshots.count) 部")
        endSelection()
    }

    private func moveSelected() {
        let destination = kind.opposite
        guard let change = appEnv.library.moveItems(ids: selectedIDs, from: kind, to: destination) else {
            return
        }
        ToastCenter.shared.show("已移到\(destination.title) \(change.snapshots.count) 部")
        endSelection()
    }

    private func undoMessage(_ change: LibraryChange) -> String {
        let count = change.snapshots.count
        let suffix = count == 1 ? "" : " \(count) 部"
        if let destination = change.destination {
            return "已移到\(destination.title)\(suffix)"
        }
        return "已从\(change.source.title)移出\(suffix)"
    }

    // MARK: - ⌘Z（片库页定向）

    /// SwiftUI 窗口在无文本焦点时不提供可用的 UndoManager；
    /// 这里在片库页单独监听 ⌘Z，避免影响搜索框里的文字撤销。
    private func installUndoShortcut() {
        guard undoKeyMonitor == nil else { return }
        undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(.command),
                      !flags.contains(.shift),
                      !flags.contains(.option),
                      !flags.contains(.control),
                      event.charactersIgnoringModifiers?.lowercased() == "z",
                      appEnv.library.lastChange != nil,
                      NSApp.keyWindow?.sheetParent == nil,
                      !(NSApp.keyWindow?.firstResponder is NSTextView)
                else {
                    return false
                }
                appEnv.library.undoLastChange()
                ToastCenter.shared.show("已撤销")
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeUndoShortcut() {
        if let undoKeyMonitor {
            NSEvent.removeMonitor(undoKeyMonitor)
        }
        undoKeyMonitor = nil
    }
}

/// 历史页（设计文档第 8.6 节）：按「今天 / 本周 / 更早」分组；可清除全部。
struct HistoryView: View {
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var showsClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                HStack {
                    Text("历史")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(UI.Palette.textPrimary)

                    if appEnv.history.count > 0 {
                        NumericText(text: "\(appEnv.history.count) / \(HistoryStore.maximumCount)", size: 11)
                    }

                    Spacer(minLength: 0)

                    if appEnv.history.count > 0 {
                        ExportMenu(scope: .history)

                        Button("清除全部") {
                            showsClearConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if appEnv.history.count == 0 {
                    EmptyState(message: "还没有浏览记录", systemImage: "clock", actionTitle: "去趋势页逛逛") {
                        AppCommandBus.select(.trending)
                    }
                } else {
                    ForEach(appEnv.history.grouped(), id: \.title) { group in
                        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .medium))
                                .kerning(0.4)
                                .foregroundStyle(UI.Palette.textSecondary)

                            VStack(spacing: 0) {
                                ForEach(group.entries) { entry in
                                    HistoryRow(entry: entry) {
                                        open(entry.asSummary)
                                    }
                                    .contextMenu { MediaContextMenu(summary: entry.asSummary) }
                                    if entry.id != group.entries.last?.id {
                                        Divider().overlay(UI.Palette.border)
                                    }
                                }
                            }
                            .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
                            .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
                        }
                    }
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .confirmationDialog("清除全部浏览历史？", isPresented: $showsClearConfirmation) {
            Button("清除全部", role: .destructive) {
                appEnv.history.clear()
                ToastCenter.shared.show("历史已清除")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("历史仅存于本机，清除后无法恢复。")
        }
    }
}

/// 历史行：小海报 40×60 + 标题 + 时间。
struct HistoryRow: View {
    let entry: LibrarySnapshot
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: UI.Spacing.s3) {
            PosterImage(path: entry.posterPath, displayWidth: 40, cornerRadius: 4)
                .frame(width: UI.Sizes.historyThumb.width, height: UI.Sizes.historyThumb.height)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(UI.Palette.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.mediaKind.label)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                    if let year = entry.year {
                        NumericText(text: "\(year)", size: 11)
                    }
                }
            }

            Spacer(minLength: 0)

            NumericText(text: Formatters.relativeTime(entry.addedAt), size: 11)
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, 6)
        .background(isHovering ? UI.Palette.surfaceElevated : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(UI.Motion.hover) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title)，\(entry.mediaKind.label)，\(Formatters.relativeTime(entry.addedAt))")
        .accessibilityAddTraits(.isButton)
    }
}
