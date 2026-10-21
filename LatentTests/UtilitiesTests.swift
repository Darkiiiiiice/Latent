import Foundation
import Testing
@testable import Latent

/// 格式化（设计文档第 11 节）。
@Suite("格式化")
struct FormattersTests {

    @Test("时长：166 → 2 小时 46 分")
    func runtime() {
        #expect(Formatters.runtime(minutes: 166) == "2 小时 46 分")
        #expect(Formatters.runtime(minutes: 120) == "2 小时")
        #expect(Formatters.runtime(minutes: 46) == "46 分")
        #expect(Formatters.runtime(minutes: 0) == nil)
        #expect(Formatters.runtime(minutes: nil) == nil)
        #expect(Formatters.runtime(minutes: -5) == nil)
    }

    @Test("金钱：$190M / $714M / $1.5B")
    func money() {
        #expect(Formatters.money(190_000_000) == "$190M")
        #expect(Formatters.money(714_444_358) == "$714.4M")
        #expect(Formatters.money(1_500_000_000) == "$1.5B")
        #expect(Formatters.money(999_000) == "$999K")
        #expect(Formatters.money(0) == nil)
        #expect(Formatters.money(nil) == nil)
    }

    @Test("评分：一位小数；0 与 nil 返回 nil")
    func rating() {
        #expect(Formatters.rating(8.133) == "8.1")
        #expect(Formatters.rating(10.0) == "10.0")
        #expect(Formatters.rating(7.95) == "8.0")
        #expect(Formatters.rating(0) == nil)
        #expect(Formatters.rating(nil) == nil)
    }

    @Test("年份：从日期串解析，异常值回退")
    func year() {
        #expect(Formatters.year(from: "2024-02-27") == 2024)
        #expect(Formatters.year(from: "") == nil)
        #expect(Formatters.year(from: "abc") == nil)
        #expect(Formatters.year(from: "1700-01-01") == nil) // 早于 1800 视为异常
        #expect(Formatters.year(from: nil) == nil)
    }

    @Test("语言标签")
    func languageLabel() {
        #expect(Formatters.languageLabel("zh-CN") == "中文")
        #expect(Formatters.languageLabel("en-US") == "English")
    }

    @Test("相对时间：今天 / 昨天 / N 天前")
    func relativeTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC

        let today = calendar.date(byAdding: .hour, value: -2, to: now)!
        #expect(!Formatters.relativeTime(today, now: now, calendar: calendar).contains("天"))

        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        #expect(Formatters.relativeTime(threeDaysAgo, now: now, calendar: calendar) == "3 天前")

        let longAgo = calendar.date(byAdding: .day, value: -40, to: now)!
        #expect(Formatters.relativeTime(longAgo, now: now, calendar: calendar).contains("年"))
    }
}

/// 错误映射（设计文档第 11 节）。
@Suite("错误分类")
struct APIErrorTests {

    @Test("断言状态码分类")
    func classification() {
        // 通过 TMDBClient 的分类行为间接验证（见 TMDBClientIntegrationTests）之外，
        // 这里直接验证错误类型的可重试性判断。
        #expect(APIError.timedOut.isRetryable)
        #expect(APIError.offline.isRetryable)
        #expect(APIError.serverError(status: 503).isRetryable)
        #expect(APIError.serverError(status: 400).isRetryable == false)
        #expect(APIError.unauthorized.isRetryable == false)
        #expect(APIError.notFound.isRetryable == false)
        #expect(APIError.rateLimited(retryAfter: 5).isRetryable)
        #expect(APIError.decodingFailed("x").isRetryable == false)
    }

    @Test("错误文案面向用户且可操作")
    func descriptions() {
        #expect(APIError.unauthorized.errorDescription.contains("Token"))
        #expect(APIError.rateLimited(retryAfter: nil).errorDescription.contains("稍后"))
        #expect(APIError.rateLimited(retryAfter: 12).errorDescription.contains("12"))
        #expect(APIError.offline.errorDescription.contains("网络"))
        #expect(APIError.serverError(status: 500).errorDescription.contains("500"))
    }

