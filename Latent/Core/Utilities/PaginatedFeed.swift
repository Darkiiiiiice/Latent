import Foundation
import Observation

/// 分页加载状态机（设计文档第 5 节）：
/// `idle → loadingFirst → loaded → loadingMore → loaded … → end / error(可重试)`
///
/// 与网络层解耦（通过 loader 闭包注入），合并去重、末页判定独立成可测类型。
@MainActor
@Observable
final class PaginatedFeed<Item: Identifiable & Sendable> where Item.ID: Hashable {
    private(set) var items: [Item] = []
    private(set) var state: State = .idle

    private var nextPage = 1
    private var lastPageReached = false
    private var currentTask: Task<Void, Never>?

    /// loader：返回指定页的 (条目, 是否末页)。
    private let loader: (Int) async throws -> (items: [Item], isLastPage: Bool)

    enum State: Equatable {
        case idle
        case loadingFirst
        case loaded
        case loadingMore
        case end
        case error(String)

        var isLoadingAny: Bool {
            self == .loadingFirst || self == .loadingMore
        }

        var isInitialLoading: Bool {
            self == .loadingFirst || self == .idle
        }
    }

    init(loader: @escaping (Int) async throws -> (items: [Item], isLastPage: Bool)) {
        self.loader = loader
    }

    /// 首屏加载（重复调用由状态机自行忽略）。
    func loadFirstPageIfNeeded() async {
        guard case .idle = state else { return }
        await run(page: 1, isFirst: true)
    }

    /// 滚动到底部触发（同一时刻只允许一次；已到末页忽略）。
    func loadMoreIfNeeded(currentItem: Item?) async {
        guard let currentItem else { return }
        guard currentItem.id == items.last?.id else { return }
        await loadNextPageIfPossible()
    }

    /// 加载下一页（不依赖「最后一项出现」的事件，供「加载更多」按钮等显式入口使用）。
    /// 未处于 `.loaded`（首屏加载中 / 已有分页请求在飞 / 已结束 / 错误待重试）时忽略。
    func loadNextPageIfPossible() async {
        guard !lastPageReached else { return }
        guard !state.isLoadingAny else { return }
        guard case .loaded = state else { return }
        await run(page: nextPage, isFirst: false)
    }

    /// 下拉刷新 / 筛选变化：整体重来。
    func reload() async {
        currentTask?.cancel()
        currentTask = nil
        items = []
        nextPage = 1
        lastPageReached = false
        state = .idle
        await loadFirstPageIfNeeded()
    }

    /// 错误后重试当前页。
    func retry() async {
        guard case .error = state else { return }
        await run(page: nextPage, isFirst: items.isEmpty)
    }

    private func run(page: Int, isFirst: Bool) async {
        if isFirst {
            state = .loadingFirst
        } else {
            state = .loadingMore
        }

        let loader = self.loader
        let task = Task<(items: [Item], isLastPage: Bool), any Error> {
            do {
                let result = try await loader(page)
                try Task.checkCancellation()
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.offline
            }
        }
        currentTask = Task { _ = try? await task.value }

        do {
            let result = try await task.value
            append(result.items, isFirst: isFirst)
            lastPageReached = result.isLastPage
            if lastPageReached {
                state = .end
            } else {
                state = .loaded
                nextPage = page + 1
            }
        } catch is CancellationError {
            // 保持上一次状态（调用方主动取消，不置错误态）
        } catch let error as APIError {
            state = .error(error.errorDescription)
        } catch {
            state = .error(APIError.offline.errorDescription)
        }
    }

    private func append(_ newItems: [Item], isFirst: Bool) {
        if isFirst {
            items = dedupe(newItems)
        } else {
            items = dedupe(items + newItems)
        }
    }

    /// 合并去重：同 id 只保留一条（分页边界重复、推荐与相似重叠等）。
    private func dedupe(_ list: [Item]) -> [Item] {
        var seen = Set<Item.ID>()
        var result: [Item] = []
        result.reserveCapacity(list.count)
        for item in list where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }
}
