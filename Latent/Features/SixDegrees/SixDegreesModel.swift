import Foundation

// MARK: - 图节点

/// 六度分隔图里的作品节点（v1.35）。
struct SixDegreesMovie: Sendable, Equatable, Identifiable {
    let id: Int
    let mediaKind: MediaKind
    let title: String
    let posterPath: String?
    let dateString: String?

    var stableID: String { "\(mediaKind.rawValue)-\(id)" }

    init(id: Int, mediaKind: MediaKind, title: String, posterPath: String? = nil, dateString: String? = nil) {
        self.id = id
        self.mediaKind = mediaKind
        self.title = title
        self.posterPath = posterPath
        self.dateString = dateString
    }

    init(summary: MediaSummary) {
        self.init(
            id: summary.id, mediaKind: summary.mediaKind, title: summary.title,
            posterPath: summary.posterPath, dateString: summary.dateString
        )
    }

    /// 还原成可 Push 的最小摘要。
    var summary: MediaSummary {
        MediaSummary(
            id: id, mediaKind: mediaKind, title: title,
            posterPath: posterPath, dateString: dateString
        )
    }
}

/// 六度分隔图里的人物节点。
struct SixDegreesPerson: Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let profilePath: String?
}

/// 路径上的一个节点：作品或人物。
enum SixDegreesPathNode: Sendable, Equatable, Identifiable {
    case movie(SixDegreesMovie)
    case person(SixDegreesPerson)

    var id: String {
        switch self {
        case .movie(let movie): return movie.stableID
        case .person(let person): return "person-\(person.id)"
        }
    }
}

/// 一条完整关系路径：作品 → 人物 → 作品 → … → 作品（首尾必为作品，中间交替）。
struct SixDegreesPath: Sendable, Equatable {
    let nodes: [SixDegreesPathNode]
    /// 每一跳的连接说明（如「提莫西·查拉梅 主演」）；数量 = 节点数 − 1。
    let links: [String]
}

// MARK: - 角色与取数抽象

/// 作品—人物连接的角色标签。
enum SixDegreesRole: String, Sendable, Equatable {
    case acting = "主演"
    case directing = "导演"
    case creating = "主创"
    case crewing = "参与制作"

    /// 「人物 → 作品」方向的措辞（主语是人物）。
    var fromPerson: String {
        switch self {
        case .acting: return "出演"
        case .directing: return "执导"
        case .creating: return "主创"
        case .crewing: return "参与制作"
        }
    }
}

/// 一部片的图信息：作品本身 + 与它相连的人物（含角色）。
struct SixDegreesMovieGraph: Sendable {
    let movie: SixDegreesMovie
    /// 相连人物（演员在前、导演 / 主创在后；同一人只出现一次，演员身份优先）。
    let people: [(person: SixDegreesPerson, role: SixDegreesRole)]
}

/// 一位影人的图信息：出演与参与的作品。
struct SixDegreesPersonGraph: Sendable {
    let person: SixDegreesPerson
    /// 出演作品（combined_credits.cast，按热度取前 N）。
    let acted: [SixDegreesMovie]
    /// 参与作品（combined_credits.crew，职位未知，统一「参与制作」）。
    let crewed: [SixDegreesMovie]
}

/// 取数抽象：单测用假图谱，真实实现包装 `TMDBClient`。
protocol SixDegreesFetching: Sendable {
    func movieGraph(id: Int, mediaKind: MediaKind) async throws -> SixDegreesMovieGraph
    func personGraph(id: Int) async throws -> SixDegreesPersonGraph
}

/// 真实实现：`movieDetail` / `personDetail`（append 数据走 7 天详情缓存）。
struct LiveSixDegreesFetcher: SixDegreesFetching {
    let client: any TMDBClientProtocol

