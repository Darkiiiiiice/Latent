import Foundation

/// 一句话筛选解析（设计文档第 8 节「自然语言筛选」）。
///
/// 纯本地规则引擎：不依赖端上模型、不联网、0 第三方依赖，断网可用。
/// 把「90 分钟以内的科幻片」「评分 8 分以上、2020 年后的动作片」这类句子
/// 解析成 `DiscoverQuery`，供发现页直接套用。
///
/// 覆盖范围（其余说法一律忽略，不做猜测）：
/// - 类型：TMDB 中文类型名 + 常见别名 / 英文名（`科幻片`、`搞笑`、`sci-fi` …）
/// - 年份：`2023 年`、`2020 年后`、`2019 年以前`、`90 年代`、`2020-2024`、`近年`
/// - 评分：`8 分以上`、`评分 8`、`低于 6 分`、`高分`、`烂片`
/// - 时长：`90 分钟以内`、`两小时以内`、`一个半小时`、`短片`
/// - 平台：已加载平台清单的名称或常见中文别名（`网飞`、`爱奇艺`、`B 站` …）
/// - 排序：`高分`、`最新的`、`经典老片`、`票房`、`热门`
/// - 作品类型：`剧集 / 电视剧 / 美剧` → 剧集，`电影 / 影片` → 电影
enum NLQueryParser {

    /// 解析结果。
    struct Result: Sendable, Equatable {
        /// 套用后的筛选条件（未提及的条件保持传入值不变）。
        var query: DiscoverQuery
        /// 命中条件的可读描述，按类型 → 年份 → 评分 → 时长 → 平台 → 排序排列。
        var matched: [String]
        /// 句子里出现的作品类型；没提则为 nil。
        var mediaKind: MediaKind?

        var isEmpty: Bool { matched.isEmpty }
    }

    /// 解析入口。
    ///
    /// - Parameters:
    ///   - text: 用户输入的一句话。
    ///   - genres: 当前作品类型对应的 TMDB 类型表（用于把中文类型名映射成 ID）。
    ///   - providers: 当前地区已加载的平台清单。
    ///   - base: 基础条件；未在句子里出现的条件保持 `base` 的值。
    ///   - mediaKind: 当前作品类型，决定 `with_runtime` 是否下发。
    static func parse(
        _ text: String,
        genres: [Genre],
        providers: [WatchProvider],
        base: DiscoverQuery = DiscoverQuery(),
        mediaKind: MediaKind = .movie
    ) -> Result {
        var query = base
        var matched: [String] = []

        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return Result(query: query, matched: [], mediaKind: nil)
        }

        let detectedKind = detectMediaKind(normalized)
        let effectiveKind = detectedKind ?? mediaKind

        // 1) 类型（命中即替换原选择；未提及则保持）
        let genreIDs = matchGenres(normalized, genres: genres)
        if !genreIDs.isEmpty {
            query.genreIDs = genreIDs
            let names = genreIDs.sorted().map { id in
                genres.first(where: { $0.id == id })?.name ?? "类型\(id)"
            }
            matched.append(names.joined(separator: "+"))
        }

        // 2) 年份
        if let year = matchYear(normalized) {
            switch year {
            case let .range(from, to):
                query.yearFrom = from
                query.yearTo = to
                matched.append(from == to ? "\(from) 年" : "\(from)–\(to)")
            case let .from(from):
                query.yearFrom = from
                query.yearTo = nil
                matched.append("\(from) 年后")
            case let .to(to):
                query.yearFrom = nil
                query.yearTo = to
                matched.append("\(to) 年前")
            }
        }

        // 3) 评分
        if let rating = matchRating(normalized) {
            switch rating {
            case let .atLeast(value):
                query.minRating = value
                matched.append("评分 ≥\(trimTrailingZero(value))")
            case let .atMost(value):
                query.maxRating = value
                matched.append("评分 ≤\(trimTrailingZero(value))")
            }
        }

        // 4) 时长（TMDB 只对电影支持 `with_runtime`）
        if let minutes = matchRuntime(normalized) {
            query.maxRuntime = minutes
            matched.append(effectiveKind == .movie ? "≤\(minutes) 分钟" : "≤\(minutes) 分钟（剧集不支持按时长筛选）")
        }

