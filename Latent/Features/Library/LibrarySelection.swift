import Foundation

/// 片库多选（v1.7）：纯函数，便于单测。
///
/// 选择键统一使用 `LibrarySnapshot.id` / `MediaSummary.stableID` 的
/// `mediaType-tmdbID` 形式，电影与剧集同 TMDB ID 也不会串选。
enum LibrarySelection {
    /// 点按勾选 / 取消勾选。
    static func toggled(_ id: String, in selection: Set<String>) -> Set<String> {
        var next = selection
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }

    /// ⇧-点按：选择 anchor 与 target 之间的连续区间（含两端）。
    /// anchor 已不在当前列表时退化为只选 target。
    static func range(
        from anchorID: String,
        through targetID: String,
        in orderedIDs: [String]
    ) -> Set<String> {
        guard let anchor = orderedIDs.firstIndex(of: anchorID),
              let target = orderedIDs.firstIndex(of: targetID) else {
            return [targetID]
        }
        let bounds = anchor <= target ? anchor...target : target...anchor
        return Set(orderedIDs[bounds])
    }

    /// 数据变化后裁掉已不存在的条目。
    static func clamped(_ selection: Set<String>, to validIDs: Set<String>) -> Set<String> {
        selection.intersection(validIDs)
    }
}
