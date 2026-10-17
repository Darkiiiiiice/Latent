import Foundation
import SwiftData
import OSLog

/// 浏览历史：最近 500 条（设计文档第 3、6 节）；按「今天 / 本周 / 更早」分组展示。
///
/// 注意：Store 必须持有 `ModelContainer`（`ModelContext` 不会让容器存活）。
@MainActor
@Observable
final class HistoryStore {
    static let maximumCount = 500

    private let container: ModelContainer
    private let context: ModelContext

    private(set) var items: [LibrarySnapshot] = []

    init(container: ModelContainer) {
        self.container = container
        let context = container.mainContext
        self.context = context
        self.items = Self.load(from: context)
    }

    /// 记录一次查看（同作品去重，刷新时间并置顶）。
    func record(_ summary: MediaSummary, at date: Date = Date()) {
        LibraryStoreWriter.upsertHistory(summary, into: context, at: date)
        trimIfNeeded()
        saveAndReload()
    }

    func clear() {
        for entry in (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? [] {
            context.delete(entry)
        }
        saveAndReload()
    }

    var count: Int { items.count }

    /// 按时间分组（今天 / 本周 / 更早）。
    func grouped(now: Date = Date(), calendar: Calendar = .current) -> [(title: String, entries: [LibrarySnapshot])] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        var today: [LibrarySnapshot] = []
        var thisWeek: [LibrarySnapshot] = []
        var earlier: [LibrarySnapshot] = []

        for item in items {
            if item.addedAt >= startOfToday {
                today.append(item)
            } else if item.addedAt >= startOfWeek {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }

        var groups: [(String, [LibrarySnapshot])] = []
        if !today.isEmpty { groups.append(("今天", today)) }
        if !thisWeek.isEmpty { groups.append(("本周", thisWeek)) }
        if !earlier.isEmpty { groups.append(("更早", earlier)) }
        return groups
    }

    /// 超过上限时删除最旧条目。
    private func trimIfNeeded() {
        let all = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
        guard all.count > Self.maximumCount else { return }
        let excess = all.count - Self.maximumCount
        let oldest = all.sorted { $0.lastViewedAt < $1.lastViewedAt }.prefix(excess)
        for entry in oldest {
            context.delete(entry)
        }
    }

    private func saveAndReload() {
        do {
            try context.save()
        } catch {
            Log.store.error("历史保存失败：\(error.localizedDescription, privacy: .public)")
        }
        items = Self.load(from: context)
    }

    private static func load(from context: ModelContext) -> [LibrarySnapshot] {
        let entries = (try? context.fetch(FetchDescriptor<HistoryEntry>())) ?? []
        return entries
            .sorted { $0.lastViewedAt > $1.lastViewedAt }
            .map(\.snapshot)
    }
}
