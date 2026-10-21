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

/// 发现页（P3）：类型 / 年份 / 评分区间 / 观看平台 / 排序筛选，变化防抖 300ms 刷新。
struct DiscoverView: View {
    let gridMode: Bool
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings
    @State private var mediaKind: MediaKind = .movie
    @State private var query = DiscoverQuery()
    @State private var genres: [Genre] = []
    @State private var providers: [WatchProvider] = []
    @State private var feed: PaginatedFeed<MediaSummary>?
    @State private var debouncer = Debouncer()
    @State private var isNamingPreset = false
    @State private var presetName = ""

    private let years: [Int] = Array((1950...Calendar.current.component(.year, from: Date())).reversed())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                header

                filterBar

                if !settings.savedDiscoverFilters.isEmpty {
                    presetBar
                }

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
        .alert("保存当前筛选", isPresented: $isNamingPreset) {
            TextField("快捷入口名称", text: $presetName)
            Button("取消", role: .cancel) {}
            Button("保存") { savePreset() }
        } message: {
            Text("之后可在发现页一键恢复这套条件。")
        }
        .task {
            await loadGenres()
            await loadProviders()
            await loadFeed()
        }
        .onChange(of: query) { oldValue, newValue in
            // 地区只在选择了平台时才影响请求（TMDB 要求两者同时出现），单独改地区不重发。
            guard effective(oldValue) != effective(newValue) else { return }
            scheduleReload()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            Task { await feed?.reload() }
        }
    }

    private var header: some View {
        HStack(spacing: UI.Spacing.s3) {
            Text("发现")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)

            Spacer(minLength: 0)

            Button {
                presetName = query.summaryLabel(genreNames: genreNamesByID, providerNames: providerNamesByID)
                isNamingPreset = true
            } label: {
                Label("保存筛选", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(query.isEmpty && query.sortBy == .popularity)
            .help("把这套筛选条件存成快捷入口")

            SurpriseMeButton(items: feed?.items ?? [], open: open)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            HStack(spacing: UI.Spacing.s3) {
                Picker("类型", selection: mediaKindSelection) {
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
                    let region = query.region
                    query = DiscoverQuery()
                    query.region = region
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(query.isEmpty && query.sortBy == .popularity)
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

                // 评分区间
                HStack(spacing: UI.Spacing.s2) {
                    Text("评分")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(UI.Palette.textSecondary)
                    ratingPicker(title: "最低", selection: $query.minRating)
                    Text("–").foregroundStyle(UI.Palette.textSecondary)
                    ratingPicker(title: "最高", selection: $query.maxRating)
                }

                Spacer(minLength: 0)

                regionMenu
            }

            // 流媒体平台（跟随地区与类型变化）
            if !providers.isEmpty {
                HStack(spacing: UI.Spacing.s2) {
                    Text("平台")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(UI.Palette.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(providers) { provider in
                                providerToggle(provider)
                            }
                        }
                    }

                    if !query.providerIDs.isEmpty {
                        Button("清除") { query.providerIDs.removeAll() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.accent)
                    }
                }

                Text("平台数据由 JustWatch 提供")
                    .font(.system(size: 10))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
        .padding(UI.Spacing.s3)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    /// 已保存的快捷入口：点名称套用，点 × 删除。
    private var presetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(settings.savedDiscoverFilters) { preset in
                    HStack(spacing: 2) {
                        Button {
                            apply(preset)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: preset.mediaKind == .tv ? "tv" : "film")
                                    .font(.system(size: 9))
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(UI.Palette.textPrimary)
                            .padding(.leading, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(preset.query.summaryLabel(genreNames: genreNamesByID, providerNames: providerNamesByID))

                        Button {
                            settings.removeDiscoverFilter(id: preset.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(UI.Palette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("删除快捷入口")
                    }
                    .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.chip, style: .continuous))
                    .hairlineBorder(UI.Palette.border, radius: UI.Radius.chip)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var regionMenu: some View {
        Menu {
            ForEach(DiscoverQuery.regions, id: \.self) { code in
                Button {
                    selectRegion(code)
                } label: {
                    if code == query.region {
                        Label(CountryDirectory.name(for: code), systemImage: "checkmark")
                    } else {
                        Text(CountryDirectory.name(for: code))
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text("地区 \(CountryDirectory.name(for: query.region))")
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11))
            .foregroundStyle(UI.Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("平台可用性按地区划分")
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

    private func providerToggle(_ provider: WatchProvider) -> some View {
        let isOn = query.providerIDs.contains(provider.id)
        return Button {
            if isOn {
                query.providerIDs.remove(provider.id)
            } else {
                query.providerIDs.insert(provider.id)
            }
        } label: {
            HStack(spacing: 5) {
                if let logoPath = provider.logoPath {
                    // 平台 Logo 多为透明底，统一白色底托（与详情页同一处理）。
                    PosterImage(path: logoPath, displayWidth: 12, cornerRadius: 2, contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .padding(1)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(provider.providerName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn ? UI.Palette.accentText : UI.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
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
        .help(provider.providerName)
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

    private func ratingPicker(title: String, selection: Binding<Double?>) -> some View {
        Picker(title, selection: selection) {
            Text("不限").tag(Double?.none)
            Text("6.0").tag(Double?.some(6.0))
            Text("7.0").tag(Double?.some(7.0))
            Text("8.0").tag(Double?.some(8.0))
            Text("9.0").tag(Double?.some(9.0))
        }
        .labelsHidden()
        .frame(width: 84)
        .help("\(title)评分")
    }

    private var mediaKindSelection: Binding<MediaKind> {
        Binding(
            get: { mediaKind },
            set: { newValue in
                guard newValue != mediaKind else { return }
                mediaKind = newValue
                // 电影 / 剧集的类型 ID 与平台清单属于两套体系，切换时清空并重新拉取。
                query.genreIDs.removeAll()
                query.providerIDs.removeAll()
                genres = []
                providers = []
                Task { await loadGenres() }
                Task { await loadProviders() }
                scheduleReload()
            }
        )
    }

    private var genreNamesByID: [Int: String] {
        Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0.name) })
    }

    private var providerNamesByID: [Int: String] {
        Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.providerName) })
    }

    /// 忽略「没选平台时的地区」——它不参与请求，也不应触发重新加载。
    private func effective(_ query: DiscoverQuery) -> DiscoverQuery {
        var copy = query
        if copy.providerIDs.isEmpty { copy.region = "" }
        return copy
    }

    private func selectRegion(_ code: String) {
        guard code != query.region else { return }
        query.region = code
        // 平台可用性按地区划分，已选的平台在新区不一定存在。
        query.providerIDs.removeAll()
        Task { await loadProviders() }
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        settings.saveDiscoverFilter(DiscoverPreset(name: name, mediaKind: mediaKind, query: query))
        ToastCenter.shared.show("已保存快捷入口")
    }

    private func apply(_ preset: DiscoverPreset) {
        let kindChanged = preset.mediaKind != mediaKind
        mediaKind = preset.mediaKind
        query = preset.query
        if kindChanged {
            genres = []
            Task { await loadGenres() }
        }
        Task { await loadProviders() }
        scheduleReload()
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

    private func loadProviders() async {
        let region = query.region
        let kind = mediaKind
        let list = (try? await appEnv.client.watchProviders(mediaKind: kind, region: region)) ?? []
        // 期间地区或类型被改过就丢弃这次结果，避免旧清单覆盖新地区。
        guard region == query.region, kind == mediaKind else { return }
        providers = list
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
