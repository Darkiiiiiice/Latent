import SwiftUI
import AppKit

/// 片库多选手势：普通勾选 / ⇧ 连续区间。
enum MediaGridSelectionGesture: Sendable {
    case toggle
    case range
}

/// 媒体网格 / 列表（设计文档第 8.3、8.4 节）。
///
/// - 网格：自适应列，海报卡；列表：紧凑行（小海报 + 标题 + 年份评分）。
/// - 右键菜单统一由 `MediaContextMenu` 提供（收藏 / 清单 / 复制 TMDB ID / 链接 / 打开网站）。
/// - 传入 `onSelect` 即启用片库多选（v1.7）：多选模式下点按为勾选，⇧ 为区间。
struct MediaGrid: View {
    let items: [MediaSummary]
    var gridMode: Bool = true
    let open: (MediaSummary) -> Void
    var emptyMessage: String = "没有找到内容"
    /// 最后一项进入可视区域时回调（无限滚动入口）。本地库等不分页场景传 nil。
    var onReachEnd: (() -> Void)?
    /// 片库多选开关；为 nil 时保持普通「点按打开」行为。
    var onSelect: ((MediaSummary, MediaGridSelectionGesture) -> Void)?
    var isSelecting: Bool = false
    var selectedIDs: Set<String> = []
    /// 片库页才显示右键「移到另一清单」（v1.7.1）；其他页面保持原菜单。
    var allowsLibraryMove: Bool = false

    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        if items.isEmpty {
            EmptyState(message: emptyMessage)
        } else if gridMode {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: UI.Sizes.posterCard.width, maximum: UI.Sizes.posterCard.width * 1.35), spacing: UI.Spacing.gridSpacing)],
                alignment: .leading,
                spacing: UI.Spacing.gridSpacing
            ) {
                ForEach(items, id: \.stableID) { item in
                    PosterCard(
                        summary: item,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(item.stableID),
                        showsHoverAction: !isSelecting,
                        onOpen: { handleTap(item) },
                        onToggleFavorite: { appEnv.library.toggleFavorite(item) },
                        isFavorite: appEnv.library.isFavorite(item)
                    ) {
                        MediaContextMenu(summary: item, allowsLibraryMove: allowsLibraryMove)
                    }
                    .onAppear { reachEndIfLast(item) }
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.stableID) { item in
                    MediaListRow(
                        summary: item,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(item.stableID),
                        onOpen: { handleTap(item) }
                    )
                    .contextMenu { MediaContextMenu(summary: item, allowsLibraryMove: allowsLibraryMove) }
                    .onAppear { reachEndIfLast(item) }
                }
            }
        }
    }

    /// 多选模式 / ⌘ / ⇧ 时走选择；否则打开详情。
    /// 修饰键在 mouse-up 时读取，SwiftUI 的 TapGesture 不携带 modifier。
    private func handleTap(_ item: MediaSummary) {
        guard let onSelect else {
            open(item)
            return
        }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isSelecting || flags.contains(.command) || flags.contains(.shift) {
            onSelect(item, flags.contains(.shift) ? .range : .toggle)
        } else {
            open(item)
        }
    }

    private func reachEndIfLast(_ item: MediaSummary) {
        guard item.stableID == items.last?.stableID else { return }
        onReachEnd?()
    }
}

