import SwiftUI

/// 详情路由：按目的地类型分发（电影 / 剧集 / 人物）。
struct DetailRouteView: View {
    let destination: DetailDestination

    var body: some View {
        switch destination {
        case .movie(let id, let fallback):
            MovieDetailView(movieID: id, fallback: fallback)
        case .tv(let id, let fallback):
            TVShowDetailView(showID: id, fallback: fallback)
        case .person(let id):
            PersonDetailView(personID: id)
        }
    }
}

// MARK: - 电影详情

struct MovieDetailView: View {
    let movieID: Int
    let fallback: MediaSummary?

    @Environment(AppEnvironment.self) private var appEnv
    @State private var movie: MovieDetail?
    @State private var collection: MovieCollection?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showsReceipt = false
    @State private var expandedRegion: String?
    @State private var showsAllRegions = false

    var body: some View {
        MediaDetailScaffold(
            fallback: fallback,
            detail: movie,
            isLoading: isLoading,
            errorMessage: errorMessage,
            reload: { await load() },
            receiptAction: movie == nil ? nil : { showsReceipt = true },
            extraContent: { _ in
                collectionSection
                releaseSection
            }
        ) { detail in
            factsSection(detail)
        }
        .task(id: movieID) { await load() }
        .onChange(of: movie?.id) { _, _ in
            expandedRegion = movie?.defaultReleaseRegion
            showsAllRegions = false
        }
        .task(id: movie?.belongsToCollection?.id) {
            guard let collectionID = movie?.belongsToCollection?.id else {
                collection = nil
                return
            }
            await loadCollection(collectionID)
        }
        .sheet(isPresented: $showsReceipt) {
            if let movie {
                ReceiptSheet(data: ReceiptData.build(from: movie))
            }
        }
    }

