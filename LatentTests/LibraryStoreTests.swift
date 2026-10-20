import Foundation
import SwiftData
import Testing
@testable import Latent

/// LibraryStore / HistoryStore（SwiftData 内存容器，设计文档第 11 节）。
@Suite("库 Store")
@MainActor
struct LibraryStoreTests {

    /// 内存容器宿主：Store 与容器必须一起存活（`ModelContext` 不会让容器存活，
    /// 容器释放后 SwiftData 会在 fetch 内直接 trap）。
    private func makeStores() -> (LibraryStore, HistoryStore, ModelContainer) {
        let container = LibraryContainerFactory.makeInMemory()
        return (LibraryStore(container: container), HistoryStore(container: container), container)
    }

    private var dune: MediaSummary {
        MediaSummary(id: 693134, mediaKind: .movie, title: "沙丘：第二部",
                     originalTitle: "Dune: Part Two", dateString: "2024-02-27",
                     voteAverage: 8.1, voteCount: 4210)
    }

    @Test("收藏去重：同 mediaType + tmdbID 只保留一条，且刷新字段")
    func favoriteDedupe() {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        #expect(library.favoriteCount == 1)
        #expect(library.isFavorite(dune))

        var updated = dune
        updated = MediaSummary(id: 693134, mediaKind: .movie, title: "沙丘：第二部（新标题）",
                               dateString: "2024-02-27", voteAverage: 8.2, voteCount: 4210)
        library.refresh(updated)

        #expect(library.favoriteCount == 1)
        #expect(library.favoriteItems.first?.title == "沙丘：第二部（新标题）")
        #expect(library.favoriteItems.first?.voteAverage == 8.2)
    }

    @Test("同一 TMDB ID 的电影与剧集互不冲突")
    func mediaKindIsolation() {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        let show = MediaSummary(id: 693134, mediaKind: .tv, title: "同名剧集", dateString: "2020-01-01")
        library.toggleFavorite(show)
        #expect(library.favoriteCount == 2)
    }

    @Test("Toggle：再次收藏即移出")
    func favoriteToggle() {
        let (library, _, _) = makeStores()
        #expect(library.toggleFavorite(dune) == true)
        #expect(library.toggleFavorite(dune) == false)
        #expect(library.favoriteCount == 0)
        #expect(library.isFavorite(dune) == false)
    }

    @Test("观看清单：加入、移出、移入收藏")
    func watchlistFlow() {
        let (library, _, _) = makeStores()
        library.toggleWatchlist(dune)
        #expect(library.isInWatchlist(dune))
        #expect(library.watchlistCount == 1)

        library.moveToFavorites(dune)
        #expect(library.watchlistCount == 0)
        #expect(library.isFavorite(dune))
        #expect(library.favoriteCount == 1)
    }

    @Test("排序：添加时间 / 评分 / 年份")
    func sorting() {
        let (library, _, _) = makeStores()
        let a = MediaSummary(id: 1, mediaKind: .movie, title: "A", dateString: "1999-01-01", voteAverage: 6.0)
        let b = MediaSummary(id: 2, mediaKind: .movie, title: "B", dateString: "2020-01-01", voteAverage: 9.0)
        library.toggleFavorite(a)
        library.toggleFavorite(b)

        #expect(library.items(kind: .favorites, sortedBy: .rating).first?.title == "B")
        #expect(library.items(kind: .favorites, sortedBy: .year).first?.title == "B")
        #expect(library.items(kind: .favorites, sortedBy: .addedAt).count == 2)
    }

    @Test("历史：上限 500 条，超出后保留最新")
    func historyLimit() {
        let (_, history, _) = makeStores()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<(HistoryStore.maximumCount + 20) {
            let item = MediaSummary(id: index, mediaKind: .movie, title: "作品 \(index)")
            history.record(item, at: base.addingTimeInterval(Double(index)))
        }
        #expect(history.count == HistoryStore.maximumCount)

        // 最新一条（id 519）应仍在，最旧一条（id 0）应已被淘汰
        #expect(history.items.contains { $0.tmdbID == HistoryStore.maximumCount + 19 })
        #expect(history.items.contains { $0.tmdbID == 0 } == false)
    }

