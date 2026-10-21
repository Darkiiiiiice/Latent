import SwiftUI
import UniformTypeIdentifiers

/// 全局搜索面板（设计文档第 8.6 节）：
/// 输入 → 300ms 防抖 → `/search/multi`；结果按「电影 / 剧集 / 人物」分组；
/// 空查询显示最近搜索（可清空）。
///
/// v1.16 起支持「截图识别」：拖图片到面板、或点输入框右侧的取景框按钮选图，
/// 识别出的文字自动查 TMDB 并给出候选。
struct SearchPanel: View {
    @Binding var isPresented: Bool

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    @State private var feed: PaginatedFeed<SearchResult>?
    @State private var selectedIndex: Int = -1
    @State private var debouncer = Debouncer()
    @State private var recognition: RecognitionState = .idle
    @State private var isDropTargeted = false
    @State private var isFileImporterPresented = false
    @FocusState private var isFocused: Bool

    /// 截图识别状态（与输入框搜索互不影响，识别结果单独成组展示）。
    private enum RecognitionState: Equatable {
        case idle
        case working
        case candidates([OCRSearchMatcher.Candidate])
        case failed(String)

        var isWorking: Bool { self == .working }

        var failure: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    init(isPresented: Binding<Bool>, initialQuery: String = "", autoPickImage: Bool = false) {
        _isPresented = isPresented
        _query = State(initialValue: initialQuery)
        _isFileImporterPresented = State(initialValue: autoPickImage)
    }

    private var results: [SearchResult] { feed?.items ?? [] }
    private var isSearching: Bool { feed?.state.isLoadingAny ?? false }

    private var movies: [MediaSummary] {
        results.compactMap { if case .movie(let item) = $0 { return item } else { return nil } }
    }

    private var shows: [MediaSummary] {
        results.compactMap { if case .tv(let item) = $0 { return item } else { return nil } }
    }

    private var people: [PersonSummary] {
        results.compactMap { if case .person(let item) = $0 { return item } else { return nil } }
    }

    /// 本地片库匹配（v1.8）：只在拉丁字母查询时显示，避免中文查询与 TMDB 结果重复。
    private var localMatches: [LibrarySnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, PinyinSearch.isLatinQuery(trimmed) else { return [] }

        let favorites = appEnv.library.items(kind: .favorites, sortedBy: .addedAt)
        let watchlist = appEnv.library.items(kind: .watchlist, sortedBy: .addedAt)

        var seen: Set<String> = []
        var matches: [LibrarySnapshot] = []
        for item in favorites + watchlist {
            guard seen.insert(item.id).inserted else { continue }
            if PinyinSearch.matches(query: trimmed, title: item.title, originalTitle: item.originalTitle) {
                matches.append(item)
            }
        }
        return matches
    }