    @Test("重试策略：429 只重试一次；5xx 指数退避最多 2 次")
    func retryPolicy() {
        #expect(RetryPolicy.delayAfter(error: .rateLimited(retryAfter: 7), retryAfterHeader: 7, attempt: 1) == 7)
        #expect(RetryPolicy.delayAfter(error: .rateLimited(retryAfter: 7), retryAfterHeader: 7, attempt: 2) == nil)

        #expect(RetryPolicy.delayAfter(error: .timedOut, retryAfterHeader: nil, attempt: 1) != nil)
        #expect(RetryPolicy.delayAfter(error: .timedOut, retryAfterHeader: nil, attempt: 2) != nil)
        #expect(RetryPolicy.delayAfter(error: .timedOut, retryAfterHeader: nil, attempt: 3) == nil)

        #expect(RetryPolicy.delayAfter(error: .notFound, retryAfterHeader: nil, attempt: 1) == nil)
        #expect(RetryPolicy.delayAfter(error: .unauthorized, retryAfterHeader: nil, attempt: 1) == nil)
    }

    @Test("URLSession 失败映射")
    func transportMapping() {
        #expect(APIError(transportError: URLError(.timedOut)) == .timedOut)
        #expect(APIError(transportError: URLError(.notConnectedToInternet)) == .offline)
        #expect(APIError(transportError: URLError(.networkConnectionLost)) == .offline)
    }
}

/// 分页状态机（设计文档第 11 节）。
@Suite("分页状态机")
@MainActor
struct PaginatedFeedTests {

    @Test("首屏 → 加载更多 → 末页")
    func paginationFlow() async {
        let feed = PaginatedFeed<MediaSummary> { page in
            let items = (0..<20).map { MediaSummary(id: (page - 1) * 20 + $0, mediaKind: .movie, title: "作品") }
            return (items, page >= 3)
        }

        await feed.loadFirstPageIfNeeded()
        #expect(feed.items.count == 20)
        #expect(feed.state == .loaded)

        await feed.loadMoreIfNeeded(currentItem: feed.items.last)
        #expect(feed.items.count == 40)

        await feed.loadMoreIfNeeded(currentItem: feed.items.last)
        #expect(feed.items.count == 60)
        #expect(feed.state == .end)

        // 末页后再调用不产生变化
        await feed.loadMoreIfNeeded(currentItem: feed.items.last)
        #expect(feed.items.count == 60)
    }

    @Test("合并去重：分页边界重复只保留一条")
    func dedupe() async {
        let feed = PaginatedFeed<MediaSummary> { page in
            // 两页都返回 id 19、20（边界重叠）
            let items = [MediaSummary(id: 19, mediaKind: .movie, title: "重叠"),
                         MediaSummary(id: 20, mediaKind: .movie, title: "重叠"),
                         MediaSummary(id: page * 10 + 1, mediaKind: .movie, title: "第 \(page) 页")]
            return (items, page >= 2)
        }

        await feed.loadFirstPageIfNeeded()
        await feed.loadMoreIfNeeded(currentItem: feed.items.last)
        #expect(feed.items.count == 4)
    }

    @Test("失败 → error 态，可重试成功")
    func errorThenRetry() async {
        let attempts = Counter()
        let feed = PaginatedFeed<MediaSummary> { _ in
            let count = await attempts.increment()
            if count == 1 {
                throw APIError.offline
            }
            return ([MediaSummary(id: 1, mediaKind: .movie, title: "成功")], true)
        }

        await feed.loadFirstPageIfNeeded()
        #expect(feed.state == .error(APIError.offline.errorDescription))
        #expect(feed.items.isEmpty)

        await feed.retry()
        #expect(feed.items.count == 1)
        #expect(feed.state == .end)
    }

    @Test("重新加载：清空后从头开始")
    func reload() async {
        let feed = PaginatedFeed<MediaSummary> { page in
            ([MediaSummary(id: page, mediaKind: .movie, title: "第 \(page) 页")], page >= 2)
        }
        await feed.loadFirstPageIfNeeded()
        await feed.loadMoreIfNeeded(currentItem: feed.items.last)
        #expect(feed.items.count == 2)

        await feed.reload()
        #expect(feed.items.count == 1)
        #expect(feed.items.first?.id == 1)
    }

    @Test("非末项不触发加载")
    func noPrematureLoad() async {
        var loadCount = 0
        let feed = PaginatedFeed<MediaSummary> { page in
            loadCount += 1
            return ((0..<20).map { MediaSummary(id: $0, mediaKind: .movie, title: "x") }, false)
        }
        await feed.loadFirstPageIfNeeded()
        await feed.loadMoreIfNeeded(currentItem: feed.items.first) // 不是最后一项
        #expect(loadCount == 1)
    }

