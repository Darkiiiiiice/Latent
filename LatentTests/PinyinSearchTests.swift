import Testing
@testable import Latent

/// 片库拼音搜索（v1.8，设计文档第 11 节）。
@Suite("拼音搜索")
struct PinyinSearchTests {

    @Test("全拼：连续、带空格、大小写不敏感")
    func fullPinyin() {
        #expect(PinyinSearch.matches(query: "liulangdiqiu", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "liu lang di qiu", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "LIULANGDIQIU", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "liulang", title: "流浪地球"))
    }

    @Test("首字母：从标题第一个字开始；全拼仍可匹配中间片段")
    func initials() {
        #expect(PinyinSearch.matches(query: "lldq", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "LLDQ", title: "流浪地球"))
        #expect(!PinyinSearch.matches(query: "ldq", title: "流浪地球"))
        #expect(!PinyinSearch.matches(query: "dq", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "diqiu", title: "流浪地球"))
    }

    @Test("中文与英文标题直接匹配；忽略空格、标点与大小写")
    func directTitles() {
        #expect(PinyinSearch.matches(query: "流浪", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "地球", title: "流浪地球"))
        #expect(PinyinSearch.matches(query: "spirited away", title: "Spirited Away"))
        #expect(PinyinSearch.matches(query: "SPIRITED", title: "Spirited Away"))
        #expect(PinyinSearch.matches(query: "spiderman", title: "Spider-Man: Across the Spider-Verse"))
        #expect(PinyinSearch.matches(query: "spider man", title: "Spider-Man: Across the Spider-Verse"))
    }

    @Test("原始标题参与匹配")
    func originalTitle() {
        #expect(
            PinyinSearch.matches(
                query: "everything everywhere",
                title: "瞬息全宇宙",
                originalTitle: "Everything Everywhere All at Once"
            )
        )
        #expect(
            PinyinSearch.matches(
                query: "shunxi",
                title: "瞬息全宇宙",
                originalTitle: "Everything Everywhere All at Once"
            )
        )
    }

    @Test("ü 同时接受 v 与 u")
    func umlaut() {
        #expect(PinyinSearch.matches(query: "lvpishu", title: "绿皮书"))
        #expect(PinyinSearch.matches(query: "lupishu", title: "绿皮书"))
        #expect(PinyinSearch.matches(query: "lüpishu", title: "绿皮书"))
        #expect(PinyinSearch.matches(query: "lv", title: "绿皮书"))
        #expect(PinyinSearch.matches(query: "nv", title: "女巫"))
    }

    @Test("多音字：系统两套转写取并集")
    func polyphones() {
        #expect(PinyinSearch.matches(query: "changan", title: "长安三万里"))
        #expect(PinyinSearch.matches(query: "zhangan", title: "长安三万里"))
        #expect(PinyinSearch.matches(query: "chongqing", title: "重庆森林"))
        #expect(PinyinSearch.matches(query: "cengshaonian", title: "曾少年"))
        #expect(PinyinSearch.matches(query: "zengshaonian", title: "曾少年"))
        #expect(PinyinSearch.matches(query: "jieyou", title: "解忧杂货店"))
        #expect(PinyinSearch.matches(query: "xieyou", title: "解忧杂货店"))
        #expect(PinyinSearch.matches(query: "danqin", title: "单亲妈妈"))
        #expect(PinyinSearch.matches(query: "shanqin", title: "单亲妈妈"))
    }

    @Test("不误命中；空查询不匹配")
    func noFalsePositives() {
        #expect(!PinyinSearch.matches(query: "lldq", title: "霸王别姬"))
        #expect(!PinyinSearch.matches(query: "batman", title: "流浪地球"))
        #expect(!PinyinSearch.matches(query: "", title: "流浪地球"))
        #expect(!PinyinSearch.matches(query: "   ", title: "流浪地球"))
        #expect(!PinyinSearch.matches(query: "lldq", title: ""))
    }

    @Test("拉丁查询判定：用于全局搜索的片库组")
    func latinQuery() {
        #expect(PinyinSearch.isLatinQuery("lldq"))
        #expect(PinyinSearch.isLatinQuery("liu lang"))
        #expect(PinyinSearch.isLatinQuery("Spider-Man"))
        #expect(!PinyinSearch.isLatinQuery("流浪"))
        #expect(!PinyinSearch.isLatinQuery("流浪diqiu"))
        #expect(!PinyinSearch.isLatinQuery("123"))
        #expect(!PinyinSearch.isLatinQuery(""))
    }
}