/// 列表行：小海报 + 标题 + 年份 / 评分（渐进披露，只给判断所需字段）。
struct MediaListRow: View {
    let summary: MediaSummary
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: UI.Spacing.s3) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? UI.Palette.accent : UI.Palette.textSecondary)
                    .accessibilityHidden(true)
            }

            PosterImage(path: summary.posterPath, displayWidth: 40, cornerRadius: 4)
                .frame(width: 40, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(UI.Palette.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(summary.mediaKind.label)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                    if let year = summary.year {
                        NumericText(text: "\(year)", size: 11)
                    }
                    if let rating = Formatters.rating(summary.voteAverage) {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(UI.Palette.accent)
                            NumericText(text: rating, size: 11)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UI.Spacing.s2)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .overlay {
            if isSelecting && isSelected {
                RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                    .strokeBorder(UI.Palette.accent, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(UI.Motion.hover) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isSelecting ? "点按以选择或取消选择" : "点按打开详情")
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityAction { onOpen() }
    }

    private var rowBackground: Color {
        if isSelecting && isSelected { return UI.Palette.accent.opacity(0.10) }
        return isHovering ? UI.Palette.surfaceElevated : .clear
    }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelecting && isSelected { traits.formUnion(.isSelected) }
        return traits
    }

    private var accessibilityLabel: String {
        var parts = [summary.title, summary.mediaKind.label]
        if let year = summary.year { parts.append("\(year) 年") }
        if let rating = Formatters.rating(summary.voteAverage) { parts.append("评分 \(rating)") }
        return parts.joined(separator: "，")
    }
}

/// 统一右键菜单（设计文档第 8.4 节）。
///
/// `details` 可选：详情页主海报传入后，收藏 / 入清单会一并写入富化字段（v1.9），
/// 与详情工具栏的收藏按钮行为一致。
struct MediaContextMenu: View {
    let summary: MediaSummary
    var allowsLibraryMove: Bool = false
    var details: LibraryDetails?

    @Environment(AppEnvironment.self) private var appEnv

    private var isFavorite: Bool { appEnv.library.isFavorite(summary) }
    private var isInWatchlist: Bool { appEnv.library.isInWatchlist(summary) }

    var body: some View {
        Button(isFavorite ? "移出收藏" : "加入收藏") {
            let wasFavorite = isFavorite
            appEnv.library.toggleFavorite(summary, details: details)
            ToastCenter.shared.show(wasFavorite ? "已移出收藏" : "已加入收藏")
        }
        .disabled(!summary.mediaKind.isLibraryEligible)

        Button(isInWatchlist ? "移出观看清单" : "加入观看清单") {
            let wasInWatchlist = isInWatchlist
            appEnv.library.toggleWatchlist(summary, details: details)
            ToastCenter.shared.show(wasInWatchlist ? "已移出观看清单" : "已加入观看清单")
        }
        .disabled(!summary.mediaKind.isLibraryEligible)

        if allowsLibraryMove, isFavorite, !isInWatchlist {
            Divider()
            Button("移到观看清单") {
                appEnv.library.moveToWatchlist(summary)
                ToastCenter.shared.show("已移到观看清单")
            }
        } else if allowsLibraryMove, isInWatchlist, !isFavorite {
            Divider()
            Button("移到收藏") {
                appEnv.library.moveToFavorites(summary)
                ToastCenter.shared.show("已移到收藏")
            }
        }

        Divider()

        Button("复制 TMDB ID") {
            Pasteboard.copy("\(summary.id)")
            ToastCenter.shared.show("已复制 TMDB ID：\(summary.id)")
        }

        if let url = TMDBLinks.pageURL(mediaKind: summary.mediaKind, tmdbID: summary.id) {
            Button("复制 TMDB 链接") {
                Pasteboard.copy(url.absoluteString)
                ToastCenter.shared.show("已复制链接")
            }
            Button("在 TMDB 网站打开") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// 页脚加载指示（无限滚动）。
struct FeedFooter: View {
    let state: PaginatedFeed<MediaSummary>.State
    var retry: () -> Void
    var isEmpty: Bool

    var body: some View {
        Group {
            switch state {
            case .loadingFirst:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(UI.Spacing.s6)
            case .loadingMore:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(UI.Spacing.s4)
            case .error(let message):
                ErrorBanner(message: message, retry: retry)
                    .padding(.top, UI.Spacing.s4)
            case .end where !isEmpty:
                Text("已经到底了")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(UI.Spacing.s6)
            default:
                Color.clear.frame(height: UI.Spacing.s6)
            }
        }
    }
}

/// 网格骨架屏（首屏）。
struct GridSkeleton: View {
    var count: Int = 10

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: UI.Sizes.posterCard.width, maximum: UI.Sizes.posterCard.width * 1.35), spacing: UI.Spacing.gridSpacing)],
            alignment: .leading,
            spacing: UI.Spacing.gridSpacing
        ) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                    Skeleton.block()
                        .frame(width: UI.Sizes.posterCard.width, height: UI.Sizes.posterCard.height)
                    Skeleton.textLines(width: UI.Sizes.posterCard.width)
                }
                .frame(width: UI.Sizes.posterCard.width, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}
