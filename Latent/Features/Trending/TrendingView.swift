import SwiftUI

/// 趋势页（设计文档第 8.6 节）：分段 `[今日|本周] × [电影|剧集]`，默认「今日 · 电影」。
struct TrendingView: View {
    let gridMode: Bool
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var window: Endpoint.TrendingWindow = .day
    @State private var mediaKind: MediaKind = .movie
    @State private var feed: PaginatedFeed<MediaSummary>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                header

                if let feed {
                    // 首屏失败：只显示内联错误横幅 + 重试，不与「没有找到内容」空状态同时出现（设计文档第 4 节错误态）。
                    if case .error(let message) = feed.state, feed.items.isEmpty {
                        ErrorBanner(message: message) { Task { await feed.retry() } }
                    } else if feed.state.isInitialLoading {
                        GridSkeleton(count: 10)
                    } else {
                        MediaGrid(items: feed.items, gridMode: gridMode, open: open, onReachEnd: {
                            Task { await feed.loadMoreIfNeeded(currentItem: feed.items.last) }
                        })
                        FeedFooter(state: feed.state, retry: { Task { await feed.retry() } }, isEmpty: feed.items.isEmpty)
                    }
                } else {
                    GridSkeleton(count: 10)
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: "\(window.rawValue)-\(mediaKind.rawValue)") {
            await loadFeed()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            Task { await feed?.reload() }
        }
    }

    private var header: some View {
        HStack(spacing: UI.Spacing.s3) {
            Text("趋势")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)

            Picker("时间", selection: $window) {
                ForEach(Endpoint.TrendingWindow.allCases, id: \.self) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            Picker("类型", selection: $mediaKind) {
                Text("电影").tag(MediaKind.movie)
                Text("剧集").tag(MediaKind.tv)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            Spacer(minLength: 0)

            SurpriseMeButton(items: feed?.items ?? [], open: open)
        }
    }

    private func loadFeed() async {
        let client = appEnv.client
        let window = self.window
        let mediaKind = self.mediaKind
        let newFeed = PaginatedFeed<MediaSummary> { page in
            let paged = try await client.trending(mediaKind: mediaKind, window: window, page: page)
            return (paged.items, paged.isLastPage)
        }
        feed = newFeed
        await newFeed.loadFirstPageIfNeeded()
    }
}

/// 发现页（P3）：类型 / 年份 / 评分 / 排序筛选，变化防抖 300ms 刷新。
struct DiscoverView: View {
    let gridMode: Bool
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var mediaKind: MediaKind = .movie
    @State private var query = DiscoverQuery()
    @State private var genres: [Genre] = []
    @State private var feed: PaginatedFeed<MediaSummary>?
    @State private var debouncer = Debouncer()