    func movieGraph(id: Int, mediaKind: MediaKind) async throws -> SixDegreesMovieGraph {
        switch mediaKind {
        case .movie:
            let detail = try await client.movieDetail(id: id)
            let movie = SixDegreesMovie(
                id: detail.id, mediaKind: .movie, title: detail.title,
                posterPath: detail.posterPath, dateString: detail.dateString
            )
            return Self.graph(movie: movie, cast: detail.credits?.cast ?? [], crew: detail.credits?.crew ?? [])
        case .tv:
            let detail = try await client.tvDetail(id: id)
            let movie = SixDegreesMovie(
                id: detail.id, mediaKind: .tv, title: detail.name,
                posterPath: detail.posterPath, dateString: detail.firstAirDate
            )
            return Self.graph(movie: movie, cast: detail.credits?.cast ?? [], crew: detail.credits?.crew ?? [])
        default:
            throw APIError.notFound
        }
    }

    func personGraph(id: Int) async throws -> SixDegreesPersonGraph {
        let detail = try await client.personDetail(id: id)
        let person = SixDegreesPerson(id: detail.id, name: detail.name, profilePath: detail.profilePath)
        let credits = detail.combinedCredits
        let limit = SixDegreesSearch.Budget().filmsPerPerson
        let acted = (credits?.cast ?? [])
            .filter { $0.mediaKind == .movie || $0.mediaKind == .tv }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(limit)
            .map(SixDegreesMovie.init(summary:))
        let crewed = (credits?.crew ?? [])
            .filter { $0.mediaKind == .movie || $0.mediaKind == .tv }
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(limit)
            .map(SixDegreesMovie.init(summary:))
        return SixDegreesPersonGraph(person: person, acted: Array(acted), crewed: Array(crewed))
    }

    /// 演职员表 → 相连人物（演员前 8 + 导演 / 主创；同一人演员身份优先）。
    static func graph(movie: SixDegreesMovie, cast: [CastMember], crew: [CrewMember]) -> SixDegreesMovieGraph {
        var people: [(person: SixDegreesPerson, role: SixDegreesRole)] = []
        var seen = Set<Int>()

        for member in cast.prefix(SixDegreesSearch.Budget().peoplePerMovie) where !seen.contains(member.id) {
            seen.insert(member.id)
            people.append((SixDegreesPerson(id: member.id, name: member.name, profilePath: member.profilePath), .acting))
        }
        for member in crew where !seen.contains(member.id) {
            let role: SixDegreesRole
            switch member.job {
            case "Director": role = .directing
            case "Creator": role = .creating
            default: continue
            }
            seen.insert(member.id)
            people.append((SixDegreesPerson(id: member.id, name: member.name, profilePath: member.profilePath), role))
        }
        return SixDegreesMovieGraph(movie: movie, people: people)
    }
}

// MARK: - BFS 搜索

enum SixDegreesSearch {
    /// 搜索预算：控制请求量与搜索深度，避免图的规模失控。
    struct Budget: Sendable {
        /// 全程最多发出的取数次数（含左右两部片的开销）。
        var maxRequests = 150
        /// 每部片最多扩展的人物数（演员；导演 / 主创另计）。
        var peoplePerMovie = 8
        /// 每位影人最多扩展的作品数（按热度）。
        var filmsPerPerson = 30
        /// 路径中间最多几位影人（3 位 = 最多 4 部片）。
        var maxIntermediatePeople = 3
    }

    enum Outcome: Sendable, Equatable {
        case found(SixDegreesPath)
        /// 预算内未找到（附探索量，供界面说明）。
        case notFound(exploredMovies: Int, exploredPeople: Int)
    }

