import AppIntents
import Foundation

extension MediaTypeAppEnum: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "作品类型"
    static let caseDisplayRepresentations: [MediaTypeAppEnum: DisplayRepresentation] = [
        .movie: "电影",
        .tv: "剧集"
    ]
}

/// Intents 的统一错误（不暴露内部细节）。
enum LatentIntentError: LocalizedError {
    case invalidTMDBID

    var errorDescription: String? {
        switch self {
        case .invalidTMDBID: return "TMDB ID 必须大于 0。"
        }
    }
}

/// 在 TMDB 搜索电影 / 剧集，返回可继续传给「打开作品」的实体。
struct SearchTitlesIntent: AppIntent {
    static let title: LocalizedStringResource = "搜索作品"
    static let description = IntentDescription(
        "在 TMDB 搜索电影或剧集，结果可在后续动作中打开。",
        categoryName: "浏览",
        searchKeywords: ["电影", "剧集", "TMDB", "搜索"]
    )
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "关键词")
    var query: String

    @Parameter(title: "类型")
    var mediaType: MediaTypeAppEnum?

    func perform() async throws -> some IntentResult & ReturnsValue<[TitleEntity]> {
        let entities = try await IntentDataStore.shared.search(query: query, mediaType: mediaType)
        return .result(value: entities)
    }
}

/// Spotlight 点击索引结果 / Shortcuts「打开作品」使用。
struct OpenTitleIntent: OpenIntent {
    static let title: LocalizedStringResource = "打开作品"
    static let description = IntentDescription(
        "在显影中打开电影或剧集详情。",
        categoryName: "浏览",
        searchKeywords: ["打开", "详情", "TMDB"]
    )

    @Parameter(title: "作品")
    var target: TitleEntity

    func perform() async throws -> some IntentResult {
        Log.intents.info("OpenTitleIntent 收到：\(self.target.id, privacy: .public)")
        await IntentRouter.shared.openTitle(target)
        return .result()
    }
}

/// 给蝉蜕等外部工作流用：只知道 TMDB ID 也能直接打开。
struct OpenTitleByIDIntent: AppIntent {
    static let title: LocalizedStringResource = "按 TMDB ID 打开"
    static let description = IntentDescription(
        "用 TMDB ID 与类型直接打开显影详情，适合与蝉蜕或其它工具联动。",
        categoryName: "浏览",
        searchKeywords: ["TMDB ID", "蝉蜕", "详情"]
    )
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "TMDB ID", description: "例如 157336")
    var tmdbID: Int

    @Parameter(title: "类型")
    var mediaType: MediaTypeAppEnum

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard tmdbID > 0 else { throw LatentIntentError.invalidTMDBID }
        await IntentRouter.shared.openTitle(mediaKind: mediaType.mediaKind, tmdbID: tmdbID)
        return .result(dialog: "正在打开 TMDB \(tmdbID)")
    }
}

/// 打开应用并预填全局搜索（适合从其它 App 一键带入关键词）。
struct OpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "在显影中搜索"
    static let description = IntentDescription(
        "打开显影，把关键词填进全局搜索面板。",
        categoryName: "浏览",
        searchKeywords: ["搜索", "打开"]
    )
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "关键词")
    var query: String?

    func perform() async throws -> some IntentResult {
        await IntentRouter.shared.openSearch(query ?? "")
        return .result()
    }
}

/// 免配置 App Shortcuts（Shortcuts / Siri 中直接出现）。
struct LatentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchTitlesIntent(),
            // macOS 27 元数据处理器只允许 AppEntity / AppEnum 出现在短语里；
            // 自由文本关键词不进短语，由 Shortcuts 在运行时询问。
            phrases: [
                "用 \(.applicationName) 搜索",
                "在 \(.applicationName) 里查找"
            ],
            shortTitle: "搜索作品",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSearchIntent(),
            phrases: [
                "在 \(.applicationName) 中搜索",
                "打开 \(.applicationName) 搜索"
            ],
            shortTitle: "在显影中搜索",
            systemImageName: "magnifyingglass.circle"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .grape }
}