    @Test("历史：同作品重复查看去重并置顶")
    func historyDedupe() {
        let (_, history, _) = makeStores()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        history.record(dune, at: base)
        let other = MediaSummary(id: 157336, mediaKind: .movie, title: "星际穿越")
        history.record(other, at: base.addingTimeInterval(60))
        history.record(dune, at: base.addingTimeInterval(120))

        #expect(history.count == 2)
        #expect(history.items.first?.tmdbID == dune.id)
    }

    @Test("历史：分组（今天 / 本周 / 更早）")
    func historyGrouping() {
        let (_, history, _) = makeStores()
        let now = Date()
        history.record(MediaSummary(id: 1, mediaKind: .movie, title: "今天"), at: now)
        history.record(MediaSummary(id: 2, mediaKind: .movie, title: "本周"), at: now.addingTimeInterval(-3 * 86_400))
        history.record(MediaSummary(id: 3, mediaKind: .movie, title: "更早"), at: now.addingTimeInterval(-30 * 86_400))

        let groups = history.grouped(now: now)
        #expect(groups.map(\.title) == ["今天", "本周", "更早"])
    }

    @Test("历史：清除全部")
    func historyClear() {
        let (_, history, _) = makeStores()
        history.record(dune)
        history.clear()
        #expect(history.count == 0)
    }

    @Test("快照 → MediaSummary 往返（库条目可进详情）")
    func snapshotRoundTrip() {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        let snapshot = library.favoriteItems.first!
        let summary = snapshot.asSummary
        #expect(summary.id == dune.id)
        #expect(summary.mediaKind == .movie)
        #expect(summary.year == 2024)
    }

    // MARK: - 单条操作（v1.7.1）

