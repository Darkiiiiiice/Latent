import Foundation

/// 片库拼音搜索（v1.8，设计文档第 3 / 8.6 / 14.6 节）。
///
/// 只依赖系统 `CFStringTransform`（0 第三方依赖）：
/// - 逐字使用 `Han-Latin` 与 `Han-Latin/Names` 两套转写，合并结果；
/// - 少量系统默认读音不符合片名的常见多音字（地 / 了 / 行 / 乐 / 重…）补一份
///   精简读音表，避免「地球」「银行」「音乐」这类词搜不到；
/// - 去音调、忽略大小写 / 空格 / 标点，生成「全拼」与「首字母」；
/// - `ü` 同时接受 `v` 与 `u`（`lvpishu` / `lupishu` 都能命中《绿皮书》）；
/// - 中文 / 英文标题仍走直接子串匹配，拼音只是额外的匹配面。
///
/// 读音按单字缓存；系统仍有个别词只给一种读音，这类词可直接输入中文标题。
enum PinyinSearch {

    /// 作品标题匹配：`title` 与 `originalTitle` 任一命中即可。
    static func matches(query: String, title: String, originalTitle: String? = nil) -> Bool {
        matches(query: query, in: [title, originalTitle])
    }

    /// 多候选标题匹配（空 / nil 候选自动跳过）。
    static func matches(query: String, in candidates: [String?]) -> Bool {
        let normalizedQuery = compact(fold(query))
        guard !normalizedQuery.isEmpty else { return false }

        let queryHasCJK = containsCJK(query)
        for candidate in candidates {
            guard let candidate, !candidate.isEmpty else { continue }
            let term = prepare(candidate)

            if term.direct.contains(normalizedQuery) {
                return true
            }
            // 中文查询没有对应的拉丁索引，直接子串已经覆盖。
            guard !queryHasCJK else { continue }
            if term.pinyin.contains(where: { $0.contains(normalizedQuery) }) {
                return true
            }
            if term.initials.contains(where: { $0.hasPrefix(normalizedQuery) }) {
                return true
            }
        }
        return false
    }

