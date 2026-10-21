import SwiftUI

/// 制片公司页（v1.21）：公司信息 + 该公司最新上映的作品。
struct CompanyDetailView: View {
    let companyID: Int
    /// 从电影详情进来时先显示公司名，避免加载期间出现「载入中…」。
    let fallbackName: String?

    @Environment(AppEnvironment.self) private var appEnv
    @State private var company: CompanyDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var feed: PaginatedFeed<MediaSummary>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                header

                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                }

                if isLoading && company == nil {
                    Skeleton.textLines(width: 420, lines: 3)
                } else if company != nil {
                    biographySection
                    worksSection
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: companyID) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: UI.Spacing.s6) {
            companyLogo

            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                Text(company?.name ?? fallbackName ?? "载入中…")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)

                if let country = company?.countryName {
                    Text(country)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let headquarters = company?.headquarters {
                        factLine("总部", headquarters)
                    }
                    if let parent = company?.parentCompany {
                        factLine("母公司", parent.name)
                    }
                    if let homepage = company?.homepage {
                        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
                            Text("官网")
                                .font(.system(size: 11, weight: .medium))
                                .kerning(0.4)
                                .foregroundStyle(UI.Palette.textSecondary)
                                .frame(width: 48, alignment: .leading)
                            Link(homepage.absoluteString, destination: homepage)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    factLine("TMDB", "\(companyID)")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    /// 公司 Logo：白底托住透明 PNG，没有 Logo 时用建筑图标占位。
    @ViewBuilder
    private var companyLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(company?.logoPath == nil ? UI.Palette.surface : Color.white)

            if let logoPath = company?.logoPath {
                PosterImage(path: logoPath, displayWidth: 92, cornerRadius: 8, contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: "building.2")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
        .frame(width: 96, height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(UI.Palette.border, lineWidth: 1)
        )
    }

    private func factLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textPrimary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var biographySection: some View {
        if let biography = company?.biography {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                SectionHeader(title: "简介")
                Text(biography)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    /// 作品：按上映日期由新到旧，滚动到底继续加载。
    private var worksSection: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            HStack {
                SectionHeader(title: "作品")
                Spacer()
                Text("最新上映")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            if let feed {
                if case .error(let message) = feed.state, feed.items.isEmpty {
                    ErrorBanner(message: message) { Task { await feed.retry() } }
                } else if feed.state.isInitialLoading {
                    GridSkeleton(count: 10)
                } else {
                    MediaGrid(
                        items: feed.items,
                        gridMode: true,
                        open: open,
                        emptyMessage: "这家公司暂无收录作品",
                        onReachEnd: { Task { await feed.loadMoreIfNeeded(currentItem: feed.items.last) } }
                    )
                    FeedFooter(state: feed.state, retry: { Task { await feed.retry() } }, isEmpty: feed.items.isEmpty)
                }
            } else {
                GridSkeleton(count: 10)
            }
        }
    }

    private func open(_ summary: MediaSummary) {
        guard let destination = DetailDestination.from(summary) else { return }
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            company = try await appEnv.client.company(id: companyID)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = APIError.offline.errorDescription
        }
        isLoading = false
        if errorMessage == nil {
            await loadWorks()
        }
    }

    private func loadWorks() async {
        let client = appEnv.client
        let id = companyID
        let newFeed = PaginatedFeed<MediaSummary> { page in
            var query = DiscoverQuery()
            query.companyID = id
            query.sortBy = .newest
            let paged = try await client.discover(mediaKind: .movie, query: query, page: page)
            return (paged.items, paged.isLastPage)
        }
        feed = newFeed
        await newFeed.loadFirstPageIfNeeded()
    }
}
