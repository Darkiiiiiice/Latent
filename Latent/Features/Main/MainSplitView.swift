import SwiftUI

/// 两栏布局：侧边栏 + 内容区（设计文档第 8.3 节）。
///
/// 详情与人物页在内容列 Push 进入，返回路径最短。
struct MainSplitView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings

    @State private var scope: SidebarScope = .trending
    @State private var path = NavigationPath()
    @State private var lastDestination: DetailDestination?
    @State private var isSearchPresented = false
    @State private var searchSeed = ""
    @State private var searchGeneration = 0
    @State private var searchWantsImage = false
    @State private var searchFocus = false
    @AppStorage("view.gridMode") private var gridMode = true

    var body: some View {
        NavigationSplitView {
            SidebarView(scope: $scope, onSelect: selectScope)
                .navigationSplitViewColumnWidth(UI.Sizes.sidebarWidth)
        } detail: {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: DetailDestination.self) { destination in
                        DetailRouteView(destination: destination)
                    }
            }
            .toolbar { toolbarContent }
        }
        .background(UI.Palette.bg)
        .overlay(alignment: .topTrailing) {
            if isSearchPresented {
                SearchPanel(isPresented: $isSearchPresented, initialQuery: searchSeed, autoPickImage: searchWantsImage)
                    .id(searchGeneration)
                    .environment(appEnv)
                    .environment(settings)
                    .padding(.top, 6)
                    .padding(.trailing, UI.Spacing.s4)
                    .transition(.opacity)
            }
        }
        .onAppear {
            handleIntentRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: IntentRouter.didRequest)) { _ in
            handleIntentRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.focusSearch)) { _ in
            if !isSearchPresented {
                searchSeed = ""
                searchWantsImage = false
                searchGeneration += 1
            }
            isSearchPresented = true
        }
        // 文件菜单「从图片识别…」：打开搜索面板并直接弹出图片选择器。
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.recognizeImage)) { _ in
            searchSeed = ""
            searchWantsImage = true
            searchGeneration += 1
            isSearchPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.back)) { _ in
            if !path.isEmpty {
                path.removeLast()
                lastDestination = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.pushDetail)) { note in
            guard let destination = note.object as? DetailDestination else { return }
            // 避免重复 Push 同一目的地（NavigationStack 会告警）
            if let lastDestination, lastDestination == destination { return }
            lastDestination = destination
            path.append(destination)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .trending:
            TrendingView(gridMode: gridMode, open: open)
        case .discover:
            DiscoverView(gridMode: gridMode, open: open)
        case .calendar:
            CalendarView(open: open)
        case .favorites:
            LibraryView(kind: .favorites, gridMode: gridMode, open: open)
        case .watchlist:
            LibraryView(kind: .watchlist, gridMode: gridMode, open: open)
        case .history:
            HistoryView(open: open)
        case .stats:
            StatisticsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                isSearchPresented.toggle()
            } label: {
                // 注意：工具栏项的 label 里不能放 `Spacer`。macOS 27 会把带弹性宽度的
                // 工具栏项整个丢弃（搜索框因此不可见，2026-10-19 踩坑），这里全部用定宽布局。
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                    Text("搜索电影、剧集、人物…")
                        .font(.system(size: 12))
                }
                .frame(width: UI.Sizes.searchFieldWidth - UI.Spacing.s2 * 2, height: 24, alignment: .leading)
                .foregroundStyle(UI.Palette.textSecondary)
                .padding(.horizontal, UI.Spacing.s2)
                .frame(width: UI.Sizes.searchFieldWidth, height: 24)
                .background(UI.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: UI.Radius.input, style: .continuous))
                .hairlineBorder(UI.Palette.border, radius: UI.Radius.input)
                .overlay(alignment: .trailing) {
                    Text("⌘F")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .padding(.trailing, UI.Spacing.s2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("搜索（⌘F）")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("视图", selection: $gridMode) {
                Image(systemName: "square.grid.2x2").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 74)
            .help("网格 / 列表")

            // SettingsLink 是打开设置场景的正确入口：应用未激活时会先激活应用，
            // 避免窗口被创建后停在屏幕外（onscreen=false）。
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("设置（⌘,）")
            .accessibilityLabel("设置")
        }
    }

    private func selectScope(_ newScope: SidebarScope) {
        scope = newScope
        path = NavigationPath()
        lastDestination = nil
        isSearchPresented = false
    }

    private func open(_ summary: MediaSummary) {
        guard let destination = DetailDestination.from(summary) else { return }
        lastDestination = destination
        path.append(destination)
    }

    /// 消费 App Intents / Spotlight 导航请求（冷启动由 onAppear 消费）。
    private func handleIntentRoute() {
        guard let destination = IntentRouter.shared.consume() else { return }
        Log.intents.info("MainSplitView 消费路由：\(String(describing: destination), privacy: .public)")
        switch destination {
        case .detail(let detail):
            if lastDestination != detail {
                lastDestination = detail
                path.append(detail)
            }
        case .search(let query):
            searchSeed = query
            searchGeneration += 1
            isSearchPresented = true
        }
    }
}