    var body: some View {
        let local = localMatches
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().overlay(UI.Palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                    recognitionHeader
                    recognitionGroup

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        recentSearches
                    } else {
                        localGroup(local)

                        if let feed {
                            if case .error(let message) = feed.state, feed.items.isEmpty {
                                ErrorBanner(message: message) { Task { await feed.retry() } }
                            } else if feed.items.isEmpty {
                                if feed.state.isInitialLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(maxWidth: .infinity)
                                        .padding(UI.Spacing.s6)
                                } else if local.isEmpty {
                                    EmptyState(message: "没有找到「\(query)」", actionTitle: "清空搜索") {
                                        query = ""
                                    }
                                } else {
                                    Text("TMDB 中没有更多结果")
                                        .font(.system(size: 11))
                                        .foregroundStyle(UI.Palette.textSecondary)
                                        .padding(.vertical, UI.Spacing.s2)
                                }
                            } else {
                                group(title: "电影", items: movies)
                                group(title: "剧集", items: shows)
                                personGroup
                                paginationFooter(feed)
                            }
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(UI.Spacing.s6)
                        }
                    }
                }
                .padding(UI.Spacing.s3)
            }
            .frame(maxHeight: 460)
        }
        .frame(width: 560)
        .background(UI.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
        .onAppear {
            isFocused = true
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch(query)
            }
        }
        .onExitCommand { isPresented = false }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            startRecognition(url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay { dropHighlight }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                startRecognition(url)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: UI.Spacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)

            TextField("搜索电影、剧集、人物…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { submitSearch() }
                .onChange(of: query) { _, newValue in
                    selectedIndex = -1
                    scheduleSearch(newValue)
                }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("清空（Esc）")
            }

            Divider().frame(height: 18)

            Button {
                isFileImporterPresented = true
            } label: {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(UI.Palette.accent)
            }
            .buttonStyle(.plain)
            .help("从图片识别片名（⌘⇧O），也可以把图片拖进面板")
            .accessibilityLabel("从图片识别")

            Text("⌘F")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(UI.Palette.textSecondary)
        }
        .padding(.horizontal, UI.Spacing.s3)
        .frame(height: 40)
    }

    @ViewBuilder
    private var recentSearches: some View {
        if settings.recentSearches.isEmpty {
            Text("输入关键词开始搜索；支持中文、英文标题与片库拼音 / 首字母。")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
                .padding(.vertical, UI.Spacing.s3)
        } else {
            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(0.4)
                        .foregroundStyle(UI.Palette.textSecondary)
                    Spacer()
                    Button("清空") {
                        settings.clearRecentSearches()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.accent)
                }
                ForEach(settings.recentSearches, id: \.self) { item in
                    Button {
                        query = item
                        scheduleSearch(item)
                    } label: {
                        HStack(spacing: UI.Spacing.s2) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundStyle(UI.Palette.textSecondary)
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(UI.Palette.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 片库组：最多 6 部，紧凑行；不依赖 TMDB 请求，断网也可打开。
    @ViewBuilder
    private func localGroup(_ matches: [LibrarySnapshot]) -> some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: UI.Spacing.s2) {
                    Text("片库")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(0.4)
                        .foregroundStyle(UI.Palette.textSecondary)
                    Text("\(matches.count) 部")
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                    Spacer(minLength: 0)
                }

                ForEach(Array(matches.prefix(6))) { item in
                    LocalLibraryRow(item: item) {
                        open(item.asSummary)
                    }
                }

                if matches.count > 6 {
                    Text("还有 \(matches.count - 6) 部，可在收藏 / 观看清单中筛选")
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .padding(.leading, UI.Spacing.s2)
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func group(title: String, items: [MediaSummary]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(UI.Palette.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: UI.Spacing.s2)],
                    alignment: .leading,
                    spacing: UI.Spacing.s2
                ) {
                    ForEach(items) { item in
                        Button {
                            open(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                PosterImage(path: item.posterPath, displayWidth: 96)
                                    .frame(width: 96, height: 144)
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(UI.Palette.textPrimary)
                                    .lineLimit(1)
                                if let year = item.year {
                                    NumericText(text: "\(year)", size: 10)
                                }
                            }
                            .frame(width: 96, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var personGroup: some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("人物")
                    .font(.system(size: 11, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(UI.Palette.textSecondary)

                ForEach(people) { person in
                    PersonRow(
                        id: person.id,
                        name: person.name,
                        subtitle: person.knownForDepartment,
                        profilePath: person.profilePath
                    ) {
                        open(person)
                    }
                }
            }
        }
    }

    // MARK: - 截图识别（v1.16）

    /// 识别进行中 / 失败提示；两者互斥，且都不与候选列表同时出现。
    @ViewBuilder
    private var recognitionHeader: some View {
        if recognition.isWorking {
            HStack(spacing: UI.Spacing.s2) {
                ProgressView().controlSize(.small)
                Text("正在识别图片中的文字…")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, UI.Spacing.s2)
        } else if let message = recognition.failure {
            HStack(spacing: UI.Spacing.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.warning)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                Spacer(minLength: 0)
                Button("知道了") { recognition = .idle }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.accent)
            }
            .padding(.horizontal, UI.Spacing.s3)
            .padding(.vertical, UI.Spacing.s2)
            .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        }
    }

    /// 候选列表：识别出的文字查到多个相近作品时列出，由用户挑。
    @ViewBuilder
    private var recognitionGroup: some View {
        if case .candidates(let list) = recognition {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: UI.Spacing.s2) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.accent)
                    Text("识别结果")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(0.4)
                        .foregroundStyle(UI.Palette.textSecondary)
                    Text("\(list.count) 条")
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                    Spacer(minLength: 0)
                    Button("清除") { recognition = .idle }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.accent)
                }

                ForEach(list) { candidate in
                    OCRResultRow(candidate: candidate) { open(candidate.result) }
                }
            }
        }
    }

    /// 拖拽悬停时的高亮提示（设计文档第 8 节：强调色 + 无弹簧动效）。
    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                .fill(UI.Palette.accent.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                        .strokeBorder(
                            UI.Palette.accent,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }
                .overlay {
                    VStack(spacing: UI.Spacing.s2) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 22))
                        Text("松开，识别图片里的片名")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(UI.Palette.accent)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// 识别图片 → 逐行查 TMDB → 明显胜出直接打开，否则列候选。
    private func startRecognition(_ url: URL) {
        withAnimation(UI.Motion.imageFade) { recognition = .working }

        Task { @MainActor in
            do {
                let lines = try await ImageTextRecognizer.lines(from: url)
                let outcome = await OCRSearchMatcher.match(lines: lines, client: appEnv.client)
                apply(outcome)
            } catch {
                recognition = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ outcome: OCRSearchMatcher.Outcome) {
        switch outcome {
        case .empty:
            recognition = .failed("没有从这张图片里认出可搜索的文字")
        case .matched(let candidate):
            recognition = .idle
            open(candidate.result)
        case .candidates(let list):
            withAnimation(UI.Motion.imageFade) { recognition = .candidates(list) }
        }
    }

    private func scheduleSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncer.cancel()
            feed = nil
            return
        }
        debouncer.schedule { [weak appEnv] in
            guard let appEnv else { return }
            let client = appEnv.client
            let newFeed = PaginatedFeed<SearchResult> { page in
                let paged = try await client.searchMulti(query: trimmed, page: page)
                return (paged.items, paged.isLastPage)
            }
            self.feed = newFeed
            await newFeed.loadFirstPageIfNeeded()
        }
    }

    /// 搜索分页页脚：加载更多 / 加载中 / 失败重试 / 到底提示。
    @ViewBuilder
    private func paginationFooter(_ feed: PaginatedFeed<SearchResult>) -> some View {
        switch feed.state {
        case .loadingMore:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, UI.Spacing.s2)
        case .loaded:
            Button("加载更多") {
                Task { await feed.loadNextPageIfPossible() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.top, UI.Spacing.s2)
        case .error(let message):
            ErrorBanner(message: message) { Task { await feed.retry() } }
                .padding(.top, UI.Spacing.s2)
        case .end:
            Text("已经到底了")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, UI.Spacing.s2)
        case .idle, .loadingFirst:
            EmptyView()
        }
    }

    private func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.recordSearch(trimmed)
        if selectedIndex >= 0, selectedIndex < orderedResults.count {
            let result = orderedResults[selectedIndex]
            switch result {
            case .movie(let item), .tv(let item): open(item)
            case .person(let person): open(person)
            }
        }
    }

    private var orderedResults: [SearchResult] {
        results.filter { result in
            switch result {
            case .movie, .tv: return true
            case .person: return true
            }
        }
    }

    private func open(_ summary: MediaSummary) {
        settings.recordSearch(query)
        isPresented = false
        if let destination = DetailDestination.from(summary) {
            NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
        }
    }

    private func open(_ person: PersonSummary) {
        settings.recordSearch(query)
        isPresented = false
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: DetailDestination.person(id: person.id))
    }

    /// 识别候选是多类型的，统一入口分发（空 query 不会写进最近搜索）。
    private func open(_ result: SearchResult) {
        switch result {
        case .movie(let item), .tv(let item): open(item)
        case .person(let person): open(person)
        }
    }
}