    private let years: [Int] = Array((1950...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                HStack(spacing: UI.Spacing.s3) {
                    Text("发现")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(UI.Palette.textPrimary)

                    Spacer(minLength: 0)

                    SurpriseMeButton(items: feed?.items ?? [], open: open)
                }

                filterBar

                if let feed {
                    // 首屏失败：只显示内联错误横幅 + 重试，不与「当前筛选条件下没有结果」空状态同时出现（设计文档第 4 节错误态）。
                    if case .error(let message) = feed.state, feed.items.isEmpty {
                        ErrorBanner(message: message) { Task { await feed.retry() } }
                    } else if feed.state.isInitialLoading {
                        GridSkeleton(count: 12)
                    } else {
                        MediaGrid(items: feed.items, gridMode: gridMode, open: open, emptyMessage: "当前筛选条件下没有结果", onReachEnd: {
                            Task { await feed.loadMoreIfNeeded(currentItem: feed.items.last) }
                        })
                        FeedFooter(state: feed.state, retry: { Task { await feed.retry() } }, isEmpty: feed.items.isEmpty)
                    }
                } else {
                    GridSkeleton(count: 12)
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task {
            await loadGenres()
            await loadFeed()
        }
        .onChange(of: mediaKind) { _, _ in
            // 电影 / 剧集的类型 ID 属于两套体系，切换时清空已选类型并重新拉取。
            query.genreIDs.removeAll()
            genres = []
            Task { await loadGenres() }
            scheduleReload()
        }
        .onChange(of: query) { _, _ in
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            Task { await feed?.reload() }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            HStack(spacing: UI.Spacing.s3) {
                Picker("类型", selection: $mediaKind) {
                    Text("电影").tag(MediaKind.movie)
                    Text("剧集").tag(MediaKind.tv)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Picker("排序", selection: $query.sortBy) {
                    ForEach(DiscoverQuery.SortBy.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Spacer(minLength: 0)

                Button("重置") {
                    query = DiscoverQuery()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(query.isEmpty)
            }

            // 类型多选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(genres) { genre in
                        genreToggle(genre)
                    }
                }
            }

            HStack(spacing: UI.Spacing.s6) {
                // 年份区间
                HStack(spacing: UI.Spacing.s2) {
                    Text("年份")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(UI.Palette.textSecondary)
                    yearPicker(title: "不限", selection: $query.yearFrom)
                    Text("–").foregroundStyle(UI.Palette.textSecondary)
                    yearPicker(title: "不限", selection: $query.yearTo)
                }

                // 最低评分
                HStack(spacing: UI.Spacing.s2) {
                    Text("最低评分")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(UI.Palette.textSecondary)
                    Picker("最低评分", selection: $query.minRating) {
                        Text("不限").tag(Double?.none)
                        Text("6.0").tag(Double?.some(6.0))
                        Text("7.0").tag(Double?.some(7.0))
                        Text("8.0").tag(Double?.some(8.0))
                        Text("9.0").tag(Double?.some(9.0))
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(UI.Spacing.s3)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    private func genreToggle(_ genre: Genre) -> some View {
        let isOn = query.genreIDs.contains(genre.id)
        return Button {
            if isOn {
                query.genreIDs.remove(genre.id)
            } else {
                query.genreIDs.insert(genre.id)
            }
        } label: {
            Text(genre.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? UI.Palette.accentText : UI.Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isOn ? UI.Palette.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: UI.Radius.chip, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: UI.Radius.chip, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : UI.Palette.border, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func yearPicker(title: String, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text(title).tag(Int?.none)
            ForEach(years, id: \.self) { year in
                Text("\(year)").tag(Int?.some(year))
            }
        }
        .labelsHidden()
        .frame(width: 84)
    }

    private func scheduleReload() {
        debouncer.schedule { [weak appEnv] in
            guard let appEnv else { return }
            let client = appEnv.client
            let query = self.query
            let mediaKind = self.mediaKind
            let newFeed = PaginatedFeed<MediaSummary> { page in
                let paged = try await client.discover(mediaKind: mediaKind, query: query, page: page)
                return (paged.items, paged.isLastPage)
            }
            self.feed = newFeed
            await newFeed.loadFirstPageIfNeeded()
        }
    }

    private func loadFeed() async {
        let client = appEnv.client
        let query = self.query
        let mediaKind = self.mediaKind
        let newFeed = PaginatedFeed<MediaSummary> { page in
            let paged = try await client.discover(mediaKind: mediaKind, query: query, page: page)
            return (paged.items, paged.isLastPage)
        }
        feed = newFeed
        await newFeed.loadFirstPageIfNeeded()
    }

    private func loadGenres() async {
        guard genres.isEmpty else { return }
        genres = (try? await appEnv.client.genreList(mediaKind: mediaKind)) ?? []
    }
}

/// 「来一部」：从当前已加载、已筛选的结果里随机打开一部。
///
/// 只从内存里的列表挑，不额外发请求；因此「按当前筛选条件随机」天然成立。
/// 列表加载完成前禁用。
struct SurpriseMeButton: View {
    let items: [MediaSummary]
    let open: (MediaSummary) -> Void

    @State private var lastPick: MediaSummary?

    var body: some View {
        Button {
            guard let pick = items.randomPick(excluding: lastPick) else { return }
            lastPick = pick
            open(pick)
        } label: {
            Label("来一部", systemImage: "dice")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(items.isEmpty)
        .help("从当前列表随机打开一部")
    }
}
