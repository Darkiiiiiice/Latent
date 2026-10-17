import SwiftUI

/// 两栏布局：侧边栏 + 内容区（设计文档第 8.3 节）。
///
/// 详情与人物页在内容列 Push 进入，返回路径最短。
struct MainSplitView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    @State private var scope: SidebarScope = .trending
    @State private var path = NavigationPath()
    @State private var lastDestination: DetailDestination?
    @State private var isSearchPresented = false
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
                SearchPanel(isPresented: $isSearchPresented)
                    .environment(appEnv)
                    .environment(settings)
                    .padding(.top, 6)
                    .padding(.trailing, UI.Spacing.s4)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.focusSearch)) { _ in
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
        case .favorites:
            LibraryView(kind: .favorites, gridMode: gridMode, open: open)
        case .watchlist:
            LibraryView(kind: .watchlist, gridMode: gridMode, open: open)
        case .history:
            HistoryView(open: open)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                isSearchPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                    Text("搜索电影、剧集、人物…")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                    Text("⌘F")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .foregroundStyle(UI.Palette.textSecondary)
                .padding(.horizontal, UI.Spacing.s2)
                .frame(width: UI.Sizes.searchFieldWidth, height: 24)
                .background(UI.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: UI.Radius.input, style: .continuous))
                .hairlineBorder(UI.Palette.border, radius: UI.Radius.input)
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

            Button {
                openSettings()
            } label: {
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
                }
                Section("我的") {
                    row(.favorites)
                    row(.watchlist)
                    row(.history)
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
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(pulsing ? 0.35 : 1)
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
            withAnimation(UI.Motion.statusPulse.repeatForever(autoreverses: true)) { pulsing = true }
        } else {
            pulsing = false
        }
    }
}