    /// 查询是否只含拉丁字母（不含中日韩字符）；全局搜索用它决定是否展示「片库」组。
    static func isLatinQuery(_ text: String) -> Bool {
        var hasLatin = false
        for scalar in text.unicodeScalars {
            if isCJK(scalar) { return false }
            if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                hasLatin = true
            }
        }
        return hasLatin
    }

    // MARK: - 内部

    private struct Term {
        let direct: String
        let pinyin: Set<String>
        let initials: Set<String>
    }

    private struct Token {
        let readings: [String]
    }

    private static func prepare(_ text: String) -> Term {
        let direct = compact(fold(text))
        guard containsCJK(text) else {
            // 纯拉丁 / 数字标题不需要转写；直接匹配即可。
            return Term(direct: direct, pinyin: [direct], initials: [])
        }

        let tokens = tokens(of: text)
        guard !tokens.isEmpty else {
            return Term(direct: direct, pinyin: [], initials: [])
        }

        var pinyin: Set<String> = []
        var initials: Set<String> = []
        for variant in variants(of: tokens) {
            pinyin.insert(variant.joined())
            let initial = variant.compactMap(\.first).map(String.init).joined()
            if !initial.isEmpty { initials.insert(initial) }
        }

        return Term(direct: direct, pinyin: pinyin, initials: initials)
    }

    /// 把标题拆成「有读音的片段」：汉字逐字取读音，拉丁 / 数字连续段保持原样，
    /// 空格与标点丢弃。这样繁体 / 简体、标点与副标题都不会打断匹配。
    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var latinRun = ""

        func flushLatinRun() {
            let normalized = compact(fold(latinRun))
            if !normalized.isEmpty {
                tokens.append(Token(readings: [normalized]))
            }
            latinRun = ""
        }

        for character in text {
            if let scalar = character.unicodeScalars.first, isCJK(scalar) {
                flushLatinRun()
                let readings = readings(for: character)
                if !readings.isEmpty {
                    tokens.append(Token(readings: readings))
                }
            } else if character.isLetter || character.isNumber {
                latinRun.append(character)
            } else {
                flushLatinRun()
            }
        }
        flushLatinRun()
        return tokens
    }

    /// 生成读音组合：基础读音 + 每个多音字的单字替换 + （数量不大时）完整组合。
    ///
    /// 完整组合上限 32，避免长标题里多个多音字导致笛卡尔积爆炸；单字替换已经覆盖
    /// 「只差一个多音字」的绝大多数查询。
    private static func variants(of tokens: [Token]) -> [[String]] {
        let base = tokens.map { $0.readings[0] }
        var result: [[String]] = [base]

        for (index, token) in tokens.enumerated() where token.readings.count > 1 {
            for reading in token.readings.dropFirst() {
                var variant = base
                variant[index] = reading
                result.append(variant)
            }
        }

        let combinationCount = tokens.reduce(1) { min(33, $0 * $1.readings.count) }
        if combinationCount <= 32 {
            var combinations: [[String]] = [[]]
            for token in tokens {
                combinations = combinations.flatMap { prefix in
                    token.readings.map { prefix + [$0] }
                }
            }
            result.append(contentsOf: combinations)
        }

        var seen: Set<String> = []
        return result.filter { seen.insert($0.joined(separator: "|")).inserted }
    }

    private static func readings(for character: Character) -> [String] {
        ReadingCache.shared.readings(for: character) {
            var set: Set<String> = []
            for transform in ["Han-Latin", "Han-Latin/Names"] {
                let marked = transliterate(String(character), transform: transform)
                addReadings(from: marked, to: &set)
            }
            if let extras = extraReadings[character] {
                set.formUnion(extras)
            }
            return set.sorted()
        }
    }

    /// 把一个带调拼音拆成 `lu` / `lv` 两种键盘写法；其它字符原样保留。
    private static func addReadings(from marked: String, to set: inout Set<String>) {
        guard !marked.isEmpty else { return }

        let plain = compact(fold(marked))
        if !plain.isEmpty { set.insert(plain) }

        // 先分解再替换，兼顾 ǚ / ǜ 等带调形式。注意不能用字符串替换：
        // Swift 会把 "u" + 组合分音符规范化成预组合字符，匹配不到分解串。
        let scalars = Array(marked.decomposedStringWithCanonicalMapping.unicodeScalars)
        var withV = ""
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x0075, // u
               index + 1 < scalars.count,
               scalars[index + 1].value == 0x0308 { // combining diaeresis
                withV += "v"
                index += 2
            } else if scalar.value == 0x0308 {
                withV += "v"
                index += 1
            } else {
                withV.unicodeScalars.append(scalar)
                index += 1
            }
        }
        let vForm = compact(fold(withV))
        if !vForm.isEmpty { set.insert(vForm) }
    }

    private static func transliterate(_ text: String, transform: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        guard CFStringTransform(mutable, nil, transform as CFString, false) else { return "" }
        return mutable as String
    }

    private static func fold(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }

    /// 小写 + 只保留字母 / 数字（去掉空格、标点、连接符）；中文属于字母，会保留。
    private static func compact(_ text: String) -> String {
        var result = ""
        for scalar in text.lowercased().unicodeScalars
        where CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJK)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,   // 扩展 A
             0x4E00...0x9FFF,   // 基本区
             0xF900...0xFAFF,   // 兼容表意
             0x20000...0x2FA1F: // 扩展 B–F
            return true
        default:
            return false
        }
    }

    /// 系统转写没有覆盖、但片名里常见的多音字读音。
    ///
    /// 只补「多出来的那一种」，系统读音仍由 `Han-Latin` / `Han-Latin/Names` 提供；
    /// 读音放宽只会让搜索更宽容，不会改变直接标题匹配。
    private static let extraReadings: [Character: [String]] = [
        "地": ["di"],
        "了": ["liao"],
        "行": ["hang"],
        "乐": ["yue"],
        "还": ["huan"],
        "着": ["zhao", "zhuo"],
        "都": ["du"],
        "会": ["kuai"],
        "觉": ["jiao"],
        "血": ["xie"],
        "薄": ["bo"],
        "柏": ["bo"],
        "秘": ["bi"],
        "率": ["shuai"],
        "塞": ["se"],
        "恶": ["wu"],
        "奇": ["ji"],
        "大": ["dai"],
        "佛": ["fu"],
        "给": ["ji"],
        "校": ["jiao"],
        "传": ["zhuan"],
        "系": ["ji"],
        "省": ["xing"],
        "盛": ["cheng"],
        "重": ["chong"],
        "朝": ["zhao"],
        "藏": ["zang"],
        "区": ["ou"],
        "仇": ["qiu"],
        "查": ["zha"],
        "朴": ["piao"],
        "角": ["jue"],
        "便": ["pian"],
        "模": ["mu"],
        "圈": ["juan"],
        "露": ["lou"],
        "色": ["shai"],
        "熟": ["shou"],
        "谁": ["shei"],
        "削": ["xiao"],
        "钥": ["yue"],
        "仔": ["zi"],
        "转": ["zhuai"],
        "弹": ["tan"],
        "调": ["tiao"],
        "降": ["xiang"],
        "粘": ["nian"],
        "扎": ["za"],
        "和": ["huo", "hu"],
    ]
}

/// 单字读音缓存：查询会随每次按键重复，汉字数量有限，缓存后几乎零成本。
private final class ReadingCache: @unchecked Sendable {
    static let shared = ReadingCache()

    private var storage: [Character: [String]] = [:]
    private let lock = NSLock()

    func readings(for character: Character, compute: () -> [String]) -> [String] {
        lock.lock()
        if let cached = storage[character] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = compute()

        lock.lock()
        storage[character] = value
        lock.unlock()
        return value
    }
}
