import SwiftUI

/// 对比两部作品（v1.32）：并排指标表 + 共同项。入口在片库多选恰好两部后的「对比」。
///
/// 两侧详情并发拉取；行只做同项并排，不判断「哪部更好看」——
/// 只有评分与票房这类纯数值行会标出较高的一方。
struct CompareView: View {
    let left: MediaSummary
    let right: MediaSummary

    @Environment(AppEnvironment.self) private var appEnv
    @State private var result: CompareResult?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                heading

                if let errorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await load() }
                    }
                }

                if isLoading && result == nil {
                    loadingState
                } else if let result {
                    subjects(result)
                    metricTable(result)
                    sharedSection(result)
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: "\(left.stableID)|\(right.stableID)") { await load() }
    }

    // MARK: - 页头

    private var heading: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            HStack(spacing: UI.Spacing.s3) {
                Text("对比")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)

                Button("找关系路径") {
                    NotificationCenter.default.post(
                        name: AppCommandBus.pushDetail,
                        object: DetailDestination.sixDegrees(left: left, right: right)
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("查找两部作品之间经演员 / 导演的最短关系路径")
            }
            Text("\(left.title)　与　\(right.title)")
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    // MARK: - 两侧封面

    private func subjects(_ result: CompareResult) -> some View {
        HStack(alignment: .top, spacing: UI.Spacing.s4) {
            subjectColumn(result.left)
            Text("VS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 88)
                .padding(.top, 84)
            subjectColumn(result.right)
        }
    }

    private func subjectColumn(_ profile: CompareProfile) -> some View {
        VStack(spacing: UI.Spacing.s2) {
            PosterImage(path: profile.posterPath, displayWidth: 132)
                .frame(width: 132, height: 198)
                .overlay {
                    RoundedRectangle(cornerRadius: UI.Radius.poster, style: .continuous)
                        .strokeBorder(UI.Palette.border, lineWidth: 1)
                }

            Text(profile.title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(UI.Palette.textPrimary)

            Text(profile.mediaKind.label)
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)

            Button("打开详情") {
                if let destination = DetailDestination.from(profile.summary) {
                    NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(UI.Palette.accent)
            .help("打开「\(profile.title)」详情页")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 指标表

    private func metricTable(_ result: CompareResult) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(result.rows.enumerated()), id: \.element.id) { index, row in
                metricRow(row, isLast: index == result.rows.count - 1)
            }
        }
        .padding(.horizontal, UI.Spacing.s4)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    private func metricRow(_ row: CompareResult.Row, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s3) {
                metricValue(row.left, leads: row.leader == .left, alignment: .trailing)

                Text(row.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .frame(width: 88)

                metricValue(row.right, leads: row.leader == .right, alignment: .leading)
            }
            .padding(.vertical, UI.Spacing.s3)

            if !isLast {
                Rectangle()
                    .fill(UI.Palette.border)
                    .frame(height: 1)
            }
        }
    }

    private func metricValue(_ text: String, leads: Bool, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 13, weight: leads ? .semibold : .regular))
            .foregroundStyle(leads ? UI.Palette.accent : (text == "—" ? UI.Palette.textSecondary : UI.Palette.textPrimary))
            .frame(maxWidth: .infinity, alignment: alignment)
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
    }

    // MARK: - 共同点

    /// 没有共同项时整段隐藏（不显示占位提示）。
    @ViewBuilder
    private func sharedSection(_ result: CompareResult) -> some View {
        if result.sharedCount > 0 {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                Text("共同点")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)

                if !result.sharedGenres.isEmpty {
                    sharedLine("共同类型", result.sharedGenres.joined(separator: "、"))
                }
                if !result.sharedDirectors.isEmpty {
                    sharedLine("共同主创", result.sharedDirectors.joined(separator: "、"))
                }
                if !result.sharedCast.isEmpty {
                    sharedLine("共同出演 · \(result.sharedCast.count) 位", castText(result.sharedCast))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UI.Spacing.s4)
            .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
        }
    }

    private func sharedLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .foregroundStyle(UI.Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func castText(_ cast: [CompareProfile.CastEntry]) -> String {
        let shown = cast.prefix(8).map { member in
            member.character.map { "\(member.name)（\($0)）" } ?? member.name
        }
        let tail = cast.count > shown.count ? " 等 \(cast.count) 位" : ""
        return shown.joined(separator: "、") + tail
    }

    // MARK: - 状态

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            Skeleton.textLines(width: 160, lines: 1)
            Skeleton.block(cornerRadius: UI.Radius.button)
                .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 载入

    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            async let leftDetail = detail(for: left)
            async let rightDetail = detail(for: right)
            let (loadedLeft, loadedRight) = try await (leftDetail, rightDetail)
            result = CompareResult.make(
                left: CompareProfile(detail: loadedLeft),
                right: CompareProfile(detail: loadedRight)
            )
        } catch let error as APIError {
            errorMessage = error.errorDescription
            result = nil
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }

        isLoading = false
    }

    private func detail(for summary: MediaSummary) async throws -> any MediaDetail {
        switch summary.mediaKind {
        case .movie: return try await appEnv.client.movieDetail(id: summary.id)
        case .tv: return try await appEnv.client.tvDetail(id: summary.id)
        default: throw APIError.notFound
        }
    }
}

private extension CompareProfile {
    /// 对比页里点「打开详情」用：还原成可 Push 的最小摘要。
    var summary: MediaSummary {
        switch mediaKind {
        case .tv: return MediaSummary(id: tmdbID, mediaKind: .tv, title: title,
                                      originalTitle: originalTitle, posterPath: posterPath)
        default: return MediaSummary(id: tmdbID, mediaKind: .movie, title: title,
                                     originalTitle: originalTitle, posterPath: posterPath)
        }
    }
}