    @Test("显式加载下一页：仅 loaded 态生效")
    func explicitNextPage() async {
        var loadCount = 0
        let feed = PaginatedFeed<MediaSummary> { page in
            loadCount += 1
            let items = (0..<20).map { MediaSummary(id: (page - 1) * 20 + $0, mediaKind: .movie, title: "作品") }
            return (items, page >= 2)
        }

        await feed.loadNextPageIfPossible() // idle：忽略
        #expect(loadCount == 0)

        await feed.loadFirstPageIfNeeded()
        await feed.loadNextPageIfPossible()
        #expect(loadCount == 2)
        #expect(feed.state == .end)

        await feed.loadNextPageIfPossible() // 末页：忽略
        #expect(loadCount == 2)
    }

    private actor Counter {
        private var value = 0
        func increment() -> Int {
            value += 1
            return value
        }
    }
}

/// 防抖（设计文档第 11 节：搜索防抖，窗口内只发最后一次请求）。
@Suite("防抖")
@MainActor
struct DebouncerTests {

    @Test("窗口内只执行最后一次")
    func lastWins() async throws {
        let debouncer = Debouncer(interval: .milliseconds(50))
        let recorder = Recorder()

        debouncer.schedule { await recorder.record("第一次") }
        try await Task.sleep(for: .milliseconds(10))
        debouncer.schedule { await recorder.record("第二次") }
        try await Task.sleep(for: .milliseconds(10))
        debouncer.schedule { await recorder.record("第三次") }

        try await Task.sleep(for: .milliseconds(200))
        let calls = await recorder.calls
        #expect(calls == ["第三次"])
    }

    @Test("间隔超过窗口后全部执行")
    func sequential() async throws {
        let debouncer = Debouncer(interval: .milliseconds(20))
        let recorder = Recorder()

        debouncer.schedule { await recorder.record("A") }
        try await Task.sleep(for: .milliseconds(80))
        debouncer.schedule { await recorder.record("B") }
        try await Task.sleep(for: .milliseconds(80))

        let calls = await recorder.calls
        #expect(calls == ["A", "B"])
    }

    @Test("取消后不执行")
    func cancel() async throws {
        let debouncer = Debouncer(interval: .milliseconds(50))
        let recorder = Recorder()

        debouncer.schedule { await recorder.record("不应执行") }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(150))

        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    private actor Recorder {
        private(set) var calls: [String] = []
        func record(_ value: String) {
            calls.append(value)
        }
    }
}

/// 应用设置（最近搜索上限）。
@Suite("AppSettings")
@MainActor
struct AppSettingsTests {

    @Test("最近搜索：去重、置顶、上限 10 条")
    func recentSearches() {
        let defaults = UserDefaults(suiteName: "latent-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        for index in 1...12 {
            settings.recordSearch("查询 \(index)")
        }
        #expect(settings.recentSearches.count == AppSettings.recentSearchesLimit)
        #expect(settings.recentSearches.first == "查询 12")

        settings.recordSearch("查询 5")
        #expect(settings.recentSearches.first == "查询 5")
        #expect(settings.recentSearches.filter { $0 == "查询 5" }.count == 1)

        settings.clearRecentSearches()
        #expect(settings.recentSearches.isEmpty)
    }

