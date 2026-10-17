import SwiftUI

/// 全局搜索面板（设计文档第 8.6 节）：
/// 输入 → 300ms 防抖 → `/search/multi`；结果按「电影 / 剧集 / 人物」分组；
/// 空查询显示最近搜索（可清空）。
struct SearchPanel: View {
    @Binding var isPresented: Bool

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedIndex: Int = -1
    @State private var debouncer = Debouncer()
    @FocusState private var isFocused: Bool

    private var movies: [MediaSummary] {
        results.compactMap { if case .movie(let item) = $0 { return item } else { return nil } }
    }

    private var shows: [MediaSummary] {
        results.compactMap { if case .tv(let item) = $0 { return item } else { return nil } }
    }

    private var people: [PersonSummary] {
        results.compactMap { if case .person(let item) = $0 { return item } else { return nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().overlay(UI.Palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        recentSearches
                    } else if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    } else if results.isEmpty && !isSearching {
                        EmptyState(message: "没有找到「\(query)」", actionTitle: "清空搜索") {
                            query = ""
                        }
                    } else {
                        group(title: "电影", items: movies)
                        group(title: "剧集", items: shows)
                        personGroup
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
        .onAppear { isFocused = true }
        .onExitCommand { isPresented = false }
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
            Text("输入关键词开始搜索；支持中文与英文标题。")
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

    private func scheduleSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncer.cancel()
            results = []
            isSearching = false
            errorMessage = nil
            return
        }
        debouncer.schedule { [weak appEnv] in
            guard let appEnv else { return }
            await performSearch(trimmed, client: appEnv.client)
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

    private func performSearch(_ text: String, client: any TMDBClientProtocol) async {
        isSearching = true
        errorMessage = nil
        do {
            let page = try await client.searchMulti(query: text, page: 1)
            results = page.items
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = APIError.offline.errorDescription
        }
        isSearching = false
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
}
