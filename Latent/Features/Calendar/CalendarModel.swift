import Foundation

/// 上映日历的一条目（v1.34）：待上映 / 待播出的作品 + 倒计时。
struct CalendarEntry: Sendable, Identifiable, Hashable {
    let summary: MediaSummary
    /// 库归属（收藏 / 清单）；为空表示还不在片库里。
    let libraryKinds: [LibraryKind]

    var id: String { summary.stableID }
    var date: Date? { Formatters.date(from: summary.dateString) }

    /// 倒计时文案：今天 / 明天 / N 天后（任意天数，不设上限）。
    /// 日期已过或缺失返回 nil——日历只展示未来的条目，不伪造倒计时。
    static func countdownText(for dateString: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = Formatters.date(from: dateString) else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2...: return "\(days) 天后"
        default: return nil
        }
    }

    func countdownText(now: Date = Date(), calendar: Calendar = .current) -> String? {
        Self.countdownText(for: summary.dateString, now: now, calendar: calendar)
    }
}

/// 日历的合并与排序（纯函数，便于单测）。
enum CalendarModel {
    /// 片库待映候选：一部片 + 它所在的清单归属。
    struct PendingCandidate: Sendable, Equatable {
        let snapshot: LibrarySnapshot
        /// 同一部片可能同时在收藏与清单里，两个徽标都记。
        let kinds: [LibraryKind]
        /// 拼 `detail` 请求用的媒体类型；候选里只有电影 / 剧集。
        var mediaKind: MediaKind { snapshot.mediaKind }
        var tmdbID: Int { snapshot.tmdbID }
        var stableID: String { snapshot.id }
    }

    /// 「即将上映」段：TMDB upcoming × on the air 合并去重。
    ///
    /// 规则：按 stableID 去重（同一部片两个来源只留一条，先到先得）；
    /// 丢弃日期已过或缺失的条目（不伪造）；按日期升序。
    static func mergeGlobal(
        upcoming: [MediaSummary],
        onTheAir: [MediaSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CalendarEntry] {
        var seen = Set<String>()
        var entries: [CalendarEntry] = []
        for summary in upcoming + onTheAir {
            guard seen.insert(summary.stableID).inserted else { continue }
            guard let date = Formatters.date(from: summary.dateString),
                  date >= calendar.startOfDay(for: now) else { continue }
            entries.append(CalendarEntry(summary: summary, libraryKinds: []))
        }
        return sorted(entries, calendar: calendar)
    }

    /// 按日期升序；缺日期的条目排最后兜底（理论上已在上游过滤）。
    static func sorted(_ entries: [CalendarEntry], calendar: Calendar = .current) -> [CalendarEntry] {
        entries.sorted { left, right in
            switch (left.date, right.date) {
            case let (.some(l), .some(r)):
                if l == r { return left.summary.stableID < right.summary.stableID }
                return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.summary.stableID < right.summary.stableID
            }
        }
    }

    /// 片库待映候选：收藏 / 清单里「还没上映」的条目。
    ///
    /// 片库快照只有年份没有精确日期，因此先用 `year >= 当前年` 粗筛，
    /// 之后再由视图并发拉详情取精确日期；过去年份直接跳过，不发请求。
    /// 清单在前：待映条目通常收在清单里，更符合「想看的还没上」的语义。
    static func pendingLibraryCandidates(
        favorites: [LibrarySnapshot],
        watchlist: [LibrarySnapshot],
        currentYear: Int? = nil,
        limit: Int = 20
    ) -> [PendingCandidate] {
        let year = currentYear ?? Calendar.current.component(.year, from: Date())
        var kindsByStableID: [String: [LibraryKind]] = [:]
        // 与候选顺序一致：清单在前、收藏在后。
        for (kind, snapshots) in [(LibraryKind.watchlist, watchlist), (.favorites, favorites)] {
            for snapshot in snapshots where snapshot.mediaKind == .movie || snapshot.mediaKind == .tv {
                kindsByStableID[snapshot.id, default: []].append(kind)
            }
        }

        var seen = Set<String>()
        var candidates: [PendingCandidate] = []
        for snapshot in watchlist + favorites {
            guard let itemYear = snapshot.year, itemYear >= year else { continue }
            guard let kinds = kindsByStableID[snapshot.id], !kinds.isEmpty else { continue }
            guard seen.insert(snapshot.id).inserted else { continue }
            guard candidates.count < limit else { break }
            candidates.append(PendingCandidate(snapshot: snapshot, kinds: kinds))
        }
        return candidates
    }

    /// 把片库候选 + 拉到的精确日期组装成「我的待映」条目。
    ///
    /// `dateByStableID` 里没有的（详情拉取失败 / 日期已过）直接跳过，不伪造。
    static func buildMine(
        candidates: [PendingCandidate],
        dateByStableID: [String: String]
    ) -> [CalendarEntry] {
        sorted(
            candidates.compactMap { candidate in
                guard let dateString = dateByStableID[candidate.stableID] else { return nil }
                guard CalendarEntry.countdownText(for: dateString) != nil else { return nil }
                let base = candidate.snapshot.asSummary
                // 用详情返回的精确日期替换「年份-01-01」占位。
                let precise = MediaSummary(
                    id: base.id, mediaKind: base.mediaKind, title: base.title,
                    originalTitle: base.originalTitle, overview: base.overview,
                    posterPath: base.posterPath, backdropPath: base.backdropPath,
                    dateString: dateString, voteAverage: base.voteAverage,
                    voteCount: base.voteCount, popularity: base.popularity,
                    genreIDs: base.genreIDs
                )
                return CalendarEntry(summary: precise, libraryKinds: candidate.kinds)
            }
        )
    }
}
