import Foundation

/// App Intents → SwiftUI 导航（设计文档第 8.9 节）。
///
/// 冷启动时 Intent 可能先于 `MainSplitView` 出现：目的地先存 pending，
/// 主视图 `onAppear` / 收到通知时消费。应用已运行时通知即时消费。
@MainActor
final class IntentRouter {
    static let shared = IntentRouter()

    enum Destination: Sendable, Equatable {
        case detail(DetailDestination)
        case search(String)
    }

    static let didRequest = Notification.Name("app.latent.intent.request")

    private(set) var pending: Destination?

    func openTitle(_ entity: TitleEntity) {
        guard let destination = entity.detailDestination else { return }
        enqueue(.detail(destination))
    }

    func openTitle(mediaKind: MediaKind, tmdbID: Int) {
        switch mediaKind {
        case .movie:
            enqueue(.detail(.movie(id: tmdbID, fallback: nil)))
        case .tv:
            enqueue(.detail(.tv(id: tmdbID, fallback: nil)))
        default:
            break
        }
    }

    func openSearch(_ query: String) {
        enqueue(.search(query.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func consume() -> Destination? {
        defer { pending = nil }
        return pending
    }

    private func enqueue(_ destination: Destination) {
        Log.intents.info("IntentRouter 入队：\(String(describing: destination), privacy: .public)")
        pending = destination
        NotificationCenter.default.post(name: Self.didRequest, object: nil)
    }
}