    /// 在关系图里找 `left` 与 `right` 的最短路径。
    ///
    /// 先拉两侧演职员；从左片起逐层「片 → 人 → 片」扩展，人物命中目标片
    /// 演职员集、或影人作品命中目标 id 即回溯成路。单个节点取数失败按死路
    /// 跳过；若全程一次成功都没有（断网等）则把错误抛给界面。
    static func find(
        left: SixDegreesMovie,
        right: SixDegreesMovie,
        fetcher: any SixDegreesFetching,
        budget: Budget = Budget(),
        onProgress: (@Sendable (_ movies: Int, _ people: Int) -> Void)? = nil
    ) async throws -> Outcome {
        precondition(left.stableID != right.stableID, "同一部片不需要找关系路径")

        let session = SearchSession(fetcher: fetcher, budget: budget)

        // 1. 两侧演职员（最先花掉的 2 次请求）。
        guard let leftGraph = await session.loadMovie(left),
              let rightGraph = await session.loadMovie(right) else {
            try await session.rethrowIfTotallyFailed()
            return .notFound(
                exploredMovies: await session.exploredMovies,
                exploredPeople: await session.exploredPeople
            )
        }

        let rightID = right.stableID
        let rightPeople = Dictionary(uniqueKeysWithValues: rightGraph.people.map { ($0.person.id, $0.role) })

        // 人物 →（来自哪部片、什么角色）；作品 →（经哪位人物、什么角色）。
        var personParent: [Int: (movie: SixDegreesMovie, role: SixDegreesRole)] = [:]
        var movieParent: [String: (person: SixDegreesPerson, role: SixDegreesRole)] = [:]
        var visitedPeople = Set<Int>()
        var visitedMovies = Set<String>([left.stableID])

        /// 从命中的人物回溯到起点，拼出「片—人—片—…—目标片」路径。
        func pathFrom(_ startPerson: SixDegreesPerson, roleIntoRight: SixDegreesRole) -> SixDegreesPath {
            // 回溯收集（逆序）：人物链、各自「来自上一部片」的角色、经人物连入的作品。
            var peopleRev: [SixDegreesPerson] = []
            var rolesFromMovieRev: [SixDegreesRole] = []
            var rolesIntoMovieRev: [SixDegreesRole] = []
            var moviesRev: [SixDegreesMovie] = []

            var current = startPerson
            while true {
                guard let parent = personParent[current.id] else { break }
                peopleRev.append(current)
                rolesFromMovieRev.append(parent.role)
                if parent.movie.stableID == left.stableID { break }
                guard let via = movieParent[parent.movie.stableID] else { break }
                rolesIntoMovieRev.append(via.role)
                moviesRev.append(parent.movie)
                current = via.person
            }

            let people = Array(peopleRev.reversed())
            let rolesFromMovie = Array(rolesFromMovieRev.reversed())
            let rolesIntoMovie = Array(rolesIntoMovieRev.reversed())
            let movies = Array(moviesRev.reversed())

            var nodes: [SixDegreesPathNode] = [.movie(leftGraph.movie)]
            var links: [String] = []
            for (index, person) in people.enumerated() {
                links.append("\(person.name) \(rolesFromMovie[index].rawValue)")
                nodes.append(.person(person))
                if index < movies.count {
                    nodes.append(.movie(movies[index]))
                    links.append("\(person.name) \(rolesIntoMovie[index].fromPerson)")
                }
            }
            nodes.append(.movie(rightGraph.movie))
            links.append("\(startPerson.name) \(roleIntoRight.fromPerson)")
            return SixDegreesPath(nodes: nodes, links: links)
        }

        // 2. BFS：frontier 是待扩展的作品（已带图），逐层「片 → 人 → 片」。
        var frontier: [(movie: SixDegreesMovie, graph: SixDegreesMovieGraph)] = [(leftGraph.movie, leftGraph)]
        var depth = 0

        while depth < budget.maxIntermediatePeople, !frontier.isEmpty {
            // 2a. 从当前层的作品收集人物；命中目标片演职员集即成路。
            var nextPeople: [SixDegreesPerson] = []
            for (movie, graph) in frontier {
                for (person, role) in graph.people {
                    guard visitedPeople.insert(person.id).inserted else { continue }
                    personParent[person.id] = (movie, role)
                    if let roleIntoRight = rightPeople[person.id] {
                        return .found(pathFrom(person, roleIntoRight: roleIntoRight))
                    }
                    nextPeople.append(person)
                }
            }
            onProgress?(
                await session.exploredMovies,
                await session.exploredPeople
            )

            // 2b. 人物 → 作品（并发拉影人图谱，按预算截断）。
            let remainingForPeople = max(0, budget.maxRequests - (await session.requests))
            let allowedPeople = Array(nextPeople.prefix(remainingForPeople))
            guard !allowedPeople.isEmpty else { break }
            let personGraphs = await withTaskGroup(of: (Int, SixDegreesPersonGraph?).self) { group in
                for (index, person) in allowedPeople.enumerated() {
                    group.addTask { (index, await session.loadPerson(person)) }
                }
                var results = [SixDegreesPersonGraph?](repeating: nil, count: allowedPeople.count)
                for await (index, graph) in group {
                    results[index] = graph
                }
                return results
            }

            var nextFrontier: [SixDegreesMovie] = []
            for (index, personGraph) in personGraphs.enumerated() {
                guard let personGraph else { continue }
                let person = allowedPeople[index]
                // 同一部片「出演」优先于「参与制作」。
                var roleByStableID: [String: SixDegreesRole] = [:]
                var ordered: [SixDegreesMovie] = []
                let candidates = personGraph.acted.map { ($0, SixDegreesRole.acting) }
                    + personGraph.crewed.map { ($0, SixDegreesRole.crewing) }
                for (film, role) in candidates {
                    if let existing = roleByStableID[film.stableID] {
                        if existing == .crewing && role == .acting {
                            roleByStableID[film.stableID] = .acting
                        }
                    } else {
                        roleByStableID[film.stableID] = role
                        ordered.append(film)
                    }
                }

                for film in ordered {
                    guard visitedMovies.insert(film.stableID).inserted else { continue }
                    movieParent[film.stableID] = (person, roleByStableID[film.stableID] ?? .crewing)
                    if film.stableID == rightID {
                        let via = movieParent[rightID]!
                        return .found(pathFrom(via.person, roleIntoRight: via.role))
                    }
                    nextFrontier.append(film)
                }
            }
            onProgress?(
                await session.exploredMovies,
                await session.exploredPeople
            )

            // 2c. 作品 → 人物（并发拉作品图谱，按预算截断）。
            let remainingForMovies = max(0, budget.maxRequests - (await session.requests))
            let allowedMovies = Array(nextFrontier.prefix(remainingForMovies))
            guard !allowedMovies.isEmpty else { break }
            let movieGraphs = await withTaskGroup(of: (Int, SixDegreesMovieGraph?).self) { group in
                for (index, movie) in allowedMovies.enumerated() {
                    group.addTask { (index, await session.loadMovie(movie)) }
                }
                var results = [SixDegreesMovieGraph?](repeating: nil, count: allowedMovies.count)
                for await (index, graph) in group {
                    results[index] = graph
                }
                return results
            }
            frontier = zip(allowedMovies, movieGraphs).compactMap { movie, graph in
                graph.map { (movie, $0) }
            }
            depth += 1
        }

        try await session.rethrowIfTotallyFailed()
        return .notFound(
            exploredMovies: await session.exploredMovies,
            exploredPeople: await session.exploredPeople
        )
    }

