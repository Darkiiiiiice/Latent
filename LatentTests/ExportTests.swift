import Foundation
import Testing
@testable import Latent

/// 导出（设计文档第 8.9 节 / 第 11 节）。
@Suite("导出")
struct ExportTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_726_000_000)

    private func snapshot(
        kind: MediaKind = .movie,
        id: Int = 157336,
        title: String = "星际穿越",
        originalTitle: String? = "Interstellar",
        year: Int? = 2014,
        rating: Double? = 8.7,
        addedAt: Date? = nil
    ) -> LibrarySnapshot {
        LibrarySnapshot(
            mediaKind: kind,
            tmdbID: id,
            title: title,
            originalTitle: originalTitle,
            year: year,
            posterPath: "/poster.jpg",
            voteAverage: rating,
            addedAt: addedAt ?? fixedDate
        )
    }

    @Test("JSON：范围、TMDB ID、ISO 8601 时间")
    func json() throws {
        let export = LibraryExportBuilder.build(
            scope: .favorites,
            favorites: [snapshot()],
            watchlist: [snapshot(kind: .tv, id: 1396, title: "绝命毒师", originalTitle: "Breaking Bad")],
            history: [snapshot(id: 27205, title: "盗梦空间")],
            language: "zh-CN",
            exportedAt: fixedDate
        )

        let data = try LibraryExportBuilder.jsonData(export)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LibraryExport.self, from: data)

        #expect(decoded.scope == "favorites")
        #expect(decoded.language == "zh-CN")
        #expect(decoded.favorites.count == 1)
        #expect(decoded.watchlist.isEmpty)
        #expect(decoded.history.isEmpty)
        #expect(decoded.favorites.first?.tmdbID == 157336)
        #expect(decoded.favorites.first?.mediaType == "movie")
        #expect(decoded.favorites.first?.posterURL == "https://image.tmdb.org/t/p/w342/poster.jpg")
        #expect(decoded.favorites.first?.addedAt == fixedDate)
        #expect(decoded.favorites.first?.viewedAt == nil)

        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(raw.contains("\"schemaVersion\" : 1"))
        #expect(raw.contains("\"tmdbID\" : 157336"))
    }

    @Test("全部范围：三条分区都写入")
    func allScope() throws {
        let export = LibraryExportBuilder.build(
            scope: .all,
            favorites: [snapshot()],
            watchlist: [snapshot(kind: .tv, id: 1396, title: "绝命毒师")],
            history: [snapshot(id: 27205, title: "盗梦空间")],
            language: "zh-CN",
            exportedAt: fixedDate
        )
        let data = try LibraryExportBuilder.jsonData(export)
        let decoded = try JSONDecoder.iso8601.decode(LibraryExport.self, from: data)
        #expect(decoded.favorites.count == 1)
        #expect(decoded.watchlist.count == 1)
        #expect(decoded.history.count == 1)
        #expect(decoded.history.first?.viewedAt == fixedDate)
        #expect(decoded.history.first?.addedAt == nil)
    }

    @Test("Markdown：分区、★ / 未勾选清单、TMDB 链接")
    func markdown() {
        let calendar = Calendar(identifier: .gregorian).withTimeZone(UTC)
        let export = LibraryExportBuilder.build(
            scope: .all,
            favorites: [snapshot()],
            watchlist: [snapshot(kind: .tv, id: 1396, title: "绝命毒师", originalTitle: "Breaking Bad")],
            history: [snapshot(id: 27205, title: "盗梦空间")],
            language: "zh-CN",
            exportedAt: fixedDate
        )
        let text = LibraryExportBuilder.markdown(export, calendar: calendar)

        #expect(text.hasPrefix("# 显影 · 全部库"))
        #expect(text.contains("## 收藏（1）"))
        #expect(text.contains("## 观看清单（1）"))
        #expect(text.contains("## 浏览历史（1）"))
        #expect(text.contains("★ **星际穿越**（2014） · 电影 · ★ 8.7"))
        #expect(text.contains("- [ ] **绝命毒师**"))
        #expect(text.contains("[TMDB 1396](https://www.themoviedb.org/tv/1396)"))
        #expect(text.contains("原名 Breaking Bad"))
        #expect(text.contains("查看于 2024-09-"))
    }

    @Test("Markdown：标题特殊字符转义")
    func markdownEscaping() {
        let calendar = Calendar(identifier: .gregorian).withTimeZone(UTC)
        let export = LibraryExportBuilder.build(
            scope: .favorites,
            favorites: [snapshot(title: "A [B] *C*", originalTitle: nil)],
            watchlist: [],
            history: [],
            language: "zh-CN",
            exportedAt: fixedDate
        )
        let text = LibraryExportBuilder.markdown(export, calendar: calendar)
        #expect(text.contains("**A \\[B\\] \\*C\\***"))
    }

    @Test("空状态：JSON 数组为空，Markdown 不产生空分区")
    func empty() throws {
        let export = LibraryExportBuilder.build(
            scope: .watchlist,
            favorites: [snapshot()],
            watchlist: [],
            history: [snapshot()],
            language: "zh-CN",
            exportedAt: fixedDate
        )
        let data = try LibraryExportBuilder.jsonData(export)
        let decoded = try JSONDecoder.iso8601.decode(LibraryExport.self, from: data)
        #expect(decoded.favorites.isEmpty)
        #expect(decoded.watchlist.isEmpty)
        #expect(decoded.history.isEmpty)
        #expect(decoded.scope == "watchlist")

        let calendar = Calendar(identifier: .gregorian).withTimeZone(UTC)
        let text = LibraryExportBuilder.markdown(export, calendar: calendar)
        #expect(!text.contains("## 收藏"))
        #expect(!text.contains("## 观看清单"))
        #expect(!text.contains("## 浏览历史"))
    }

    @Test("默认文件名：范围 + yyyy-MM-dd")
    func filename() {
        let name = LibraryExportBuilder.suggestedFilename(scope: .history, format: .markdown, date: fixedDate)
        #expect(name.hasPrefix("显影-历史-"))
        #expect(name.count == "显影-历史-yyyy-MM-dd".count)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Calendar {
    func withTimeZone(_ zone: TimeZone) -> Calendar {
        var copy = self
        copy.timeZone = zone
        return copy
    }
}

private let UTC = TimeZone(secondsFromGMT: 0)!