    @Test("单条移出收藏：撤销按原添加时间恢复")
    func singleRemoveAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        let original = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })

        #expect(library.toggleFavorite(dune) == false)
        let change = try #require(library.lastChange)
        #expect(library.favoriteCount == 0)
        #expect(change.source == .favorites)
        #expect(change.destination == nil)
        #expect(change.snapshots.map(\.id) == [dune.stableID])

        library.undoLastChange()

        let restored = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })
        #expect(library.favoriteCount == 1)
        #expect(restored.addedAt == original.addedAt)
        #expect(library.lastChange == nil)
    }

    @Test("单条移出观看清单：撤销按原添加时间恢复")
    func singleWatchlistRemoveAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleWatchlist(dune)
        let original = try #require(library.watchlistItems.first { $0.tmdbID == dune.id })

        #expect(library.toggleWatchlist(dune) == false)
        let change = try #require(library.lastChange)
        #expect(library.watchlistCount == 0)
        #expect(change.source == .watchlist)
        #expect(change.destination == nil)

        library.undoLastChange()

        let restored = try #require(library.watchlistItems.first { $0.tmdbID == dune.id })
        #expect(library.watchlistCount == 1)
        #expect(restored.addedAt == original.addedAt)
        #expect(library.lastChange == nil)
    }

    @Test("单条移动：撤销恢复源清单并移除本次新增")
    func singleMoveAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        let original = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })

        let change = try #require(library.moveToWatchlist(dune))
        #expect(library.favoriteCount == 0)
        #expect(library.watchlistCount == 1)
        #expect(change.source == .favorites)
        #expect(change.destination == .watchlist)
        #expect(change.destinationIDsAdded == [dune.stableID])

        library.undoLastChange()

        let restored = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })
        #expect(library.favoriteCount == 1)
        #expect(library.watchlistCount == 0)
        #expect(restored.addedAt == original.addedAt)
        #expect(library.lastChange == nil)
    }

    @Test("单条移动：观看清单 → 收藏撤销恢复")
    func singleMoveToFavoritesAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleWatchlist(dune)
        let original = try #require(library.watchlistItems.first { $0.tmdbID == dune.id })

        let change = try #require(library.moveToFavorites(dune))
        #expect(library.watchlistCount == 0)
        #expect(library.favoriteCount == 1)
        #expect(change.source == .watchlist)
        #expect(change.destination == .favorites)

        library.undoLastChange()

        let restored = try #require(library.watchlistItems.first { $0.tmdbID == dune.id })
        #expect(library.watchlistCount == 1)
        #expect(library.favoriteCount == 0)
        #expect(restored.addedAt == original.addedAt)
    }

    @Test("单条移动：目标原本已有条目不覆盖添加时间")
    func singleMovePreservesExistingDestination() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        library.toggleWatchlist(dune)
        let watchlistOriginal = try #require(library.watchlistItems.first { $0.tmdbID == dune.id })

        let change = try #require(library.moveToWatchlist(dune))
        #expect(change.destinationIDsAdded.isEmpty)
        #expect(library.favoriteCount == 0)
        #expect(library.watchlistCount == 1)
        #expect(library.watchlistItems.first?.addedAt == watchlistOriginal.addedAt)

        library.undoLastChange()

        #expect(library.favoriteCount == 1)
        #expect(library.watchlistCount == 1)
        #expect(library.isFavorite(dune))
        #expect(library.watchlistItems.first?.addedAt == watchlistOriginal.addedAt)
    }

    @Test("单条移动：源清单没有条目不产生撤销记录")
    func singleMoveNoSource() {
        let (library, _, _) = makeStores()
        #expect(library.moveToWatchlist(dune) == nil)
        #expect(library.moveToFavorites(dune) == nil)
        #expect(library.lastChange == nil)
    }

    // MARK: - 批量操作（v1.7）

    private var interstellar: MediaSummary {
        MediaSummary(id: 157336, mediaKind: .movie, title: "星际穿越",
                     dateString: "2014-11-05", voteAverage: 8.4)
    }

    @Test("批量移出：撤销后按原添加时间恢复")
    func batchRemoveAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        library.toggleFavorite(interstellar)

        let original = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })
        let change = try #require(
            library.removeItems(ids: [original.id], from: .favorites)
        )

        #expect(library.favoriteCount == 1)
        #expect(change.snapshots.count == 1)
        #expect(library.lastChange?.id == change.id)

        library.undo(change)

        let restored = try #require(library.favoriteItems.first { $0.tmdbID == dune.id })
        #expect(library.favoriteCount == 2)
        #expect(restored.addedAt == original.addedAt)
        #expect(library.lastChange == nil)
    }

    @Test("批量移动：撤销只移除本次新增，原本已在目标清单的保留")
    func batchMoveAndUndo() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        library.toggleFavorite(interstellar)
        library.toggleWatchlist(dune) // 同时已在观看清单

        let ids = Set(library.favoriteItems.map(\.id))
        let change = try #require(
            library.moveItems(ids: ids, from: .favorites, to: .watchlist)
        )

        #expect(library.favoriteCount == 0)
        #expect(library.watchlistCount == 2)
        #expect(change.destinationIDsAdded.count == 1)
        #expect(change.destinationIDsAdded.contains(interstellar.stableID))
        #expect(change.destinationIDsAdded.contains(dune.stableID) == false)

        library.undo(change)

        #expect(library.favoriteCount == 2)
        #expect(library.watchlistCount == 1)
        #expect(library.isInWatchlist(dune))
        #expect(library.isFavorite(dune))
        #expect(library.isFavorite(interstellar))
    }

    @Test("批量操作：空选择或没有匹配条目返回 nil")
    func batchNoMatch() {
        let (library, _, _) = makeStores()
        #expect(library.removeItems(ids: [], from: .favorites) == nil)
        #expect(library.removeItems(ids: ["movie-404"], from: .favorites) == nil)
        #expect(library.moveItems(ids: ["movie-404"], from: .favorites, to: .watchlist) == nil)
        #expect(library.lastChange == nil)
    }

    @Test("刷新展示字段不改变添加时间")
    func refreshKeepsAddedAt() throws {
        let (library, _, _) = makeStores()
        library.toggleFavorite(dune)
        let original = try #require(library.favoriteItems.first)
        let updated = MediaSummary(id: dune.id, mediaKind: .movie, title: "沙丘：第二部（新）",
                                   dateString: "2024-02-27", voteAverage: 8.3)

        library.refresh(updated)

        #expect(library.favoriteItems.first?.title == "沙丘：第二部（新）")
        #expect(library.favoriteItems.first?.addedAt == original.addedAt)
    }
}
