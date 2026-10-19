import SwiftUI
import AppKit

/// 媒体网格 / 列表（设计文档第 8.3、8.4 节）。
///
/// - 网格：自适应列，海报卡；列表：紧凑行（小海报 + 标题 + 年份评分）。
/// - 右键菜单统一由 `MediaContextMenu` 提供（收藏 / 清单 / 复制 TMDB ID / 链接 / 打开网站）。
struct MediaGrid: View {
    let items: [MediaSummary]
    var gridMode: Bool = true
    let open: (MediaSummary) -> Void
    var emptyMessage: String = "没有找到内容"
    /// 最后一项进入可视区域时回调（无限滚动入口）。本地库等不分页场景传 nil。
    var onReachEnd: (() -> Void)?

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
                ForEach(items) { item in
                    PosterCard(
                        summary: item,
                        onOpen: { open(item) },
                        onToggleFavorite: { appEnv.library.toggleFavorite(item) },
                        isFavorite: appEnv.library.isFavorite(item)
                    ) {
                        MediaContextMenu(summary: item)
                    }
                    .onAppear { reachEndIfLast(item) }
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(items) { item in
                    MediaListRow(summary: item, onOpen: { open(item) })
                        .contextMenu { MediaContextMenu(summary: item) }
                        .onAppear { reachEndIfLast(item) }
                }
            }
        }
    }

    private func reachEndIfLast(_ item: MediaSummary) {
        guard item.id == items.last?.id else { return }
        onReachEnd?()
    }
}

/// 列表行：小海报 + 标题 + 年份 / 评分（渐进披露，只给判断所需字段）。
struct MediaListRow: View {
    let summary: MediaSummary
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: UI.Spacing.s3) {
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
        .background(isHovering ? UI.Palette.surfaceElevated : .clear, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(UI.Motion.hover) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [summary.title, summary.mediaKind.label]
        if let year = summary.year { parts.append("\(year) 年") }
        if let rating = Formatters.rating(summary.voteAverage) { parts.append("评分 \(rating)") }
        return parts.joined(separator: "，")
    }
}

/// 统一右键菜单（设计文档第 8.4 节）。
struct MediaContextMenu: View {
    let summary: MediaSummary

    @Environment(AppEnvironment.self) private var appEnv

    private var isFavorite: Bool { appEnv.library.isFavorite(summary) }
    private var isInWatchlist: Bool { appEnv.library.isInWatchlist(summary) }

    var body: some View {
        Button(isFavorite ? "移出收藏" : "加入收藏") {
            appEnv.library.toggleFavorite(summary)
            ToastCenter.shared.show(isFavorite ? "已移出收藏" : "已加入收藏")
        }
        .disabled(!summary.mediaKind.isLibraryEligible)

        Button(isInWatchlist ? "移出观看清单" : "加入观看清单") {
            appEnv.library.toggleWatchlist(summary)
            ToastCenter.shared.show(isInWatchlist ? "已移出观看清单" : "已加入观看清单")
        }
        .disabled(!summary.mediaKind.isLibraryEligible)

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
