import Testing
@testable import Latent

/// 片库多选纯函数（设计文档第 8.6 节，v1.7）。
@Suite("片库多选")
struct LibrarySelectionTests {

    @Test("点按切换与 ⇧ 区间选择")
    func toggleAndRange() {
        var selection = LibrarySelection.toggled("movie-1", in: [])
        #expect(selection == ["movie-1"])
        selection = LibrarySelection.toggled("movie-1", in: selection)
        #expect(selection.isEmpty)

        let order = ["movie-1", "tv-1", "movie-2", "movie-3"]
        #expect(
            LibrarySelection.range(from: "movie-1", through: "movie-2", in: order)
                == ["movie-1", "tv-1", "movie-2"]
        )
        #expect(
            LibrarySelection.range(from: "movie-3", through: "tv-1", in: order)
                == ["tv-1", "movie-2", "movie-3"]
        )
        // anchor 已失效时退化为只选 target
        #expect(
            LibrarySelection.range(from: "missing", through: "movie-2", in: order)
                == ["movie-2"]
        )
    }

    @Test("数据变化后裁掉失效 ID")
    func clampsStaleSelection() {
        let clamped = LibrarySelection.clamped(
            ["movie-1", "movie-404"],
            to: ["movie-1", "tv-2"]
        )
        #expect(clamped == ["movie-1"])
    }

    @Test("选择键含 mediaType：同 TMDB ID 的电影 / 剧集不冲突")
    func stableIDIncludesMediaKind() {
        let movie = MediaSummary(id: 693134, mediaKind: .movie, title: "电影")
        let tv = MediaSummary(id: 693134, mediaKind: .tv, title: "剧集")
        #expect(movie.stableID != tv.stableID)
    }
}
