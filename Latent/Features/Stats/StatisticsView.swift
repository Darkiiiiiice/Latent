import Charts
import SwiftUI

/// 片库统计页（设计文档第 14.3 节）。
///
/// 全部数据来自本地片库快照，不发网络请求；年代 / 评分 / 入库趋势用 Swift Charts，
/// 类型 / 导演 / 主演 / 国家用自绘条形（避免长人名在窄卡片里被坐标轴截断）。
struct StatisticsView: View {
    @Environment(AppEnvironment.self) private var appEnv

    private var statistics: LibraryStatistics {
        LibraryStatistics(
            favorites: appEnv.library.favoriteItems,
            watchlist: appEnv.library.watchlistItems
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                header

                if statistics.isEmpty {
                    EmptyState(
                        message: "收藏或加入观看清单后，这里会出现你的观影统计",
                        systemImage: "chart.bar",
                        actionTitle: "去趋势页逛逛",
                        action: { AppCommandBus.select(.trending) }
                    )
                } else {
                    summaryGrid

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360), spacing: UI.Spacing.s4)],
                        alignment: .leading,
                        spacing: UI.Spacing.s4
                    ) {
                        if !statistics.decades.isEmpty {
                            decadesCard
                        }
                        if !statistics.ratings.isEmpty {
                            ratingsCard
                        }
                        if statistics.monthly.contains(where: { $0.count > 0 }) {
                            monthlyCard
                        }
                        if !statistics.genres.isEmpty {
                            rankingCard(
                                title: "类型",
                                subtitle: "Top \(statistics.genres.count)",
                                slices: statistics.genres
                            )
                        }
                        if !statistics.directors.isEmpty {
                            rankingCard(
                                title: "导演",
                                subtitle: "Top \(statistics.directors.count)",
                                slices: statistics.directors
                            )
                        }
                        if !statistics.cast.isEmpty {
                            rankingCard(
                                title: "主演",
                                subtitle: "Top \(statistics.cast.count)",
                                slices: statistics.cast
                            )
                        }
                        if !statistics.countries.isEmpty {
                            rankingCard(
                                title: "国家 / 地区",
                                subtitle: "Top \(statistics.countries.count)",
                                slices: statistics.countries
                            )
                        }
                    }
                }
            }
            .padding(UI.Spacing.contentMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(UI.Palette.bg)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s3) {
            Text("统计")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)

            if !statistics.isEmpty {
                NumericText(text: "\(statistics.totalTitles)", size: 11)
            }

            Spacer(minLength: 0)

            if statistics.pendingCount > 0 {
                Text("还有 \(statistics.pendingCount) 条缺少详情")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)

                Button("现在补齐") {
                    appEnv.enrichLibraryInBackground()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("逐条获取详情，补齐类型 / 导演 / 主演等统计维度")
            }
        }
    }

    // MARK: - 摘要

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: UI.Spacing.s3)],
            alignment: .leading,
            spacing: UI.Spacing.s3
        ) {
            SummaryTile(title: "片库总数", value: "\(statistics.totalTitles)")
            SummaryTile(title: "电影", value: "\(statistics.movieCount)")
            SummaryTile(title: "剧集", value: "\(statistics.tvCount)")
            SummaryTile(title: "收藏", value: "\(statistics.favoriteCount)")
            SummaryTile(title: "观看清单", value: "\(statistics.watchlistCount)")
            SummaryTile(
                title: "电影总时长",
                value: Formatters.runtime(minutes: statistics.movieMinutes) ?? "—"
            )
        }
    }

    // MARK: - 图表卡片

    private var decadesCard: some View {
        ChartCard(title: "年代分布", caption: "按上映年份归入十年区间") {
            Chart(statistics.decades) { bucket in
                BarMark(
                    x: .value("年代", "\(bucket.year)s"),
                    y: .value("数量", bucket.count)
                )
                .foregroundStyle(UI.Palette.accent)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .frame(height: 150)
            .accessibilityLabel("年代分布")
        }
    }

    private var ratingsCard: some View {
        ChartCard(title: "评分分布", caption: "TMDB 评分（整数区间）") {
            Chart(statistics.ratings) { bucket in
                BarMark(
                    x: .value("评分", bucket.score),
                    y: .value("数量", bucket.count)
                )
                .foregroundStyle(UI.Palette.accent)
                .cornerRadius(2)
            }
            .chartXScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: [0, 2, 4, 6, 8, 10]) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .frame(height: 150)
            .accessibilityLabel("评分分布")
        }
    }

    private var monthlyCard: some View {
        ChartCard(title: "入库趋势", caption: "最近 12 个月的收藏 / 入库条数") {
            Chart(statistics.monthly) { point in
                AreaMark(
                    x: .value("月份", point.month),
                    y: .value("数量", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [UI.Palette.accent.opacity(0.28), UI.Palette.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("月份", point.month),
                    y: .value("数量", point.count)
                )
                .foregroundStyle(UI.Palette.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits))
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
            .frame(height: 150)
            .accessibilityLabel("入库趋势")
        }
    }

    private func rankingCard(
        title: String,
        subtitle: String,
        slices: [LibraryStatistics.Slice]
    ) -> some View {
        let maxCount = slices.map(\.count).max() ?? 1
        return ChartCard(title: title, caption: subtitle) {
            VStack(spacing: UI.Spacing.s2) {
                ForEach(slices) { slice in
                    HStack(spacing: UI.Spacing.s2) {
                        Text(slice.name)
                            .font(.system(size: 12))
                            .foregroundStyle(UI.Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 96, alignment: .leading)

                        Capsule()
                            .fill(UI.Palette.border.opacity(0.5))
                            .frame(height: 6)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(UI.Palette.accent)
                                        .frame(
                                            width: max(
                                                4,
                                                proxy.size.width * CGFloat(slice.count) / CGFloat(maxCount)
                                            )
                                        )
                                }
                                .frame(height: 6)
                            }

                        NumericText(text: "\(slice.count)", size: 11)
                            .frame(width: 24, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(slice.name)，\(slice.count) 部")
                }
            }
        }
    }
}

// MARK: - 局部组件

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(UI.Palette.textSecondary)

            NumericText(text: value, size: 18, weight: .semibold, color: UI.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.Spacing.s3)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)：\(value)")
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)
                Spacer(minLength: 0)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }

            content
        }
        .padding(UI.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }
}
