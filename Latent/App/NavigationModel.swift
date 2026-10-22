import SwiftUI

/// 侧边栏范围（探索 / 我的）。
enum SidebarScope: String, CaseIterable, Identifiable, Sendable {
    case trending
    case discover
    case favorites
    case watchlist
    case history
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "趋势"
        case .discover: return "发现"
        case .favorites: return "收藏"
        case .watchlist: return "观看清单"
        case .history: return "历史"
        case .stats: return "统计"
        }
    }

    var systemImage: String {
        switch self {
        case .trending: return "chart.line.uptrend.xyaxis"
        case .discover: return "sparkles"
        case .favorites: return "star"
        case .watchlist: return "bookmark"
        case .history: return "clock"
        case .stats: return "chart.bar"
        }
    }

    /// 快捷键（Cmd+1…6，设计文档第 8.7 节）。
    var shortcutIndex: Int {
        switch self {
        case .trending: return 1
        case .discover: return 2
        case .favorites: return 3
        case .watchlist: return 4
        case .history: return 5
        case .stats: return 6
        }
    }
}

/// 内容区可达的详情目的地（Push 进入）。
enum DetailDestination: Hashable, Sendable {
    case movie(id: Int, fallback: MediaSummary?)
    case tv(id: Int, fallback: MediaSummary?)
    case person(id: Int)
    /// 制片公司页（v1.21）；`name` 用于载入期间先显示标题。
    case company(id: Int, name: String?)
    /// 对比两部作品（v1.32）；两侧都是影视条目（人物 / 公司不可比）。
    case compare(left: MediaSummary, right: MediaSummary)
}

extension DetailDestination {
    static func == (lhs: DetailDestination, rhs: DetailDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.movie(lID, _), .movie(rID, _)): return lID == rID
        case let (.tv(lID, _), .tv(rID, _)): return lID == rID
        case let (.person(lID), .person(rID)): return lID == rID
        case let (.company(lID, _), .company(rID, _)): return lID == rID
        case let (.compare(lLeft, lRight), .compare(rLeft, rRight)):
            return lLeft.stableID == rLeft.stableID && lRight.stableID == rRight.stableID
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .movie(let id, _):
            hasher.combine("movie"); hasher.combine(id)
        case .tv(let id, _):
            hasher.combine("tv"); hasher.combine(id)
        case .person(let id):
            hasher.combine("person"); hasher.combine(id)
        case .company(let id, _):
            hasher.combine("company"); hasher.combine(id)
        case .compare(let left, let right):
            hasher.combine("compare")
            hasher.combine(left.stableID)
            hasher.combine(right.stableID)
        }
    }

    static func from(_ summary: MediaSummary) -> DetailDestination? {
        switch summary.mediaKind {
        case .movie: return .movie(id: summary.id, fallback: summary)
        case .tv: return .tv(id: summary.id, fallback: summary)
        default: return nil
        }
    }
}

/// Cmd+R 等命令通过通知总线转发（视图自行声明可达性）。
enum AppCommandBus {
    static let refresh = Notification.Name("app.latent.command.refresh")
    static let back = Notification.Name("app.latent.command.back")
    static let focusSearch = Notification.Name("app.latent.command.focusSearch")
    /// 切换侧边栏范围（object = SidebarScope.rawValue）。
    static let selectScope = Notification.Name("app.latent.command.selectScope")
    /// 在内容列 Push 详情（object = DetailDestination；详情页内跳转用）。
    static let pushDetail = Notification.Name("app.latent.command.pushDetail")
    /// 导出全部库（文件菜单；根视图消费）。
    static let exportAllJSON = Notification.Name("app.latent.command.exportAllJSON")
    static let exportAllMarkdown = Notification.Name("app.latent.command.exportAllMarkdown")
    /// 从图片识别文字（文件菜单 ⌘⇧O；主界面打开搜索面板并弹出选择器）。
    static let recognizeImage = Notification.Name("app.latent.command.recognizeImage")

    static func select(_ scope: SidebarScope) {
        NotificationCenter.default.post(name: selectScope, object: scope.rawValue)
    }
}