    @Test("默认语言 zh-CN，外观跟随系统")
    func defaults() {
        let defaults = UserDefaults(suiteName: "latent-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.language == "zh-CN")
        #expect(settings.appearance == .system)
        #expect(settings.proxy == ProxyConfiguration()) // 默认跟随系统；主机的默认值 127.0.0.1
    }

    @Test("代理：改动即持久化（下次启动仍生效）")
    func proxyPersistence() {
        let defaults = UserDefaults(suiteName: "latent-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.proxy = ProxyConfiguration(mode: .manual, kind: .socks5, host: "10.0.0.5", port: 1080)

        #expect(ProxyConfiguration.read(from: defaults).mode == .manual)
        #expect(ProxyConfiguration.read(from: defaults).port == 1080)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.proxy.kind == .socks5)
        #expect(reloaded.proxy.host == "10.0.0.5")
    }

    @Test("代理：首次启动从环境变量预填，已设置过则不再覆盖")
    func proxySeeding() {
        let defaults = UserDefaults(suiteName: "latent-tests-\(UUID().uuidString)")!
        let seeded = AppSettings(defaults: defaults, environment: ["https_proxy": "http://127.0.0.1:7890"])
        #expect(seeded.proxy.mode == .manual)
        #expect(seeded.proxy.port == 7890)

        seeded.proxy = ProxyConfiguration(mode: .system) // 用户手动改回跟随系统
        let reloaded = AppSettings(defaults: defaults, environment: ["https_proxy": "http://127.0.0.1:9999"])
        #expect(reloaded.proxy.mode == .system) // 不再被环境变量覆盖
    }

    @Test("发现页快捷入口：同名覆盖、上限 12 条、可删除并持久化")
    func discoverPresets() {
        let defaults = UserDefaults(suiteName: "latent-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        var query = DiscoverQuery()
        query.minRating = 7.0
        settings.saveDiscoverFilter(DiscoverPreset(name: "高分", mediaKind: .movie, query: query))
        #expect(settings.savedDiscoverFilters.map(\.name) == ["高分"])

        // 同名覆盖：不新增条目，条件被替换。
        query.minRating = 8.0
        settings.saveDiscoverFilter(DiscoverPreset(name: "高分", mediaKind: .movie, query: query))
        #expect(settings.savedDiscoverFilters.count == 1)
        #expect(settings.savedDiscoverFilters.first?.query.minRating == 8.0)

        for index in 1...14 {
            settings.saveDiscoverFilter(DiscoverPreset(name: "预设 \(index)", mediaKind: .tv, query: DiscoverQuery()))
        }
        #expect(settings.savedDiscoverFilters.count == AppSettings.discoverPresetsLimit)
        #expect(settings.savedDiscoverFilters.first?.name == "预设 14")

        // 重新读取：持久化生效。
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.savedDiscoverFilters == settings.savedDiscoverFilters)

        let removed = reloaded.savedDiscoverFilters[0]
        reloaded.removeDiscoverFilter(id: removed.id)
        #expect(!reloaded.savedDiscoverFilters.contains { $0.id == removed.id })
        #expect(AppSettings(defaults: defaults).savedDiscoverFilters.count == AppSettings.discoverPresetsLimit - 1)
    }
}

/// 「来一部」随机挑选。
@Suite("随机来一部")
struct RandomPickTests {

    private func item(_ id: Int, kind: MediaKind = .movie, title: String = "测试") -> MediaSummary {
        MediaSummary(id: id, mediaKind: kind, title: title)
    }

    @Test("空列表返回 nil")
    func emptyReturnsNil() {
        #expect([MediaSummary]().randomPick(excluding: nil) == nil)
    }

    @Test("只有一条时返回自身（即使它是上一部）")
    func singleReturnsSelf() {
        let only = item(1)
        #expect([only].randomPick(excluding: only) == only)
    }

    @Test("多条时避开上一部")
    func avoidsPrevious() {
        let first = item(1)
        let second = item(2)
        #expect([first, second].randomPick(excluding: first) == second)
        #expect([first, second].randomPick(excluding: second) == first)
    }

    @Test("同 id 不同类型不算同一部")
    func kindMatters() {
        let movie = item(603, kind: .movie)
        let show = item(603, kind: .tv)
        #expect([movie, show].randomPick(excluding: movie) == show)
    }
}

/// TMDB 外链（设计文档第 11 节）：右键菜单「复制链接 / 在 TMDB 打开」的地址来源。
@Suite("TMDB 外链")
struct TMDBLinksTests {

    @Test("网页链接按类型拼路径")
    func pageURL() {
        #expect(TMDBLinks.pageURL(mediaKind: .movie, tmdbID: 693_134)?.absoluteString
            == "https://www.themoviedb.org/movie/693134")
        #expect(TMDBLinks.pageURL(mediaKind: .tv, tmdbID: 1399)?.absoluteString
            == "https://www.themoviedb.org/tv/1399")
        #expect(TMDBLinks.pageURL(mediaKind: .person, tmdbID: 287)?.absoluteString
            == "https://www.themoviedb.org/person/287")
    }

    @Test("IMDb 外链：空 id 返回 nil")
    func imdbURL() {
        #expect(TMDBLinks.imdbURL(imdbID: "tt15239678")?.absoluteString
            == "https://www.imdb.com/title/tt15239678/")
        #expect(TMDBLinks.imdbURL(imdbID: nil) == nil)
        #expect(TMDBLinks.imdbURL(imdbID: "") == nil)
    }
}