    /// 取数会话：请求预算与探索计数都收在 actor 里，供任务组并发安全地调用。
    private actor SearchSession {
        let fetcher: any SixDegreesFetching
        let budget: Budget
        private(set) var requests = 0
        private(set) var exploredMovies = 0
        private(set) var exploredPeople = 0
        private(set) var lastError: (any Error)?

        init(fetcher: any SixDegreesFetching, budget: Budget) {
            self.fetcher = fetcher
            self.budget = budget
        }

        /// 拉一部片的图谱；预算耗尽或失败返回 nil（失败记为死路，不中断整层）。
        func loadMovie(_ movie: SixDegreesMovie) async -> SixDegreesMovieGraph? {
            guard requests < budget.maxRequests else { return nil }
            requests += 1
            do {
                let graph = try await fetcher.movieGraph(id: movie.id, mediaKind: movie.mediaKind)
                exploredMovies += 1
                return graph
            } catch {
                lastError = error
                return nil
            }
        }

        /// 拉一位影人的图谱。
        func loadPerson(_ person: SixDegreesPerson) async -> SixDegreesPersonGraph? {
            guard requests < budget.maxRequests else { return nil }
            requests += 1
            do {
                let graph = try await fetcher.personGraph(id: person.id)
                exploredPeople += 1
                return graph
            } catch {
                lastError = error
                return nil
            }
        }

        /// 一次成功取数都没有（断网等）时抛出最后一个错误，交给界面显示可重试横幅。
        func rethrowIfTotallyFailed() throws {
            if exploredMovies == 0 && exploredPeople == 0, let lastError {
                throw lastError
            }
        }
    }
}
