import SwiftUI

/// 收藏 / 观看清单页（设计文档第 8.6 节）：同款网格；排序（添加时间 / 评分 / 年份）。
struct LibraryView: View {
    let kind: LibraryKind
    let gridMode: Bool
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var sort: SortOption = .addedAt

    private var items: [LibrarySnapshot] {
        appEnv.library.items(kind: kind, sortedBy: sort)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                HStack(spacing: UI.Spacing.s3) {
                    Text(kind.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(UI.Palette.textPrimary)

                    if !items.isEmpty {
                        NumericText(text: "\(items.count)", size: 11)
                    }

                    Spacer(minLength: 0)

                    if !items.isEmpty {
                        ExportMenu(scope: kind == .favorites ? .favorites : .watchlist)

                        Picker("排序", selection: $sort) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                }

                if items.isEmpty {
                    EmptyState(
                        message: kind == .favorites ? "还没有收藏" : "观看清单是空的",
                        systemImage: kind == .favorites ? "star" : "bookmark",
                        actionTitle: "去趋势页逛逛",
                        action: { AppCommandBus.select(.trending) }
                    )
                } else {
                    MediaGrid(items: items.map(\.asSummary), gridMode: gridMode, open: open)
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            // 库数据来自本地，刷新即重读（视图已有 @Observable 联动，这里仅作界面反馈）
            ToastCenter.shared.show("已刷新")
        }
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
