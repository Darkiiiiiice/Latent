import Testing
import Foundation
@testable import Latent

@Suite("六度分隔")
struct SixDegreesTests {

    // MARK: - 假图谱

    /// 预置一张人物 / 作品关系图，并统计请求数。
    actor FakeFetcher: SixDegreesFetching {
        let movies: [String: SixDegreesMovieGraph]
        let people: [Int: SixDegreesPersonGraph]
        private(set) var movieRequests = 0
        private(set) var personRequests = 0

        init(movies: [String: SixDegreesMovieGraph], people: [Int: SixDegreesPersonGraph]) {
            self.movies = movies
            self.people = people
        }

        func movieGraph(id: Int, mediaKind: MediaKind) async throws -> SixDegreesMovieGraph {
            movieRequests += 1
            guard let graph = movies["\(mediaKind.rawValue)-\(id)"] else {
                struct Missing: Error {}
                throw Missing()
            }
            return graph
        }

        func personGraph(id: Int) async throws -> SixDegreesPersonGraph {
            personRequests += 1
            guard let graph = people[id] else {
                struct Missing: Error {}
                throw Missing()
            }
            return graph
        }
    }

    private func movie(_ kind: MediaKind, _ id: Int, _ title: String) -> SixDegreesMovie {
        SixDegreesMovie(id: id, mediaKind: kind, title: title)
    }

    private func person(_ id: Int, _ name: String) -> SixDegreesPerson {
        SixDegreesPerson(id: id, name: name, profilePath: nil)
    }

    /// 断言路径结构合法：首尾为目标片、人物与作品交替、连接数 = 节点数 − 1。
    private func assertStructure(_ path: SixDegreesPath, left: SixDegreesMovie, right: SixDegreesMovie) {
        guard case .movie(let first) = path.nodes.first else {
            Issue.record("路径起点必须是作品")
            return
        }
        guard case .movie(let last) = path.nodes.last else {
            Issue.record("路径终点必须是作品")
            return
        }
        #expect(first.stableID == left.stableID)
        #expect(last.stableID == right.stableID)
        #expect(path.links.count == path.nodes.count - 1)
        for (index, node) in path.nodes.enumerated() {
            let isMovie = index.isMultiple(of: 2)
            switch node {
            case .movie: #expect(isMovie, "第 \(index) 个节点应为作品")
            case .person: #expect(!isMovie, "第 \(index) 个节点应为人行")
            }
        }
    }

    // MARK: - 用例

    @Test("共同人物直连：两部片各拉一次即成三节点路径")
    func directSharedPerson() async throws {
        let a = movie(.movie, 1, "A")
        let b = movie(.movie, 2, "B")
        let p = person(10, "共同演员")
        let fetcher = FakeFetcher(
            movies: [
                "movie-1": SixDegreesMovieGraph(movie: a, people: [(p, .acting)]),
                "movie-2": SixDegreesMovieGraph(movie: b, people: [(p, .acting)]),
            ],
            people: [:]
        )

        let outcome = try await SixDegreesSearch.find(left: a, right: b, fetcher: fetcher)
        guard case .found(let path) = outcome else {
            Issue.record("应直接命中共同人物")
            return
        }
        assertStructure(path, left: a, right: b)
        #expect(path.nodes.count == 3)
        #expect(path.links == ["共同演员 主演", "共同演员 出演"])
        #expect(await fetcher.movieRequests == 2)
        #expect(await fetcher.personRequests == 0)
    }

