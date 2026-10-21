import Foundation
import Testing
@testable import Latent

/// 截图识别匹配（v1.16，设计文档第 11 节）。
@Suite("截图识别匹配")
struct OCRSearchMatcherTests {

    // MARK: - 挑词与年份

    @Test("挑词：去空行 / 纯数字 / 纯符号 / 超长行，去重且保序")
    func queryExtraction() {
        let longLine = String(repeating: "简介", count: 30)
        let lines = [
            "",
            "   ",
            "沙丘：第二部",
            "2024",
            "8.1",
            longLine,
            "沙丘：第二部",
            "Dune: Part Two",
            "★★★",
        ]
        #expect(OCRSearchMatcher.queries(from: lines) == ["沙丘：第二部", "Dune: Part Two"])
    }

    @Test("挑词上限：默认 6 条，可显式收紧")
    func queryLimit() {
        let lines = (1...10).map { "作品 \($0)" }
        #expect(OCRSearchMatcher.queries(from: lines).count == OCRSearchMatcher.defaultQueryLimit)
        #expect(OCRSearchMatcher.queries(from: lines, limit: 2).count == 2)
    }

    @Test("年份线索：取第一个 1900–2100 的四年数字")
    func yearHint() {
        #expect(OCRSearchMatcher.yearHint(from: ["沙丘", "上映 2024-03-01"]) == 2024)
        #expect(OCRSearchMatcher.yearHint(from: ["2024", "1994"]) == 2024)
        // 评分 8.1 / 166 分钟都不该被当成年份
        #expect(OCRSearchMatcher.yearHint(from: ["评分 8.1", "共 166 分钟"]) == nil)
    }

    // MARK: - 打分

    @Test("相似度：完全一致 > 包含 > 无关")
    func similarity() {
        #expect(OCRSearchMatcher.titleSimilarity("沙丘：第二部", "沙丘：第二部") == 1.0)

        let contained = OCRSearchMatcher.titleSimilarity("沙丘", "沙丘：第二部")
        #expect(contained > 0.6)
        #expect(contained < 1.0)

        #expect(OCRSearchMatcher.titleSimilarity("星际穿越", "沙丘：第二部") == 0)
        #expect(OCRSearchMatcher.titleSimilarity("Dune: Part Two", "dune part two") == 1.0)
    }

    @Test("年份一致加分、冲突扣分")
    func yearAdjustment() {
        let base = OCRSearchMatcher.score(
            title: "沙丘：第二部", originalTitle: nil, year: 2024, query: "沙丘：第二部", hint: nil
        )
        #expect(abs(base - 1.0) < 0.0001)

        let agree = OCRSearchMatcher.score(
            title: "沙丘：第二部", originalTitle: nil, year: 2024, query: "沙丘：第二部", hint: 2024
        )
        #expect(abs(agree - 1.15) < 0.0001)

        let conflict = OCRSearchMatcher.score(
            title: "沙丘：第二部", originalTitle: nil, year: 2024, query: "沙丘：第二部", hint: 2020
        )
        #expect(abs(conflict - 0.8) < 0.0001)
    }

    // MARK: - 端到端匹配

    @Test("片名 + 年份都一致：直接命中")
    func autoMatch() async {
        let outcome = await OCRSearchMatcher.match(lines: ["沙丘：第二部", "2024"], client: MockTMDBClient())
        guard case .matched(let candidate) = outcome else {
            Issue.record("应直接命中，实际为 \(outcome)")
            return
        }
        #expect(candidate.result == .movie(.sampleMovie(id: 1, title: "沙丘：第二部")))
        #expect(candidate.matchedQuery == "沙丘：第二部")
    }

    @Test("年份对不上：退回候选列表，按分数排序")
    func fallsBackToCandidates() async {
        var client = MockTMDBClient()
        client.searchPage = Paged(
            page: 1,
            items: [
                .movie(.sampleMovie(id: 1, title: "沙丘")),
                .movie(.sampleMovie(id: 2, title: "沙丘：第二部")),
            ],
            totalPages: 1,
            totalResults: 2
        )

        let outcome = await OCRSearchMatcher.match(lines: ["沙丘", "2020"], client: client)
        guard case .candidates(let list) = outcome else {
            Issue.record("应退回候选列表，实际为 \(outcome)")
            return
        }
        #expect(list.count == 2)
        #expect(list.first?.result == .movie(.sampleMovie(id: 1, title: "沙丘")))
        #expect((list.first?.score ?? 0) > (list.last?.score ?? 0))
    }

    @Test("人物也能命中")
    func personMatch() async {
        let outcome = await OCRSearchMatcher.match(lines: ["布拉德·皮特"], client: MockTMDBClient())
        guard case .matched(let candidate) = outcome else {
            Issue.record("应直接命中人物，实际为 \(outcome)")
            return
        }
        #expect(candidate.result == .person(
            PersonSummary(id: 287, name: "布拉德·皮特", knownForDepartment: "Acting")
        ))
    }

    @Test("图里没有可用文字：返回 empty，不发请求")
    func emptyLines() async {
        let outcome = await OCRSearchMatcher.match(lines: ["", "  ", "2024", "★★★"], client: MockTMDBClient())
        #expect(outcome == .empty)
    }

    @Test("搜索失败不崩，退化为 empty")
    func searchFailure() async {
        var client = MockTMDBClient()
        client.searchError = .offline
        let outcome = await OCRSearchMatcher.match(lines: ["沙丘"], client: client)
        #expect(outcome == .empty)
    }
}
