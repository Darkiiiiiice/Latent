import Foundation

/// 截图识别 → 作品匹配（v1.16）。
///
/// 纯逻辑 + 依赖注入 client：把 OCR 出来的行文本挑成查询词，逐条查 TMDB
/// `/search/multi`，再按「标题相似度 + 年份一致」给候选打分排序。
/// 最高分明显胜出就直接跳详情页，否则把候选交给用户挑。
enum OCRSearchMatcher {

    /// 一条候选：命中结果 + 分数 + 命中它的那行文字。
    struct Candidate: Sendable, Identifiable, Equatable {
        var result: SearchResult
        var score: Double
        var matchedQuery: String

        var id: String { result.id }
    }

    enum Outcome: Sendable, Equatable {
        /// 图里没有可用于搜索的文字。
        case empty
        /// 最高匹配明显胜出，直接打开。
        case matched(Candidate)
        /// 有多个相近候选，交给用户挑。
        case candidates([Candidate])
    }

    /// 自动跳转的分数下限。
    static let autoOpenScore = 0.9
    /// 自动跳转要求「第一名领先第二名」的最小差值。
    static let autoOpenMargin = 0.12
    /// 单次识别最多拿前几行去查（控制请求量）。
    static let defaultQueryLimit = 6

    // MARK: - 入口

    static func match(
        lines: [String],
        client: any TMDBClientProtocol,
        queryLimit: Int = defaultQueryLimit
    ) async -> Outcome {
        let queries = queries(from: lines, limit: queryLimit)
        guard !queries.isEmpty else { return .empty }

        let hint = yearHint(from: lines)
        var best: [String: Candidate] = [:]

        for query in queries {
            // 单条查询失败（断网 / 限流）不影响其余行，继续尝试。
            guard let paged = try? await client.searchMulti(query: query, page: 1) else { continue }
            for result in paged.items {
                let candidate = candidate(for: result, query: query, year: hint)
                if let existing = best[candidate.id], existing.score >= candidate.score { continue }
                best[candidate.id] = candidate
            }
        }

        let ranked = best.values
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let left = voteCount(of: lhs.result) ?? 0
                let right = voteCount(of: rhs.result) ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
        .prefix(12)

        guard let top = ranked.first else { return .empty }
        let runnerUp = ranked.dropFirst().first?.score ?? 0
        if top.score >= autoOpenScore, top.score - runnerUp >= autoOpenMargin {
            return .matched(top)
        }
        return .candidates(Array(ranked))
    }

    // MARK: - 从 OCR 行里挑查询词

    /// 把行文本过滤成可查询的词条：去空行、去纯数字 / 纯符号、去超长行（多半是简介），
    /// 去重后取前 `limit` 条。
    static func queries(from lines: [String], limit: Int = defaultQueryLimit) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in lines {
            let text = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{3000}", with: " ")
            guard (2...40).contains(text.count) else { continue }
            // 纯数字（年份 / 评分 / 时长）与纯符号不构成片名。
            guard text.contains(where: { $0.isLetter }) else { continue }
            guard !text.lowercased().contains("http") else { continue }

            let key = text.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(text)
            if result.count >= limit { break }
        }
        return result
    }

    /// 从全部行里找第一个 1900–2100 的年份，作为年份线索。
    static func yearHint(from lines: [String]) -> Int? {
        for line in lines {
            var digits = ""
            for character in line {
                if character.isNumber {
                    digits.append(character)
                    if digits.count == 4, let value = Int(digits), (1900...2100).contains(value) {
                        return value
                    }
                } else {
                    digits = ""
                }
            }
        }
        return nil
    }

    // MARK: - 打分

    private static func candidate(for result: SearchResult, query: String, year: Int?) -> Candidate {
        let title: String
        let originalTitle: String?
        let itemYear: Int?

        switch result {
        case .movie(let item), .tv(let item):
            title = item.title
            originalTitle = item.originalTitle
            itemYear = item.year
        case .person(let person):
            title = person.name
            originalTitle = nil
            itemYear = nil
        }

        return Candidate(
            result: result,
            score: score(title: title, originalTitle: originalTitle, year: itemYear, query: query, hint: year),
            matchedQuery: query
        )
    }

    /// 标题相似度（0…1）+ 年份一致加成 / 冲突扣分。
    static func score(
        title: String,
        originalTitle: String?,
        year: Int?,
        query: String,
        hint: Int?
    ) -> Double {
        let similarity = max(
            titleSimilarity(query, title),
            originalTitle.map { titleSimilarity(query, $0) } ?? 0
        )
        var score = similarity
        if let hint, let year {
            score += hint == year ? 0.15 : -0.2
        }
        return min(1.15, max(0, score))
    }

    /// 归一化后的相似度：完全一致 1.0；包含关系 0.6–0.9；否则按词 / 字二元组重合度。
    static func titleSimilarity(_ query: String, _ title: String) -> Double {
        let q = normalize(query)
        let t = normalize(title)
        guard !q.isEmpty, !t.isEmpty else { return 0 }
        if q == t { return 1.0 }
        if t.contains(q) || q.contains(t) {
            let ratio = Double(min(q.count, t.count)) / Double(max(q.count, t.count))
            return 0.6 + 0.3 * ratio
        }
        return jaccard(tokens(query), tokens(title))
    }

    /// 只留有意义的字符（字母 / 数字 / 汉字），统一小写。
    private static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 拉丁文本按词切（词数 > 1 时）；中文 / 单词按字符二元组切。
    private static func tokens(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { $0.count > 1 }
        if words.count > 1 { return Set(words) }

        let characters = Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
        guard characters.count > 1 else { return Set(characters.map(String.init)) }
        var grams = Set<String>()
        for index in 0..<(characters.count - 1) {
            grams.insert(String(characters[index...index + 1]))
        }
        return grams
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        return Double(intersection) / Double(union)
    }

    private static func voteCount(of result: SearchResult) -> Int? {
        switch result {
        case .movie(let item), .tv(let item): return item.voteCount
        case .person: return nil
        }
    }
}