    @Test("两层路径：A—人—片—人—B，请求计数正确")
    func twoHopPath() async throws {
        let a = movie(.movie, 1, "A")
        let mid = movie(.movie, 3, "M")
        let b = movie(.movie, 2, "B")
        let p1 = person(10, "甲")
        let p2 = person(20, "乙")

        let fetcher = FakeFetcher(
            movies: [
                "movie-1": SixDegreesMovieGraph(movie: a, people: [(p1, .acting)]),
                "movie-3": SixDegreesMovieGraph(movie: mid, people: [(p2, .directing)]),
                "movie-2": SixDegreesMovieGraph(movie: b, people: [(p2, .acting)]),
            ],
            people: [
                10: SixDegreesPersonGraph(person: p1, acted: [mid], crewed: []),
                20: SixDegreesPersonGraph(person: p2, acted: [b], crewed: []),
            ]
        )

        let outcome = try await SixDegreesSearch.find(left: a, right: b, fetcher: fetcher)
        guard case .found(let path) = outcome else {
            Issue.record("应找到两层路径")
            return
        }
        assertStructure(path, left: a, right: b)
        // A → 甲（主演）→ M → 乙（导演）→ B
        #expect(path.nodes.map(\.id) == ["movie-1", "person-10", "movie-3", "person-20", "movie-2"])
        #expect(path.links == ["甲 主演", "甲 出演", "乙 导演", "乙 出演"])
        // 开销：A、B、M 三次作品 + 甲一次影人（乙在命中时无需再拉）。
        #expect(await fetcher.movieRequests == 3)
        #expect(await fetcher.personRequests == 1)
    }

    @Test("无路可走：预算耗尽返回未找到，请求量不超过预算")
    func budgetExhausted() async throws {
        let a = movie(.movie, 1, "A")
        let b = movie(.movie, 2, "B")
        let lonely = person(10, "孤影人")
        var budget = SixDegreesSearch.Budget()
        budget.maxRequests = 6

        let fetcher = FakeFetcher(
            movies: [
                "movie-1": SixDegreesMovieGraph(movie: a, people: [(lonely, .acting)]),
                "movie-2": SixDegreesMovieGraph(movie: b, people: [(person(99, "路人"), .acting)]),
            ],
            people: [
                10: SixDegreesPersonGraph(person: lonely, acted: [], crewed: []),
            ]
        )

        let outcome = try await SixDegreesSearch.find(left: a, right: b, fetcher: fetcher, budget: budget)
        guard case .notFound(let movies, let people) = outcome else {
            Issue.record("预算内找不到应返回 notFound")
            return
        }
        #expect(movies == 2)
        #expect(people == 1)
        let total = await fetcher.movieRequests + fetcher.personRequests
        #expect(total <= budget.maxRequests)
    }

    @Test("同一人物在多部片出现只扩展一次")
    func deduplicatesPeople() async throws {
        let a = movie(.movie, 1, "A")
        let m1 = movie(.movie, 3, "M1")
        let m2 = movie(.movie, 4, "M2")
        let b = movie(.movie, 2, "B")
        let p1 = person(10, "甲")
        let p2 = person(20, "乙")

        // 甲同时出现在 A、M1、M2 的演职员里；只有第一次被发现时会扩展。
        let fetcher = FakeFetcher(
            movies: [
                "movie-1": SixDegreesMovieGraph(movie: a, people: [(p1, .acting)]),
                "movie-3": SixDegreesMovieGraph(movie: m1, people: [(p1, .acting), (p2, .acting)]),
                "movie-4": SixDegreesMovieGraph(movie: m2, people: [(p1, .acting)]),
                "movie-2": SixDegreesMovieGraph(movie: b, people: [(p2, .acting)]),
            ],
            people: [
                10: SixDegreesPersonGraph(person: p1, acted: [m1, m2], crewed: []),
                20: SixDegreesPersonGraph(person: p2, acted: [b], crewed: []),
            ]
        )

        let outcome = try await SixDegreesSearch.find(left: a, right: b, fetcher: fetcher)
        guard case .found = outcome else {
            Issue.record("应找到路径")
            return
        }
        // 甲只拉一次（10 号影人图谱只取一次），乙在命中时无需再拉。
        #expect(await fetcher.personRequests == 1)
    }

    @Test("全部取数失败时抛出错误，交给界面显示可重试横幅")
    func throwsWhenEverythingFails() async {
        let a = movie(.movie, 1, "A")
        let b = movie(.movie, 2, "B")
        let fetcher = FakeFetcher(movies: [:], people: [:])

        do {
            _ = try await SixDegreesSearch.find(left: a, right: b, fetcher: fetcher)
            Issue.record("全失败时应抛错")
        } catch {
            // 预期：两侧图谱都拿不到时抛出最后一个错误。
        }
    }
}