    /// 所属系列（v1.19）：系列片才显示；只有一部作品的「系列」按普通电影处理，整段不出现。
    @ViewBuilder
    private var collectionSection: some View {
        if let collection, collection.parts.count > 1 {
            let parts = collection.orderedParts
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                HStack(alignment: .top) {
                    SectionHeader(title: "系列 · \(collection.name)")
                    Spacer()
                    HStack(spacing: UI.Spacing.s3) {
                        Text("共 \(parts.count) 部")
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                        Button("整系列加入清单") {
                            addSeriesToWatchlist(parts)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.accent)
                        .help("把本系列还不在清单里的作品一次加入观看清单")
                    }
                    .padding(.top, 2)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: UI.Spacing.gridSpacing) {
                        ForEach(parts) { item in
                            PosterCard(
                                summary: item,
                                showsHoverAction: false,
                                onOpen: { openSummary(item) }
                            ) {
                                MediaContextMenu(summary: item)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 发行信息（v1.20）：分地区折叠——默认展开中国大陆（无则第一个地区），
    /// 最多先列 5 个地区，其余折叠在「显示全部」后面，避免详情页被几十行地区撑长。
    @ViewBuilder
    private var releaseSection: some View {
        let regions = movie?.releaseRegions ?? []
        if !regions.isEmpty {
            let visible = showsAllRegions ? regions : Array(regions.prefix(5))
            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                HStack {
                    SectionHeader(title: "发行信息")
                    Spacer()
                    Text("\(regions.count) 个地区")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, region in
                        if index > 0 {
                            Divider().overlay(UI.Palette.border)
                        }
                        regionRow(region)
                    }
                }
                .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
                .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)

                if regions.count > 5 {
                    Button(showsAllRegions ? "收起其余地区" : "显示全部 \(regions.count) 个地区") {
                        withAnimation(UI.Motion.hover) { showsAllRegions.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func regionRow(_ region: RegionReleaseRow) -> some View {
        let isExpanded = expandedRegion == region.code
        VStack(spacing: 0) {
            Button {
                withAnimation(UI.Motion.hover) {
                    expandedRegion = isExpanded ? nil : region.code
                }
            } label: {
                HStack(spacing: UI.Spacing.s2) {
                    Text(region.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)

                    if let certification = region.certification {
                        Text(certification)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(UI.Palette.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(UI.Palette.border, lineWidth: 1)
                            )
                    }

                    Spacer(minLength: UI.Spacing.s2)

                    if let summary = region.summary {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                            .lineLimit(1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .padding(.horizontal, UI.Spacing.s3)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(region.name)，\(isExpanded ? "已展开" : "已收起")")
            .accessibilityHint("双击展开该地区的发行记录")

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(region.entries) { entry in
                        HStack(spacing: UI.Spacing.s2) {
                            Text(entry.typeLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(UI.Palette.textSecondary)
                                .frame(width: 32, alignment: .leading)
                            Text(Formatters.fullDate(entry.dayString) ?? "日期待定")
                                .font(.system(size: 12))
                                .foregroundStyle(UI.Palette.textPrimary)
                            if let note = trimmedNote(entry.note) {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(UI.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, UI.Spacing.s3)
                .padding(.bottom, UI.Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func trimmedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadCollection(_ id: Int) async {
        do {
            collection = try await appEnv.client.collection(id: id)
        } catch {
            // 系列只是附加信息：拉不到就整段隐藏，不弹错误打扰主内容。
            collection = nil
        }
    }

    private func addSeriesToWatchlist(_ parts: [MediaSummary]) {
        let missing = parts.filter { !appEnv.library.isInWatchlist($0) }
        guard !missing.isEmpty else {
            ToastCenter.shared.show("本系列已全部在清单中")
            return
        }
        for item in missing {
            appEnv.library.toggleWatchlist(item)
        }
        ToastCenter.shared.show("已加入 \(missing.count) 部到观看清单")
    }

    private func factsSection(_ detail: MovieDetail) -> some View {
        ForEach(detail.facts, id: \.label) { row in
            FactRow(label: row.label, value: row.value)
        }
    }

    /// 系列里的作品点击后推入详情（走与相似 / 推荐 rail 相同的命令）。
    private func openSummary(_ summary: MediaSummary) {
        guard let destination = DetailDestination.from(summary) else { return }
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await appEnv.client.movieDetail(id: movieID)
            movie = detail
            let summary = (fallback ?? MediaSummary(id: movieID, mediaKind: .movie, title: detail.title)).resolved(from: detail)
            appEnv.recordView(summary)
            appEnv.library.refresh(summary, details: detail.libraryDetails)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = APIError.offline.errorDescription
        }
        isLoading = false
    }
}

// MARK: - 剧集详情

struct TVShowDetailView: View {
    let showID: Int
    let fallback: MediaSummary?

    @Environment(AppEnvironment.self) private var appEnv
    @State private var show: TVShowDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var selectedSeason: Int?
    @State private var seasonDetail: SeasonDetail?
    @State private var seasonError: String?
    @State private var isLoadingSeason = false
    @State private var showsReceipt = false

    var body: some View {
        MediaDetailScaffold(
            fallback: fallback,
            detail: show,
            isLoading: isLoading,
            errorMessage: errorMessage,
            reload: { await load() },
            receiptAction: show == nil ? nil : { showsReceipt = true },
            extraContent: { detail in
                airingSection(detail)
                seasonSection(detail)
            }
        ) { detail in
            factsSection(detail)
        }
        .task(id: showID) { await load() }
        .sheet(isPresented: $showsReceipt) {
            if let show {
                ReceiptSheet(data: ReceiptData.build(from: show))
            }
        }
    }

    private func factsSection(_ detail: TVShowDetail) -> some View {
        ForEach(detail.facts, id: \.label) { row in
            FactRow(label: row.label, value: row.value)
        }
    }

    /// 追更（v1.18，设计文档第 8.6 节）：未完结的剧显示下一集与播出时间；
    /// 已完结 / 已取消的剧显示季集总数。两者都不满足时整段不出现。
    @ViewBuilder
    private func airingSection(_ detail: TVShowDetail) -> some View {
        if let next = detail.nextEpisodeToAir {
            airingRow(
                icon: "calendar.badge.clock",
                label: "下一集",
                primary: episodeLabel(next),
                trailing: Formatters.airDatePhrase(next.airDate) ?? "待定",
                emphasized: true,
                hint: Formatters.fullDate(next.airDate).map { "\($0) 播出" }
            )
        } else if detail.hasEnded {
            airingRow(
                icon: "checkmark.circle",
                label: detail.statusLabel ?? "已完结",
                primary: episodeTotals(detail),
                trailing: nil,
                emphasized: false,
                hint: nil
            )
        }
    }

    /// 「第 2 季第 5 集 · 标题」；集名缺省或与集号重复时只留集号。
    private func episodeLabel(_ episode: Episode) -> String {
        var parts: [String] = []
        if let season = episode.seasonNumber, season > 0 { parts.append("第 \(season) 季") }
        if episode.episodeNumber > 0 { parts.append("第 \(episode.episodeNumber) 集") }
        let index = parts.joined()

        let name = episode.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return index.isEmpty ? episode.displayName : index }
        return index.isEmpty ? name : "\(index) · \(name)"
    }

    /// 「共 4 季 34 集」——任一数字缺失就省略对应部分；都没有则返回空串（由调用方整行隐藏）。
    private func episodeTotals(_ detail: TVShowDetail) -> String {
        var parts: [String] = []
        if let seasons = detail.numberOfSeasons, seasons > 0 { parts.append("共 \(seasons) 季") }
        if let episodes = detail.numberOfEpisodes, episodes > 0 { parts.append("\(episodes) 集") }
        return parts.joined(separator: " ")
    }

    private func airingRow(
        icon: String,
        label: String,
        primary: String,
        trailing: String?,
        emphasized: Bool,
        hint: String?
    ) -> some View {
        HStack(spacing: UI.Spacing.s2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(emphasized ? UI.Palette.accent : UI.Palette.textSecondary)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(UI.Palette.textSecondary)

            if !primary.isEmpty {
                Text(primary)
                    .font(.system(size: 13, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: UI.Spacing.s2)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? UI.Palette.accent : UI.Palette.textSecondary)
            }
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s2)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
        .help(hint ?? "")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func seasonSection(_ detail: TVShowDetail) -> some View {
        if let seasons = detail.seasons, !seasons.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                HStack {
                    SectionHeader(title: "分集")
                    Spacer()
                    Picker("季", selection: Binding(
                        get: { selectedSeason ?? seasons.first?.seasonNumber ?? 1 },
                        set: { newValue in
                            selectedSeason = newValue
                            Task { await loadSeason(newValue) }
                        }
                    )) {
                        ForEach(seasons, id: \.seasonNumber) { season in
                            Text(season.displayName).tag(season.seasonNumber)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                if isLoadingSeason {
                    ProgressView().controlSize(.small)
                } else if let seasonError {
                    ErrorBanner(message: seasonError) {
                        Task { await loadSeason(selectedSeason ?? 1) }
                    }
                } else if let seasonDetail, let episodes = seasonDetail.episodes, !episodes.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(episodes) { episode in
                            EpisodeRow(episode: episode)
                            if episode.id != episodes.last?.id {
                                Divider().overlay(UI.Palette.border)
                            }
                        }
                    }
                    .padding(.vertical, UI.Spacing.s2)
                    .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
                    .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
                } else {
                    Text("该季暂无分集信息")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await appEnv.client.tvDetail(id: showID)
            show = detail
            let summary = (fallback ?? MediaSummary(id: showID, mediaKind: .tv, title: detail.title)).resolved(from: detail)
            appEnv.recordView(summary)
            appEnv.library.refresh(summary, details: detail.libraryDetails)
            if selectedSeason == nil, let first = detail.seasons?.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                ?? detail.seasons?.first?.seasonNumber {
                selectedSeason = first
                await loadSeason(first)
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = APIError.offline.errorDescription
        }
        isLoading = false
    }

    private func loadSeason(_ number: Int) async {
        isLoadingSeason = true
        seasonError = nil
        do {
            seasonDetail = try await appEnv.client.tvSeason(id: showID, seasonNumber: number)
        } catch let error as APIError {
            seasonError = error.errorDescription
            seasonDetail = nil
        } catch {
            seasonError = APIError.offline.errorDescription
            seasonDetail = nil
        }
        isLoadingSeason = false
    }
}

/// 分集行（设计文档第 8.6 节）：剧照缩略图 + 集号与标题 + 播出日期 · 时长 · 评分 + 简介。
struct EpisodeRow: View {
    let episode: Episode

    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: UI.Spacing.s3) {
            PosterImage(path: episode.stillPath, displayWidth: 80, cornerRadius: 4)
                .frame(width: 80, height: 45)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(UI.Palette.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: UI.Spacing.s2) {
                    NumericText(text: "E\(episode.episodeNumber)", size: 11, weight: .semibold, color: UI.Palette.textSecondary)
                        .frame(width: 26, alignment: .leading)
                    Text(episode.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let rating = Formatters.rating(episode.voteAverage) {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(UI.Palette.accent)
                            NumericText(text: rating, size: 11)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if let date = Formatters.fullDate(episode.airDate) {
                        NumericText(text: date, size: 11)
                    }
                    if let runtime = episode.runtime, let text = Formatters.runtime(minutes: runtime) {
                        Text("·").font(.system(size: 11)).foregroundStyle(UI.Palette.textSecondary)
                        NumericText(text: text, size: 11)
                    }
                }

                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                        .onTapGesture { isExpanded.toggle() }
                        .help("点击展开 / 收起简介")
                } else {
                    Text("暂无简介")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s2)
    }
}

// MARK: - 通用详情脚手架

/// 电影 / 剧集详情共用的骨架：Hero + 海报 + 标题区 + 简介 + 事实栏。
///
/// 事实栏内容与额外区块由调用方以 ViewBuilder 提供（保持具体详情类型，避免 existential）。
struct MediaDetailScaffold<Detail: MediaDetail, Facts: View, Extra: View>: View {
    let fallback: MediaSummary?
    let detail: Detail?
    let isLoading: Bool
    let errorMessage: String?
    let reload: () async -> Void
    /// 分享卡入口（电影 / 剧集详情传值；人物页不使用本骨架）。
    let receiptAction: (() -> Void)?
    @ViewBuilder let facts: (Detail) -> Facts
    @ViewBuilder let extraContent: (Detail) -> Extra

    @Environment(AppEnvironment.self) private var appEnv
    @State private var isOverviewExpanded = false

    private var summary: MediaSummary? {
        if let detail {
            return (fallback ?? MediaSummary(id: detail.id, mediaKind: detail.mediaKind, title: detail.title)).resolved(from: detail)
        }
        return fallback
    }

    init(
        fallback: MediaSummary?,
        detail: Detail?,
        isLoading: Bool,
        errorMessage: String?,
        reload: @escaping () async -> Void,
        receiptAction: (() -> Void)? = nil,
        @ViewBuilder extraContent: @escaping (Detail) -> Extra,
        @ViewBuilder facts: @escaping (Detail) -> Facts
    ) {
        self.fallback = fallback
        self.detail = detail
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.reload = reload
        self.receiptAction = receiptAction
        self.facts = facts
        self.extraContent = extraContent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                    titleSection

                    if let errorMessage {
                        ErrorBanner(message: errorMessage) {
                            Task { await reload() }
                        }
                    }

                    if isLoading && detail == nil {
                        detailSkeleton
                    } else if let detail {
                        detailsBody(detail)
                    } else if errorMessage == nil, let fallback, !fallback.mediaKind.isLibraryEligible {
                        EmptyState(message: "该条目没有更多信息", systemImage: "questionmark.circle")
                    }
                }
                .padding(.horizontal, UI.Spacing.contentMargin)
                .padding(.top, UI.Spacing.s6)
                .padding(.bottom, UI.Spacing.s8)
            }
        }
        .background(UI.Palette.bg)
        .toolbar {
            if let summary, summary.mediaKind.isLibraryEligible {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        let added = appEnv.library.toggleFavorite(summary, details: detail?.libraryDetails)
                        ToastCenter.shared.show(added ? "已加入收藏" : "已移出收藏")
                    } label: {
                        Label(
                            appEnv.library.isFavorite(summary) ? "移出收藏" : "收藏",
                            systemImage: appEnv.library.isFavorite(summary) ? "star.fill" : "star"
                        )
                    }
                    .help("收藏（⌘D）")
                    .keyboardShortcut("d", modifiers: .command)

                    Button {
                        let added = appEnv.library.toggleWatchlist(summary, details: detail?.libraryDetails)
                        ToastCenter.shared.show(added ? "已加入观看清单" : "已移出观看清单")
                    } label: {
                        Label(
                            appEnv.library.isInWatchlist(summary) ? "移出清单" : "加入清单",
                            systemImage: appEnv.library.isInWatchlist(summary) ? "bookmark.fill" : "bookmark"
                        )
                    }
                    .help("观看清单（⇧⌘D）")
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
            }

            if let receiptAction {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: receiptAction) {
                        Label("分享卡", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                    }
                    .help("生成分享卡（发朋友圈用）")
                }
            }
        }
    }

    /// Hero：w1280 背景图，向下渐隐到窗口底色。
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let backdrop = detail?.backdropPath ?? fallback?.backdropPath {
                PosterImage(path: backdrop, displayWidth: UI.Sizes.detailHeroHeight, cornerRadius: 0, contentMode: .fill)
                    .frame(height: UI.Sizes.detailHeroHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: UI.Palette.bg.opacity(0.25), location: 0),
                                .init(color: UI.Palette.bg.opacity(0.75), location: 0.7),
                                .init(color: UI.Palette.bg, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                UI.Palette.surface
                    .frame(height: 120)
            }
        }
        .frame(height: detail?.backdropPath != nil || fallback?.backdropPath != nil ? UI.Sizes.detailHeroHeight : 120)
        .clipped()
    }

    /// 标题区：海报 w500 + 标题 / 原名 / 评分 / 类型。
    private var titleSection: some View {
        HStack(alignment: .top, spacing: UI.Spacing.s6) {
            if let summary, summary.mediaKind.isLibraryEligible {
                PosterImage(path: summary.posterPath, displayWidth: 168)
                    .frame(width: 168, height: 252)
                    .overlay(RoundedRectangle(cornerRadius: UI.Radius.poster, style: .continuous).strokeBorder(UI.Palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
                    .contentShape(RoundedRectangle(cornerRadius: UI.Radius.poster, style: .continuous))
                    .contextMenu {
                        MediaContextMenu(summary: summary, details: detail?.libraryDetails)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                Text(summary?.title ?? "载入中…")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(2)

                if let original = summary?.originalTitle, original != summary?.title {
                    Text(original)
                        .font(.system(size: 13))
                        .foregroundStyle(UI.Palette.textSecondary)
                }

                HStack(spacing: UI.Spacing.s3) {
                    if let summary {
                        RatingRing(rating: summary.voteAverage)
                        VStack(alignment: .leading, spacing: 2) {
                            if let count = summary.voteCount, count > 0 {
                                NumericText(
                                    text: count < 20 ? "\(count) 票 · 样本不足" : "\(count) 票",
                                    size: 11
                                )
                            }
                            if let year = summary.year {
                                NumericText(text: "\(year)", size: 11)
                            }
                        }
                    }
                }

                if let genres = detail?.genres, !genres.isEmpty {
                    GenreChips(genres: genres)
                }
            }
        }
    }

    @ViewBuilder
    private func detailsBody(_ detail: Detail) -> some View {
        HStack(alignment: .top, spacing: UI.Spacing.s6) {
            VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                extraContent(detail)
                overviewSection(detail)
                watchSection(detail)
                creditsSection(detail)
                railSection(title: "剧照", items: detail.images?.stills.map(\.filePath) ?? [], width: 168, height: 95, cornerRadius: 4)
                railSection(title: "相似", media: detail.similar ?? [], open: openSummary)
                railSection(title: "推荐", media: detail.recommendations ?? [], open: openSummary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 事实栏：固定 280，随内容滚动
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "事实")
                facts(detail)
                Divider().overlay(UI.Palette.border).padding(.vertical, UI.Spacing.s2)
                FactRow(label: "TMDB", value: "\(detail.id)", copyText: "\(detail.id)")
                if let imdb = detail.externalIDs?.imdbID, let url = TMDBLinks.imdbURL(imdbID: imdb) {
                    HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
                        Text("IMDB")
                            .font(.system(size: 11, weight: .medium))
                            .kerning(0.4)
                            .foregroundStyle(UI.Palette.textSecondary)
                            .frame(width: 64, alignment: .leading)
                        Link(imdb, destination: url)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(width: UI.Sizes.factColumnWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func overviewSection(_ detail: Detail) -> some View {
        let overview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overview, !overview.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                SectionHeader(title: "简介")
                Text(overview)
                    .font(.system(size: 13))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineSpacing(3)
                    .lineLimit(isOverviewExpanded ? nil : 4)
                Button(isOverviewExpanded ? "收起" : "展开全文") {
                    withAnimation(UI.Motion.hover) { isOverviewExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.accent)
            }
        } else {
            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                SectionHeader(title: "简介")
                Text("暂无简介")
                    .font(.system(size: 13))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
    }

    /// 观看平台：没有数据时整段隐藏。
    @ViewBuilder
    private func watchSection(_ detail: Detail) -> some View {
        if let providers = detail.watchProviders {
            WatchProvidersSection(providers: providers)
        }
    }

    @ViewBuilder
    private func creditsSection(_ detail: Detail) -> some View {
        let cast = detail.credits?.cast ?? []
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                SectionHeader(title: "演职员")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: UI.Spacing.s3) {
                        ForEach(cast.prefix(20)) { member in
                            CastAvatar(member: member)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func railSection(title: String, items: [String], width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UI.Spacing.s2) {
                        ForEach(items, id: \.self) { path in
                            PosterImage(path: path, displayWidth: width, cornerRadius: cornerRadius)
                                .frame(width: width, height: height)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func railSection(title: String, media: [MediaSummary], open: @escaping (MediaSummary) -> Void) -> some View {
        let items = dedupe(media)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: UI.Spacing.gridSpacing) {
                        ForEach(items) { item in
                            PosterCard(
                                summary: item,
                                showsHoverAction: false,
                                onOpen: { open(item) }
                            ) {
                                MediaContextMenu(summary: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func dedupe(_ items: [MediaSummary]) -> [MediaSummary] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.mediaKind.rawValue)-\($0.id)").inserted }
    }

    private func openSummary(_ summary: MediaSummary) {
        guard let destination = DetailDestination.from(summary) else { return }
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
    }

    private var detailSkeleton: some View {
        HStack(alignment: .top, spacing: UI.Spacing.s6) {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                Skeleton.textLines(width: 320, lines: 4)
                Skeleton.block()
                    .frame(height: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Skeleton.textLines(width: UI.Sizes.factColumnWidth, lines: 5)
        }
    }
}

/// 演职员头像（64 全圆 + 姓名 + 角色，点击进入人物页）。
struct CastAvatar: View {
    let member: CastMember

    /// 文字列宽（略宽于头像，减少截断；间距保证相邻两列不会贴在一起）。
    private let textWidth: CGFloat = 88

    var body: some View {
        Button {
            NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: DetailDestination.person(id: member.id))
        } label: {
            VStack(spacing: UI.Spacing.s2) {
                PosterImage(path: member.profilePath, displayWidth: UI.Sizes.castAvatar, cornerRadius: UI.Sizes.castAvatar / 2)
                    .frame(width: UI.Sizes.castAvatar, height: UI.Sizes.castAvatar)
                    // 竖图按圆裁切（PosterImage 已按 frame 裁切，这里再收成整圆）
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(UI.Palette.border, lineWidth: 1))

                Text(member.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(width: textWidth)

                if let character = member.characterOrNil {
                    Text(character)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(width: textWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(member.characterOrNil.map { "查看 \(member.name)（\($0)）" } ?? "查看 \(member.name)")
    }
}

/// 分区标题（13 Semibold + 细分隔线）。
struct SectionHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Rectangle()
                .fill(UI.Palette.border)
                .frame(height: 1)
        }
    }
}

/// 观看平台区块：订阅 / 免费 / 广告合并为「在线看」，租借与购买分列；无地区可显示时整段隐藏。
struct WatchProvidersSection: View {
    let providers: WatchProviders

    /// 用户手动选择的地区；nil 表示用默认地区（中国大陆优先）。
    @State private var selectedRegionCode: String?

    var body: some View {
        if let region = providers.region(for: selectedRegionCode) {
            let regions = providers.availableRegions
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
                    Text("在哪看")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(UI.Palette.textPrimary)

                    if regions.count > 1 {
                        Menu {
                            ForEach(regions) { option in
                                Button {
                                    selectedRegionCode = option.code
                                } label: {
                                    if option.code == region.code {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(region.name)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("切换观看地区")
                    } else {
                        Text(region.name)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }

                    Spacer(minLength: 0)
                }

                Rectangle()
                    .fill(UI.Palette.border)
                    .frame(height: 1)

                ForEach(region.region.groups) { group in
                    HStack(alignment: .center, spacing: UI.Spacing.s3) {
                        Text(group.kind.label)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                            .frame(width: 48, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: UI.Spacing.s2) {
                                ForEach(group.providers) { provider in
                                    WatchProviderBadge(provider: provider)
                                }
                            }
                        }
                    }
                }

                if let link = region.region.link {
                    Link(destination: link) {
                        HStack(spacing: 2) {
                            Text("在 TMDB 查看全部渠道")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 单个观看平台：白色底托住透明 Logo，右侧跟平台名。
struct WatchProviderBadge: View {
    let provider: WatchProvider

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white)
                PosterImage(
                    path: provider.logoPath,
                    displayWidth: 22,
                    cornerRadius: 4,
                    contentMode: .fit
                )
                .padding(2)
            }
            .frame(width: 24, height: 24)

            Text(provider.providerName)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, UI.Spacing.s2)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(UI.Palette.surface)
        }
        .hairlineBorder(radius: 7)
        .help(provider.providerName)
    }
}