/// 侧边栏：探索 / 我的 + 底部连接状态。
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Binding var scope: SidebarScope
    let onSelect: (SidebarScope) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { scope },
                set: { newValue in
                    guard let newValue else { return }
                    onSelect(newValue)
                }
            )) {
                Section("探索") {
                    row(.trending)
                    row(.discover)
                    row(.calendar)
                }
                Section("我的") {
                    row(.favorites)
                    row(.watchlist)
                    row(.history)
                    row(.stats)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider().overlay(UI.Palette.border)
            ConnectionStatusView()
        }
        .background(UI.Palette.surface)
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.selectScope)) { note in
            if let raw = note.object as? String, let target = SidebarScope(rawValue: raw) {
                onSelect(target)
            }
        }
    }

    private func row(_ item: SidebarScope) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                if let count = badge(for: item), count > 0 {
                    NumericText(text: "\(count)", size: 11, color: UI.Palette.textSecondary)
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }

    private func badge(for item: SidebarScope) -> Int? {
        switch item {
        case .favorites: return appEnv.library.favoriteCount
        case .watchlist: return appEnv.library.watchlistCount
        case .history: return appEnv.history.count
        default: return nil
        }
    }
}

/// 侧边栏底部连接状态：`● TMDB 已连接 · zh-CN`；有网络请求时轻微呼吸。
struct ConnectionStatusView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var state: AppEnvironment.ConnectionState { appEnv.connectionState }

    private var color: Color {
        switch state {
        case .unknown: return UI.Palette.textSecondary
        case .connected: return UI.Palette.success
        case .failed: return UI.Palette.error
        }
    }

    private var label: String {
        switch state {
        case .unknown: return "TMDB 检查中"
        case .connected: return "TMDB 已连接"
        case .failed: return "TMDB 未连接"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            BreathingFill(
                color: color,
                cornerRadius: 3,
                lowOpacity: 0.35,
                highOpacity: 1,
                duration: UI.Motion.Breath.statusDot,
                animated: pulsing && !reduceMotion,
                colorScheme: colorScheme
            )
            .frame(width: 6, height: 6)
            Text("\(label) · \(settings.language)")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UI.Spacing.s3)
        .padding(.vertical, UI.Spacing.s3)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，元数据语言 \(settings.language)")
        .onAppear { updatePulse() }
        .onChange(of: appEnv.connectionState) { _, _ in updatePulse() }
    }

    private var helpText: String {
        switch state {
        case .connected: return "TMDB API 连接正常"
        case .unknown: return "正在验证 TMDB 连接"
        case .failed(let message): return message
        }
    }

    private func updatePulse() {
        guard !reduceMotion else { return }
        if case .unknown = state {
            pulsing = true
        } else {
            pulsing = false
        }
    }
}
