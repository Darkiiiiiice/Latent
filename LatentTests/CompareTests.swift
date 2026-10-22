import Testing
import Foundation
@testable import Latent

@Suite @MainActor
struct CompareTests {
    /// 两部片都有完整数据，共同项正确交集。
    @Test("电影 × 电影：完整字段 + 共同类型 / 导演 / 演员")
    func fullMovieVsMovie() {
        let leftCredits = Credits(
            cast: [
                CastMember(id: 1, name: "Tom Hanks", character: "Woody"),
                CastMember(id: 2, name: "Tim Allen", character: "Buzz Lightyear"),
                CastMember(id: 3, name: "Don Rickles", character: "Mr. Potato Head"),
            ],
            crew: [
                CrewMember(id: 10, name: "John Lasseter", job: "Director"),
            ]
        )

        let rightCredits = Credits(
            cast: [
                CastMember(id: 1, name: "Tom Hanks", character: "Walt Disney"),
                CastMember(id: 4, name: "Emma Thompson", character: "P.L. Travers"),
            ],
            crew: [
                CrewMember(id: 10, name: "John Lasseter", job: "Director"),
            ]
        )

        let leftMovie = MovieDetail(
            id: 1, title: "Toy Story", originalTitle: "Toy Story",
            posterPath: "/tXHpQ.jpg", dateString: "1995-11-22",
            voteAverage: 8.0, voteCount: 15000,
            genres: [Genre(id: 1, name: "Animation"), Genre(id: 2, name: "Comedy"), Genre(id: 3, name: "Family")],
            credits: leftCredits,
            runtime: 81, budget: 30_000_000, revenue: 373_000_000
        )

        let rightMovie = MovieDetail(
            id: 2, title: "Saving Mr. Banks", originalTitle: "Saving Mr. Banks",
            posterPath: "/sMB.jpg", dateString: "2013-12-13",
            voteAverage: 7.3, voteCount: 6000,
            genres: [Genre(id: 2, name: "Comedy"), Genre(id: 4, name: "Drama"), Genre(id: 5, name: "History")],
            credits: rightCredits,
            runtime: 125, budget: 35_000_000, revenue: 112_000_000
        )

        let left = CompareProfile(detail: leftMovie)
        let right = CompareProfile(detail: rightMovie)

        #expect(left.id == "movie-1")
        #expect(right.id == "movie-2")
        #expect(left.mediaKind == .movie)
        #expect(right.mediaKind == .movie)

        let result = CompareResult.make(left: left, right: right)

        #expect(result.rows.count == 6) // 类型、日期、片长、评分、预算、票房
        #expect(result.sharedGenres == ["Comedy"])
        #expect(result.sharedDirectors == ["John Lasseter"])
        #expect(result.sharedCast.map(\.id) == [1])
        #expect(result.sharedCast.first?.name == "Tom Hanks")
        #expect(result.sharedCast.count == 1)
        #expect(result.sharedCount == 3) // 类型 + 导演 + 演员

        // 评分行：8.0 领先 7.3，左高亮
        if let ratingRow = result.rows.first(where: { $0.id == "rating" }) {
            #expect(ratingRow.leader == .left)
            #expect(ratingRow.left.contains("8.0"))
            #expect(ratingRow.right.contains("7.3"))
        }
        if let budgetRow = result.rows.first(where: { $0.id == "budget" }) {
            #expect(budgetRow.leader == .none)
        }
        if let revenueRow = result.rows.first(where: { $0.id == "revenue" }) {
            #expect(revenueRow.leader == .left) // 左片票房更高
        }
    }

    /// 其中一部没有数据（空字段，界面展示「—」）。
    @Test("电影缺字段：行数对应、共同项为空")
    func oneMissingFields() {
        let left = CompareProfile(detail: MovieDetail(
            id: 10, title: "Test Movie",
            voteAverage: 7.5,
            genres: [Genre(id: 1, name: "Action")],
            runtime: 120
        ))
        let right = CompareProfile(detail: MovieDetail(
            id: 20, title: "Another Movie",
            genres: []
        ))

        let result = CompareResult.make(left: left, right: right)

        #expect(result.rows.contains { $0.id == "runtime" })
        if let row = result.rows.first(where: { $0.id == "runtime" }) {
            #expect(row.left == "2 小时")
            #expect(row.right == "—")
        }
        #expect(result.sharedGenres.isEmpty)
        #expect(result.sharedCount == 0)
    }

    /// 剧集和电影对比，体量行出结果。
    @Test("剧集 × 电影：剧集有季数、电影没有")
    func tvVsMovie() {
        let show = TVShowDetail(
            id: 100, name: "Breaking Bad", originalName: "Breaking Bad",
            firstAirDate: "2008-01-20",
            voteAverage: 9.1, voteCount: 20000,
            numberOfSeasons: 5, numberOfEpisodes: 62,
            createdBy: [Creator(id: 10, name: "Vince Gilligan")]
        )
        let movie = MovieDetail(
            id: 200, title: "El Camino", dateString: "2019-10-11",
            voteAverage: 7.3, voteCount: 1500,
            runtime: 122
        )

        let left = CompareProfile(detail: show)
        let right = CompareProfile(detail: movie)

        #expect(left.mediaKind == .tv)
        #expect(left.seasonsText == "5 季 · 62 集")
        #expect(right.seasonsText == nil)

        let result = CompareResult.make(left: left, right: right)
        #expect(result.rows.contains { $0.id == "seasons" })

        if let row = result.rows.first(where: { $0.id == "seasons" }) {
            #expect(row.left == "5 季 · 62 集")
            #expect(row.right == "—")
        }
    }

    /// 顺序：共同项保留左侧顺序。
    @Test("共同项顺序保持左侧条目顺序")
    func sharedOrderFollowsLeft() {
        let leftCredits = Credits(cast: (1...8).map {
            CastMember(id: $0, name: "Actor \($0)")
        })
        let rightCredits = Credits(cast: [8, 6, 4, 2].reversed().map {
            CastMember(id: $0, name: "Actor \($0)")
        })
        let left = CompareProfile(detail: MovieDetail(id: 1, title: "Left", credits: leftCredits))
        let right = CompareProfile(detail: MovieDetail(id: 2, title: "Right", credits: rightCredits))

        let result = CompareResult.make(left: left, right: right)
        #expect(result.sharedCast.map(\.id) == [2, 4, 6, 8])
    }
}
