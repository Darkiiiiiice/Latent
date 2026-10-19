import Foundation
import SwiftData

/// 在 App 与 App Intents 之间共享同一个 SwiftData 容器。
///
/// App Intents 运行在主应用进程内；`LatentApp.init` 把已经打开的容器放进来，
/// 避免在 Shortcuts / Spotlight 调用时再打开第二个容器。若进程尚未完成初始化
/// （例如系统在后台唤醒执行 Intent），则按同一路径懒创建。
final class IntentContainerBox: @unchecked Sendable {
    static let shared = IntentContainerBox()

    private let lock = NSLock()
    private var container: ModelContainer?

    func set(_ container: ModelContainer) {
        lock.lock()
        self.container = container
        lock.unlock()
    }

    func get() -> ModelContainer? {
        lock.lock()
        defer { lock.unlock() }
        return container
    }
}

/// App Intents / Spotlight 的本地数据与 TMDB 访问入口（主 actor）。
///
/// 只返回 `Sendable` 值类型；不把 SwiftData 模型或 ModelContext 带出隔离域。
@MainActor
final class IntentDataStore {
    static let shared = IntentDataStore()

    private var fallbackContainer: ModelContainer?
    private var client: TMDBClient?
    private var clientLanguage: String?

    // MARK: - 配置

    private func resolvedContainer() -> ModelContainer {
        if let existing = IntentContainerBox.shared.get() {
            return existing
        }
        if let fallbackContainer {
            return fallbackContainer
        }
        let created = LibraryContainerFactory.make()
        fallbackContainer = created
        IntentContainerBox.shared.set(created)
        return created
    }

    private func resolvedClient() -> TMDBClient {
        // 与主应用一致：用户语言存 UserDefaults，Token 由 TMDBClient 从 Keychain 读取。
        // 每次取用时校验语言，设置变更后无需重启进程也能生效。
        let language = UserDefaults.standard.string(forKey: "settings.language") ?? "zh-CN"
        if let client, clientLanguage == language {
            return client
        }
        let created = TMDBClient(languageProvider: { @Sendable in language })
        client = created
        clientLanguage = language
        return created
    }

    // MARK: - 库

    /// 收藏 + 清单去重后的实体（收藏优先，按加入时间倒序）。
    func libraryEntities() -> [TitleEntity] {
        let (favorites, watchlist) = librarySnapshots()
        return TitleEntity.merged(favorites: favorites, watchlist: watchlist)
    }

    /// 收藏 / 清单分别成组；同一作品同时存在时只进收藏组。
    func libraryBuckets() -> (favorites: [TitleEntity], watchlist: [TitleEntity]) {
        let (favorites, watchlist) = librarySnapshots()
        return TitleEntity.buckets(favorites: favorites, watchlist: watchlist)
    }

    func libraryEntities(matching query: String) -> [TitleEntity] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Array(libraryEntities().prefix(20)) }
        return Array(
            libraryEntities()
                .filter {
                    $0.title.localizedCaseInsensitiveContains(needle)
                        || ($0.originalTitle?.localizedCaseInsensitiveContains(needle) ?? false)
                        || String($0.tmdbID) == needle
                }
                .prefix(20)
        )
    }

    /// 按 "movie-123" / "tv-456" 解析；先查本地库，缺失时再取 TMDB 详情。
    func entities(for identifiers: [TitleEntity.ID]) async -> [TitleEntity] {
        let local = Dictionary(uniqueKeysWithValues: libraryEntities().map { ($0.id, $0) })
        var result: [TitleEntity] = []
        for identifier in identifiers {
            if let item = local[identifier] {
                result.append(item)
                continue
            }
            guard let parsed = TitleEntity.parse(identifier: identifier) else { continue }
            if let summary = await remoteSummary(id: parsed.tmdbID, kind: parsed.mediaKind) {
                result.append(TitleEntity(summary: summary))
            }
        }
        return result
    }

    // MARK: - 搜索

    /// 搜索电影 / 剧集；人物不进入 `TitleEntity`。
    func search(query: String, mediaType: MediaTypeAppEnum?) async throws -> [TitleEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paged = try await resolvedClient().searchMulti(query: trimmed, page: 1)
        let entities = paged.items.compactMap { result -> TitleEntity? in
            switch result {
            case .movie(let summary):
                guard mediaType == nil || mediaType == .movie else { return nil }
                return TitleEntity(summary: summary)
            case .tv(let summary):
                guard mediaType == nil || mediaType == .tv else { return nil }
                return TitleEntity(summary: summary)
            case .person:
                return nil
            }
        }
        return Array(entities.prefix(20))
    }

    // MARK: - 内部

    private func librarySnapshots() -> (favorites: [LibrarySnapshot], watchlist: [LibrarySnapshot]) {
        let context = ModelContext(resolvedContainer())
        let favorites = ((try? context.fetch(FetchDescriptor<FavoriteItem>())) ?? [])
            .map(snapshot(for:))
        let watchlist = ((try? context.fetch(FetchDescriptor<WatchlistItem>())) ?? [])
            .map(snapshot(for:))
        return (favorites, watchlist)
    }

    private func snapshot(for item: FavoriteItem) -> LibrarySnapshot {
        LibrarySnapshot(
            mediaKind: item.mediaKind,
            tmdbID: item.tmdbID,
            title: item.title,
            originalTitle: item.originalTitle,
            year: item.year,
            posterPath: item.posterPath,
            voteAverage: item.voteAverage,
            addedAt: item.addedAt
        )
    }

    private func snapshot(for item: WatchlistItem) -> LibrarySnapshot {
        LibrarySnapshot(
            mediaKind: item.mediaKind,
            tmdbID: item.tmdbID,
            title: item.title,
            originalTitle: item.originalTitle,
            year: item.year,
            posterPath: item.posterPath,
            voteAverage: item.voteAverage,
            addedAt: item.addedAt
        )
    }

    private func remoteSummary(id: Int, kind: MediaKind) async -> MediaSummary? {
        let client = resolvedClient()
        switch kind {
        case .movie:
            guard let detail = try? await client.movieDetail(id: id) else { return nil }
            return MediaSummary(id: id, mediaKind: .movie, title: detail.title).resolved(from: detail)
        case .tv:
            guard let detail = try? await client.tvDetail(id: id) else { return nil }
            return MediaSummary(id: id, mediaKind: .tv, title: detail.title).resolved(from: detail)
        default:
            return nil
        }
    }
}

/// `IntentDataStore.search` 的参数类型；放在独立文件是为了让 Core 数据层不依赖 AppIntents。
enum MediaTypeAppEnum: String, CaseIterable, Sendable {
    case movie
    case tv

    var mediaKind: MediaKind {
        switch self {
        case .movie: return .movie
        case .tv: return .tv
        }
    }
}
