import Foundation

/// 300ms 防抖（搜索、发现筛选共用）。
///
/// 每次调用取消上一次未执行的动作；窗口内只执行最后一次（设计文档第 11 节「搜索防抖」）。
@MainActor
final class Debouncer {
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .milliseconds(300)) {
        self.interval = interval
    }

    /// 调度一次动作（延迟执行，期间再次调度会取消前一次）。
    func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [interval] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return // 被取消
            }
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    /// 立即取消未执行的动作。
    func cancel() {
        task?.cancel()
        task = nil
    }
}
