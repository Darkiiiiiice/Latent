import SwiftUI

/// 海报卡（核心组件，设计文档第 8.4 节）。
///
/// 168×252 圆角 8；下方两行：标题（13 Semibold，截断）+「年份 · ★评分」（11 Secondary，等宽数字）。
/// hover：上移 2pt + 淡阴影 + 右上角按钮淡入；选中：1px accent 描边 + 10% 外发光。
struct PosterCard<ContextMenu: View>: View {
    let summary: MediaSummary
    var isSelected: Bool = false
    var showsHoverAction: Bool = true
    let onOpen: () -> Void
    var onToggleFavorite: (() -> Void)?
    var isFavorite: Bool = false
    @ViewBuilder var contextMenu: () -> ContextMenu

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            poster
            textBlock
        }
        .frame(width: UI.Sizes.posterCard.width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(UI.Motion.cardLift) { isHovering = hovering }
        }
        .offset(y: isHovering && !reduceMotion ? -2 : 0)
        .cardHoverShadow(isHovering && !reduceMotion)
        .contextMenu { contextMenu() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var poster: some View {
        ZStack(alignment: .topTrailing) {
            PosterImage(path: summary.posterPath, displayWidth: UI.Sizes.posterCard.width)
                .frame(width: UI.Sizes.posterCard.width, height: UI.Sizes.posterCard.height)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: UI.Radius.poster, style: .continuous)
                            .strokeBorder(UI.Palette.accent, lineWidth: 1)
                    }
                }
                .overlay {
                    // 选中：accent 10% 外发光
                    if isSelected {
                        RoundedRectangle(cornerRadius: UI.Radius.poster, style: .continuous)
                            .fill(UI.Palette.accent.opacity(0.10))
                    }
                }

            if showsHoverAction, let onToggleFavorite {
                favoriteButton(action: onToggleFavorite)
                    .padding(UI.Spacing.s2)
                    .opacity(isHovering || isFavorite ? 1 : 0)
            }
        }
        .frame(width: UI.Sizes.posterCard.width, height: UI.Sizes.posterCard.height)
    }

    private func favoriteButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFavorite ? UI.Palette.accent : UI.Palette.textPrimary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "移出收藏" : "加入收藏")
        .accessibilityLabel(isFavorite ? "移出收藏" : "加入收藏")
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                if let year = summary.year {
                    NumericText(text: "\(year)", size: 11)
                }
                if let rating = Formatters.rating(summary.voteAverage) {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(UI.Palette.accent)
                        NumericText(text: rating, size: 11)
                    }
                }
            }
            .frame(height: 14)
        }
        .frame(width: UI.Sizes.posterCard.width, alignment: .leading)
    }

    private var accessibilityLabel: String {
        var parts = [summary.title]
        if let year = summary.year { parts.append("\(year) 年") }
        if let rating = Formatters.rating(summary.voteAverage) { parts.append("评分 \(rating)") }
        return parts.joined(separator: "，")
    }
}

/// 紧凑人物行（搜索结果里的人物分组、演职员列表）。
struct PersonRow: View {
    let id: Int
    let name: String
    let subtitle: String?
    let profilePath: String?
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: UI.Spacing.s3) {
            PosterImage(path: profilePath, displayWidth: 36, cornerRadius: 18)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(UI.Palette.border, lineWidth: 1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .lineLimit(1)
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
        .accessibilityLabel(subtitle.map { "\(name)，\($0)" } ?? name)
        .accessibilityAddTraits(.isButton)
    }
}