        // 5) 平台
        let providerIDs = matchProviders(normalized, providers: providers)
        if !providerIDs.isEmpty {
            query.providerIDs = providerIDs
            let names = providerIDs.sorted().compactMap { id in
                providers.first(where: { $0.id == id })?.providerName
            }
            matched.append(names.joined(separator: "+"))
        }

        // 6) 排序
        if let sort = matchSort(normalized) {
            query.sortBy = sort
            matched.append(sort.label)
        }

        return Result(query: query, matched: matched, mediaKind: detectedKind)
    }

    // MARK: - 类型

    private static func matchGenres(_ text: String, genres: [Genre]) -> Set<Int> {
        var ids = Set<Int>()

        // ① TMDB 中文类型名直接命中
        for genre in genres where text.contains(genre.name.lowercased()) {
            ids.insert(genre.id)
        }

        // ② 别名 / 英文名 → 目标类型名 → 再查表
        for (alias, target) in genreAliases where text.contains(alias) {
            let needle = target.lowercased()
            for genre in genres {
                let name = genre.name.lowercased()
                if name == needle || name.contains(needle) || needle.contains(name) {
                    ids.insert(genre.id)
                }
            }
        }
        return ids
    }

    /// 别名词表：键为句子里的说法，值为 TMDB 类型名（或其片段）。
    private static let genreAliases: [(String, String)] = [
        ("科幻片", "科幻"), ("恐怖片", "恐怖"), ("动作片", "动作"), ("爱情片", "爱情"),
        ("喜剧片", "喜剧"), ("剧情片", "剧情"), ("战争片", "战争"), ("悬疑片", "悬疑"),
        ("惊悚片", "惊悚"), ("犯罪片", "犯罪"), ("动画片", "动画"), ("奇幻片", "奇幻"),
        ("冒险片", "冒险"), ("纪录片", "纪录片"), ("音乐片", "音乐"), ("历史片", "历史"),
        ("家庭片", "家庭"), ("西部片", "西部"), ("武侠", "动作"), ("武打", "动作"),
        ("打斗", "动作"), ("搞笑", "喜剧"), ("爆笑", "喜剧"), ("逗笑", "喜剧"),
        ("谈情", "爱情"), ("探案", "犯罪"), ("破案", "犯罪"), ("悬案", "悬疑"),
        ("科幻", "科幻"), ("惊悚", "惊悚"), ("犯罪", "犯罪"), ("动画", "动画"),
        ("sci-fi", "科幻"), ("science fiction", "科幻"), ("action", "动作"),
        ("comedy", "喜剧"), ("drama", "剧情"), ("horror", "恐怖"), ("thriller", "惊悚"),
        ("animation", "动画"), ("animated", "动画"), ("documentary", "纪录片"),
        ("crime", "犯罪"), ("adventure", "冒险"), ("fantasy", "奇幻"),
        ("mystery", "悬疑"), ("romance", "爱情"), ("war", "战争"), ("family", "家庭"),
        ("history", "历史"), ("music", "音乐"),
    ]

    // MARK: - 作品类型

    private static func detectMediaKind(_ text: String) -> MediaKind? {
        let tvWords = ["剧集", "电视剧", "连续剧", "美剧", "英剧", "日剧", "韩剧", "番剧", "综艺"]
        let movieWords = ["电影", "影片", "大片", "院线"]
        if tvWords.contains(where: { text.contains($0) }) { return .tv }
        if movieWords.contains(where: { text.contains($0) }) { return .movie }
        return nil
    }

    // MARK: - 年份

    private enum YearMatch {
        case range(Int, Int)
        case from(Int)
        case to(Int)
    }

    private static func matchYear(_ text: String) -> YearMatch? {
        let tokens = numberTokens(in: text)
        let yearTokens = tokens.filter { $0.isInteger && (1900...2100).contains(Int($0.value)) }

        // ① 四位数区间：2020-2024 / 2020 到 2024 / 2020 年至 2024 年
        if yearTokens.count >= 2 {
            let first = yearTokens[0]
            let second = yearTokens[1]
            let between = String(text[first.range.upperBound..<second.range.lowerBound])
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "年", with: "")
            let separators = ["", "-", "–", "—", "~", "～", "到", "至", ","]
            if separators.contains(between) {
                let low = min(Int(first.value), Int(second.value))
                let high = max(Int(first.value), Int(second.value))
                return .range(low, high)
            }
        }

        // ② 单个四位数 + 后缀
        if let token = yearTokens.first {
            let value = Int(token.value)
            let tail = String(text[token.range.upperBound...].prefix(6))
                .replacingOccurrences(of: " ", with: "")

            if tail.hasPrefix("年代") {
                let decade = (value / 10) * 10
                return .range(decade, decade + 9)
            }
            if tail.hasPrefix("年后") || tail.hasPrefix("年以后") || tail.hasPrefix("年之后") || tail.hasPrefix("年以来") {
                return .from(value)
            }
            if tail.hasPrefix("年前") || tail.hasPrefix("年以前") || tail.hasPrefix("年之前") {
                return .to(value)
            }
            if tail.hasPrefix("年") {
                return .range(value, value)
            }
            if tail.hasPrefix("后") || tail.hasPrefix("以后") || tail.hasPrefix("以来") {
                return .from(value)
            }
            if tail.hasPrefix("前") || tail.hasPrefix("以前") {
                return .to(value)
            }
        }

        // ③ 两位数年代：90 年代 / 00 年代
        if let token = tokens.first(where: { $0.isInteger && (0...99).contains(Int($0.value)) }) {
            let tail = String(text[token.range.upperBound...].prefix(3))
                .replacingOccurrences(of: " ", with: "")
            if tail.hasPrefix("年代") {
                let raw = Int(token.value)
                let decade = raw >= 30 ? 1900 + raw : 2000 + raw
                return .range(decade, decade + 9)
            }
        }

        // ④ 相对时间
        if ["近年", "最近几年", "这几年", "近几年"].contains(where: { text.contains($0) }) {
            return .from(Calendar.current.component(.year, from: Date()) - 3)
        }
        return nil
    }

    // MARK: - 评分

    private enum RatingMatch {
        case atLeast(Double)
        case atMost(Double)
    }

    private static func matchRating(_ text: String) -> RatingMatch? {
        for token in numberTokens(in: text) {
            guard (0...10).contains(token.value) else { continue }

            let start = text.index(token.range.lowerBound, offsetBy: -6, limitedBy: text.startIndex) ?? text.startIndex
            let before = String(text[start..<token.range.lowerBound]).replacingOccurrences(of: " ", with: "")
            let after = String(text[token.range.upperBound...].prefix(6)).replacingOccurrences(of: " ", with: "")

            let mentionsScore = before.contains("评分") || before.contains("分数") || before.contains("打分")
            // 「分钟」不是「分」——否则「5 分钟以内」会被误判成评分上限。
            let hasScoreUnit = after.hasPrefix("分") && !after.hasPrefix("分钟")
            let wantsHigher = hasScoreUnit && (after.contains("以上") || after.contains("及以上")
                || after.contains("起") || after.contains("+"))
            let wantsLower = hasScoreUnit && (after.contains("以下") || after.contains("以内"))
            let explicitHigher = ["高于", "超过", "至少", "不低于", "不小于"].contains(where: { before.contains($0) })
            let explicitLower = ["低于", "少于", "不超过", "不大于"].contains(where: { before.contains($0) })

            guard mentionsScore || wantsHigher || wantsLower || explicitHigher || explicitLower else { continue }
            return (wantsLower || explicitLower) ? .atMost(token.value) : .atLeast(token.value)
        }

        if ["高分", "好评", "口碑好", "评分高"].contains(where: { text.contains($0) }) {
            return .atLeast(7.5)
        }
        if ["低分", "烂片", "评分低"].contains(where: { text.contains($0) }) {
            return .atMost(5.0)
        }
        return nil
    }

    // MARK: - 时长

    private static func matchRuntime(_ text: String) -> Int? {
        for token in numberTokens(in: text) {
            let after = String(text[token.range.upperBound...].prefix(4)).replacingOccurrences(of: " ", with: "")
            if after.hasPrefix("小时") || after.hasPrefix("钟头") {
                let minutes = Int((token.value * 60).rounded())
                if (10...600).contains(minutes) { return minutes }
            }
            if after.hasPrefix("分钟") || after.hasPrefix("min") {
                let minutes = Int(token.value.rounded())
                if (10...600).contains(minutes) { return minutes }
            }
        }
        if ["短片", "短一点", "别太长", "不要太长"].contains(where: { text.contains($0) }) {
            return 100
        }
        return nil
    }

    // MARK: - 平台

    private static func matchProviders(_ text: String, providers: [WatchProvider]) -> Set<Int> {
        var ids = Set<Int>()
        for provider in providers {
            let name = provider.providerName.lowercased()
            let aliasHit = providerAliases.contains { pair in
                text.contains(pair.0) && name.contains(pair.1)
            }
            if text.contains(name) || aliasHit {
                ids.insert(provider.id)
            }
        }
        return ids
    }

    /// 中文说法 → 平台英文名的片段（用于在已加载清单里找到对应平台）。
    private static let providerAliases: [(String, String)] = [
        ("网飞", "netflix"), ("奈飞", "netflix"),
        ("迪士尼", "disney"), ("迪斯尼", "disney"),
        ("苹果", "apple tv"), ("亚马逊", "amazon"),
        ("派拉蒙", "paramount"), ("爱奇艺", "iqiyi"),
        ("腾讯", "tencent"), ("优酷", "youku"),
        ("哔哩哔哩", "bilibili"), ("b站", "bilibili"), ("b 站", "bilibili"),
        ("芒果", "mango"), ("咪咕", "mgtv"), ("搜狐", "sohu"), ("西瓜", "xigua"),
    ]

    // MARK: - 排序

    private static func matchSort(_ text: String) -> DiscoverQuery.SortBy? {
        if ["票房", "卖座", "最赚钱"].contains(where: { text.contains($0) }) { return .revenue }
        if ["高分", "好评", "评分最高", "最受好评"].contains(where: { text.contains($0) }) { return .rating }
        if ["最新", "新片", "刚上映", "新一点的"].contains(where: { text.contains($0) }) { return .newest }
        if ["经典", "老片", "老的", "早一点"].contains(where: { text.contains($0) }) { return .oldest }
        if ["热门", "人气", "最火"].contains(where: { text.contains($0) }) { return .popularity }
        return nil
    }

    // MARK: - 文本归一化

    /// 小写化 + 全角空格归一 + 短语与中文数字改写，让后续规则只看「数字 + 关键词」。
    private static func normalize(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for (phrase, replacement) in numeralPhrases {
            result = result.replacingOccurrences(of: phrase, with: replacement)
        }
        return convertChineseNumerals(result)
    }

    /// 「一个半小时」这类整体短语先改写，避免中文数字转换把「个」切断。
    private static let numeralPhrases: [(String, String)] = [
        ("一个半小时", "1.5小时"), ("一个钟头", "1小时"), ("半个小时", "0.5小时"),
        ("半小时", "0.5小时"), ("一个小时", "1小时"), ("一个钟", "1小时"),
    ]

    /// 中文数字 → 阿拉伯数字（支持 十 / 百：「九十」→ 90、「一百二十」→ 120）。
    private static func convertChineseNumerals(_ text: String) -> String {
        let digitMap: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        ]
        let unitMap: [Character: Int] = ["十": 10, "百": 100]

        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard digitMap[character] != nil || unitMap[character] != nil else {
                output.append(character)
                index = text.index(after: index)
                continue
            }

            var section = 0
            var number = 0
            var cursor = index
            while cursor < text.endIndex {
                if let digit = digitMap[text[cursor]] {
                    number = digit
                } else if let unit = unitMap[text[cursor]] {
                    section += (number == 0 ? 1 : number) * unit
                    number = 0
                } else {
                    break
                }
                cursor = text.index(after: cursor)
            }
            output.append(String(section + number))
            index = cursor
        }
        return output
    }

    // MARK: - 数字分词

    private struct NumberToken {
        let value: Double
        let range: Range<String.Index>
        var isInteger: Bool { value == value.rounded() }
    }

    /// 找出文本里的阿拉伯数字（含小数），供各规则按上下文判断用途。
    private static func numberTokens(in text: String) -> [NumberToken] {
        var tokens: [NumberToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var seenDot = false
            while index < text.endIndex, text[index].isNumber || (text[index] == "." && !seenDot) {
                if text[index] == "." { seenDot = true }
                index = text.index(after: index)
            }
            if let value = Double(text[start..<index]) {
                tokens.append(NumberToken(value: value, range: start..<index))
            }
        }
        return tokens
    }

    private static func trimTrailingZero(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
