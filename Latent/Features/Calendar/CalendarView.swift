import SwiftUI

/// 上映日历页（v1.34）：「我的待映」（片库未上映条目）+「即将上映」（TMDB upcoming × on the air），
/// 按「yyyy 年 M 月」分组倒计时；可设上映日提醒或加入观看清单。
struct CalendarView: View {
    let open: (MediaSummary) -> Void

    @Environment(AppEnvironment.self) private var appEnv
    /// 「即将上映」段：nil = 载入中。
    @State private var globalEntries: [CalendarEntry]?
    @State private var globalError: String?
    /// 「我的待映」段：nil = 载入中；载入完成但为空时整段隐藏。
    @State private var mineEntries: [CalendarEntry]?
    /// 已排期的上映提醒（按条目 id）。
    @State private var scheduledIDs: Set<String> = []
    @State private var busyIDs: Set<String> = []
    /// 已在观看清单里的条目（含本页新加入的）。
    @State private var watchlistedIDs: Set<String> = []
    @State private var reloadToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                header

                mineSection

                globalSection
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: reloadToken) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            reloadToken += 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s2) {
            Text("上映日历")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("即将上映与播出的作品，倒计时可设提醒；片库里还没上映的也会排进来。")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    // MARK: - 我的待映

    @ViewBuilder
    private var mineSection: some View {
        if let entries = mineEntries, !entries.isEmpty {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                sectionTitle("我的待映", count: entries.count)
                ForEach(monthGroups(entries), id: \.label) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        monthHeader(group.label)
                        ForEach(group.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 即将上映

    @ViewBuilder
    private var globalSection: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            sectionTitle("即将上映", count: globalEntries?.count)

            if let entries = globalEntries {
                if entries.isEmpty {
                    Text("暂时没有拿到即将上映的条目，稍后再试试刷新。")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                        .padding(.vertical, UI.Spacing.s4)
                } else {
                    ForEach(monthGroups(entries), id: \.label) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            monthHeader(group.label)
                            ForEach(group.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            } else if let globalError {
                ErrorBanner(message: globalError) {
                    reloadToken += 1
                }
            } else {
                VStack(spacing: UI.Spacing.s2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Skeleton(cornerRadius: UI.Radius.chip)
                            .frame(height: 64)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack(spacing: UI.Spacing.s2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            if let count {
                Text("\(count) 部")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func monthHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(UI.Palette.textSecondary)
            .padding(.top, UI.Spacing.s3)
            .padding(.bottom, UI.Spacing.s2)
    }

    // MARK: - 行

    private func row(_ entry: CalendarEntry) -> some View {
        let reminder = ReleaseReminder(
            mediaKind: entry.summary.mediaKind,
            tmdbID: entry.summary.id,
            title: entry.summary.title,
            dateString: entry.summary.dateString
        )
        let isScheduled = reminder.map { scheduledIDs.contains($0.id) } ?? false
        let isInWatchlist = entry.libraryKinds.contains(.watchlist) || watchlistedIDs.contains(entry.id)

        return HStack(spacing: UI.Spacing.s3) {
            PosterImage(path: entry.summary.posterPath, displayWidth: 40)
                .frame(width: 40, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .hairlineBorder(radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.summary.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)
                    kindChip(entry.summary.mediaKind)
                    ForEach(entry.libraryKinds, id: \.self) { kind in
                        libraryChip(kind)
                    }
                }
                Text(Formatters.fullDate(entry.summary.dateString) ?? entry.summary.dateString ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
            }

            Spacer(minLength: UI.Spacing.s2)

            if let countdown = entry.countdownText() {
                Text(countdown)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.Palette.accentText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(UI.Palette.accent.opacity(0.14), in: Capsule())
            }

            if let reminder {
                reminderButton(entry, reminder: reminder, isScheduled: isScheduled)
            }
            if !isInWatchlist {
                watchlistButton(entry)
            }
        }
        .padding(.vertical, UI.Spacing.s2)
        .contentShape(Rectangle())
        .onTapGesture {
            open(entry.summary)
        }
    }

    private func kindChip(_ kind: MediaKind) -> some View {
        Text(kind == .tv ? "剧集" : "电影")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(UI.Palette.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(UI.Palette.surfaceElevated, in: Capsule())
            .overlay {
                Capsule().strokeBorder(UI.Palette.border, lineWidth: 1)
            }
    }

    private func libraryChip(_ kind: LibraryKind) -> some View {
        Text(kind == .favorites ? "收藏" : "清单")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(UI.Palette.accentText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(UI.Palette.accent.opacity(0.14), in: Capsule())
    }

    private func reminderButton(_ entry: CalendarEntry, reminder: ReleaseReminder, isScheduled: Bool) -> some View {
        Button {
            Task { await handleReminderTap(reminder) }
        } label: {
            Image(systemName: isScheduled ? "bell.badge.fill" : "bell")
                .font(.system(size: 12))
                .foregroundStyle(isScheduled ? UI.Palette.accent : UI.Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    (isScheduled ? UI.Palette.accent.opacity(0.14) : UI.Palette.surfaceElevated),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busyIDs.contains(entry.id))
        .help(isScheduled
            ? "已设提醒：\(Formatters.fullDate(reminder.dateString) ?? reminder.dateString) 上午 \(ReleaseReminder.hourOfDay) 点。点按取消"
            : "在 \(Formatters.fullDate(reminder.dateString) ?? reminder.dateString) 上午 \(ReleaseReminder.hourOfDay) 点提醒我")
    }

    private func watchlistButton(_ entry: CalendarEntry) -> some View {
        Button {
            toggleWatchlist(entry)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(UI.Palette.surfaceElevated, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("加入观看清单")
    }

    // MARK: - 动作

    private func handleReminderTap(_ reminder: ReleaseReminder) async {
        if scheduledIDs.contains(reminder.id) {
            await appEnv.releaseReminders.cancel(identifier: reminder.identifier)
            scheduledIDs.remove(reminder.id)
            ToastCenter.shared.show("已取消提醒")
            return
        }

        busyIDs.insert(reminder.id)
        defer { busyIDs.remove(reminder.id) }

        var authorization = await appEnv.releaseReminders.authorizationStatus()
        if authorization == .notDetermined {
            _ = await appEnv.releaseReminders.requestAuthorization()
            authorization = await appEnv.releaseReminders.authorizationStatus()
        }
        guard authorization == .allowed else {
            ToastCenter.shared.show("请先在「系统设置 → 通知」里允许「显影」发送通知")
            return
        }

        do {
            try await appEnv.releaseReminders.schedule(reminder)
            scheduledIDs.insert(reminder.id)
            let when = Formatters.fullDate(reminder.dateString) ?? reminder.dateString
            ToastCenter.shared.show("已设置提醒：\(when) 上午 \(ReleaseReminder.hourOfDay) 点")
        } catch {
            ToastCenter.shared.show("设置提醒失败：日期已过或被系统拒绝")
        }
    }

    private func toggleWatchlist(_ entry: CalendarEntry) {
        let added = appEnv.library.toggleWatchlist(entry.summary)
        if added {
            watchlistedIDs.insert(entry.id)
            ToastCenter.shared.show("已加入观看清单")
        } else {
            watchlistedIDs.remove(entry.id)
            ToastCenter.shared.show("已移出观看清单")
        }
    }

    // MARK: - 载入

    private func load() async {
        globalEntries = nil
        globalError = nil
        mineEntries = nil
        watchlistedIDs = Set(appEnv.library.watchlistItems.map(\.id))

        async let global = loadGlobal()
        async let mine = loadMine()
        let (loadedGlobal, loadedMine) = await (global, mine)
        globalEntries = loadedGlobal
        mineEntries = loadedMine
        scheduledIDs = await appEnv.releaseReminders.scheduledIdentifiers()
    }

    /// TMDB upcoming × on the air（各取第一页）；失败记录错误信息由「即将上映」段展示。
    private func loadGlobal() async -> [CalendarEntry]? {
        do {
            async let upcoming = appEnv.client.movieUpcoming(page: 1)
            async let onTheAir = appEnv.client.tvOnTheAir(page: 1)
            let (upcomingPage, onTheAirPage) = try await (upcoming, onTheAir)
            return CalendarModel.mergeGlobal(
                upcoming: upcomingPage.items,
                onTheAir: onTheAirPage.items
            )
        } catch let error as APIError {
            globalError = error.errorDescription
            return nil
        } catch {
            globalError = error.localizedDescription
            return nil
        }
    }

    /// 片库待映：候选并发拉详情取精确日期；单个失败静默跳过（本地数据不整段报错）。
    private func loadMine() async -> [CalendarEntry] {
        let candidates = CalendarModel.pendingLibraryCandidates(
            favorites: appEnv.library.favoriteItems,
            watchlist: appEnv.library.watchlistItems
        )
        guard !candidates.isEmpty else { return [] }

        let client = appEnv.client
        var dateByStableID: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for candidate in candidates {
                let mediaKind = candidate.mediaKind
                let tmdbID = candidate.tmdbID
                let stableID = candidate.stableID
                group.addTask {
                    let dateString: String?
                    do {
                        switch mediaKind {
                        case .movie:
                            dateString = try await client.movieDetail(id: tmdbID).dateString
                        case .tv:
                            dateString = try await client.tvDetail(id: tmdbID).dateString
                        default:
                            dateString = nil
                        }
                    } catch {
                        dateString = nil
                    }
                    return (stableID, dateString)
                }
            }
            for await (stableID, dateString) in group {
                if let dateString {
                    dateByStableID[stableID] = dateString
                }
            }
        }
        return CalendarModel.buildMine(candidates: candidates, dateByStableID: dateByStableID)
    }

    // MARK: - 分组

    /// 按「yyyy 年 M 月」分组；组间按最早日期排序（无日期的「日期待定」垫底）。
    private func monthGroups(_ entries: [CalendarEntry]) -> [(label: String, entries: [CalendarEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"

        var grouped: [String: [CalendarEntry]] = [:]
        for entry in entries {
            let label = entry.date.map(formatter.string(from:)) ?? "日期待定"
            grouped[label, default: []].append(entry)
        }
        return grouped
            .map { (label: $0.key, entries: CalendarModel.sorted($0.value)) }
            .sorted { left, right in
                switch (left.entries.first?.date, right.entries.first?.date) {
                case let (.some(l), .some(r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return false
                }
            }
    }
}