/// 全局搜索里的片库紧凑行（v1.8）。
private struct LocalLibraryRow: View {
    let item: LibrarySnapshot
    let onOpen: () -> Void

    @State private var isHovering = false

    private var subtitle: String {
        var parts = [item.mediaKind.label]
        if let year = item.year { parts.append("\(year)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: UI.Spacing.s3) {
                PosterImage(path: item.posterPath, displayWidth: 32, cornerRadius: 4)
                    .frame(width: 32, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            .padding(.horizontal, UI.Spacing.s2)
            .padding(.vertical, 5)
            .background(
                isHovering ? UI.Palette.surfaceElevated : .clear,
                in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(UI.Motion.hover) { isHovering = hovering }
        }
        .accessibilityLabel(item.year.map { "\(item.title)，\($0) 年" } ?? item.title)
    }
}

/// 截图识别的候选行（v1.16）：海报缩略 + 标题 + 类型 · 年份 + 命中它的那行文字。
private struct OCRResultRow: View {
    let candidate: OCRSearchMatcher.Candidate
    let onOpen: () -> Void

    @State private var isHovering = false

    private var posterPath: String? {
        switch candidate.result {
        case .movie(let item), .tv(let item): return item.posterPath
        case .person(let person): return person.profilePath
        }
    }

    private var title: String {
        switch candidate.result {
        case .movie(let item), .tv(let item): return item.title
        case .person(let person): return person.name
        }
    }

    private var subtitle: String {
        switch candidate.result {
        case .movie(let item), .tv(let item):
            var parts = [item.mediaKind.label]
            if let year = item.year { parts.append("\(year)") }
            return parts.joined(separator: " · ")
        case .person(let person):
            return person.knownForDepartment ?? "人物"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: UI.Spacing.s3) {
                PosterImage(path: posterPath, displayWidth: 32, cornerRadius: 4)
                    .frame(width: 32, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("「\(candidate.matchedQuery)」")
                    .font(.system(size: 10))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            .padding(.horizontal, UI.Spacing.s2)
            .padding(.vertical, 5)
            .background(
                isHovering ? UI.Palette.surfaceElevated : .clear,
                in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(UI.Motion.hover) { isHovering = hovering }
        }
        .accessibilityLabel("\(title)，\(subtitle)")
    }
}
