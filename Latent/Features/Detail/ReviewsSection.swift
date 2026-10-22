import SwiftUI

/// 影评聚合（v1.23）：只读展示 TMDB 收录的第三方影评，按页加载。
///
/// 默认只列前 3 条，其余折叠；单条正文过长时再按条折叠。
/// 拉取失败或没有影评时整段隐藏，不打扰详情主内容。
struct ReviewsSection: View {
    let mediaKind: MediaKind
    let mediaID: Int

    @Environment(AppEnvironment.self) private var appEnv
    @State private var reviews: [Review] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var didFail = false
    @State private var expandedIDs: Set<String> = []
    @State private var showsAll = false

    private var visible: [Review] {
        showsAll ? reviews : Array(reviews.prefix(3))
    }

    var body: some View {
        Group {
            if reviews.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                    HStack(alignment: .top) {
                        SectionHeader(title: "影评")
                        Spacer()
                        Text("\(reviews.count)\(hasMore ? "+" : "") 条")
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                            .padding(.top, 2)
                    }

                    VStack(spacing: UI.Spacing.s2) {
                        ForEach(visible) { review in
                            card(review)
                        }
                    }

                    if reviews.count > 3 && !showsAll {
                        Button("显示全部 \(reviews.count)\(hasMore ? "+" : "") 条影评") {
                            withAnimation(UI.Motion.hover) { showsAll = true }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.accent)
                    }

                    if hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("加载更多影评")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.accent)
                        .disabled(isLoading)
                    }
                }
            }
        }
        .task(id: "\(mediaKind.rawValue)-\(mediaID)") { await reload() }
    }

    private func card(_ review: Review) -> some View {
        let isExpanded = expandedIDs.contains(review.id)
        return VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            HStack(spacing: UI.Spacing.s2) {
                avatar(review)

                VStack(alignment: .leading, spacing: 1) {
                    Text(review.displayAuthor)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)

                    if let created = review.relativeCreatedText {
                        Text(created)
                            .font(.system(size: 10))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                }

                Spacer(minLength: UI.Spacing.s2)

                if let rating = review.ratingText {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(rating)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(UI.Palette.accent)
                }
            }

            if let body = review.bodyText {
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(isExpanded ? nil : 5)
                    .textSelection(.enabled)

                HStack(spacing: UI.Spacing.s3) {
                    if review.isLong {
                        Button(isExpanded ? "收起" : "展开全文") {
                            withAnimation(UI.Motion.hover) {
                                if isExpanded {
                                    expandedIDs.remove(review.id)
                                } else {
                                    expandedIDs.insert(review.id)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.accent)
                    }

                    if let url = review.url {
                        Link("在 TMDB 查看", destination: url)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                }
            }
        }
        .padding(UI.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    @ViewBuilder
    private func avatar(_ review: Review) -> some View {
        ZStack {
            Circle().fill(UI.Palette.surfaceElevated)

            if let path = review.avatarPath {
                PosterImage(path: path, displayWidth: 24, cornerRadius: 12)
                    .frame(width: 24, height: 24)
            } else {
                Text(review.initial)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().strokeBorder(UI.Palette.border, lineWidth: 1))
    }

    // MARK: - 加载

    private func reload() async {
        reviews = []
        page = 0
        hasMore = false
        didFail = false
        expandedIDs = []
        showsAll = false
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading, !didFail else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let next = try await appEnv.client.reviews(mediaKind: mediaKind, id: mediaID, page: page + 1)
            page = next.page
            hasMore = !next.isLastPage
            let existing = Set(reviews.map(\.id))
            reviews.append(contentsOf: next.items.filter { !existing.contains($0.id) })
        } catch {
            // 影评是附加信息：失败就隐藏整段，不弹错误横幅（与系列横条一致）。
            didFail = true
        }
    }
}
