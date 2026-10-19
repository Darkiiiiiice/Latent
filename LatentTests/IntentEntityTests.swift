import Foundation
import Testing
@testable import Latent

/// App Intents / Spotlight 实体（设计文档第 8.9 节）。
@Suite("系统集成实体")
struct IntentEntityTests {
    private func snapshot(
        _ kind: MediaKind,
        _ id: Int,
        _ title: String,
        addedAt: Date = Date(timeIntervalSince1970: 1_726_000_000)
    ) -> LibrarySnapshot {
        LibrarySnapshot(
            mediaKind: kind,
            tmdbID: id,
            title: title,
            originalTitle: "Original \(title)",
            year: 2024,
            posterPath: "/p.jpg",
            voteAverage: 8.123,
            addedAt: addedAt
        )
    }

    @Test("库快照 → 实体：ID / 类型 / 摘要")
    func mapping() {
        let entity = TitleEntity(snapshot: snapshot(.movie, 157336, "星际穿越"))
        #expect(entity.id == "movie-157336")
        #expect(entity.tmdbID == 157336)
        #expect(entity.mediaKind == .movie)
        #expect(entity.title == "星际穿越")
        #expect(entity.year == 2024)
        #expect(entity.summary.id == 157336)
        #expect(entity.detailDestination == .movie(id: 157336, fallback: entity.summary))
    }

    @Test("ID 解析：movie / tv；非法值返回 nil")
    func parse() {
        let movie = TitleEntity.parse(identifier: "movie-157336")
        #expect(movie?.mediaKind == .movie)
        #expect(movie?.tmdbID == 157336)

        let tv = TitleEntity.parse(identifier: "tv-1396")
        #expect(tv?.mediaKind == .tv)
        #expect(tv?.tmdbID == 1396)

        #expect(TitleEntity.parse(identifier: "person-123") == nil)
        #expect(TitleEntity.parse(identifier: "movie-abc") == nil)
        #expect(TitleEntity.parse(identifier: "157336") == nil)
    }

    @Test("Spotlight 合并：同一作品收藏优先，清单不重复")
    func buckets() {
        let favoriteDate = Date(timeIntervalSince1970: 1_726_000_000)
        let watchlistDate = Date(timeIntervalSince1970: 1_726_100_000)
        let favorites = [snapshot(.movie, 1, "收藏作品", addedAt: favoriteDate)]
        let watchlist = [
            snapshot(.movie, 1, "收藏作品（旧）", addedAt: watchlistDate),
            snapshot(.tv, 2, "清单作品", addedAt: watchlistDate)
        ]

        let buckets = TitleEntity.buckets(favorites: favorites, watchlist: watchlist)
        #expect(buckets.favorites.count == 1)
        #expect(buckets.favorites.first?.title == "收藏作品")
        #expect(buckets.watchlist.count == 1)
        #expect(buckets.watchlist.first?.id == "tv-2")

        let merged = TitleEntity.merged(favorites: favorites, watchlist: watchlist)
        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)).count == 2)
    }

    @Test("排序：收藏 / 清单内部按加入时间倒序")
    func ordering() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_726_000_000)
        let buckets = TitleEntity.buckets(
            favorites: [
                snapshot(.movie, 1, "旧", addedAt: older),
                snapshot(.movie, 2, "新", addedAt: newer)
            ],
            watchlist: []
        )
        #expect(buckets.favorites.map(\.tmdbID) == [2, 1])
    }

    @Test("路由：详情目的地排队并在消费后清空")
    @MainActor
    func router() {
        let router = IntentRouter()
        router.openTitle(mediaKind: .tv, tmdbID: 1396)
        #expect(router.consume() == .detail(.tv(id: 1396, fallback: nil)))
        #expect(router.consume() == nil)

        router.openSearch("  星际穿越  ")
        #expect(router.consume() == .search("星际穿越"))
    }
}
