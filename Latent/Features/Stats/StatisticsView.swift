import Charts
import MapKit
import SwiftUI

/// 片库统计页（设计文档第 14.3 节）。
///
/// 全部数据来自本地片库快照，不发网络请求；年代 / 评分 / 入库趋势用 Swift Charts，
/// 类型 / 导演 / 主演 / 国家用自绘条形（避免长人名在窄卡片里被坐标轴截断）。
struct StatisticsView: View {
    @Environment(AppEnvironment.self) private var appEnv

    /// 「按口味来一部」上一次选中的条目，避免连点两次看到同一部。
    @State private var lastTastePickID: String?

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

                    if !statistics.taste.isEmpty {
                        tasteCard
                    }

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
                        if !statistics.budgetRevenue.isEmpty {
                            budgetCard
                        }
                        if !statistics.passport.isEmpty {
                            passportCard
                        }
                        if !statistics.timeline.isEmpty {
                            timelineCard
                        }
                        if statistics.radar.contains(where: { $0.count > 0 }) {
                            radarCard
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

    // MARK: - 口味画像

    private var tasteCard: some View {
        let taste = statistics.taste
        return ChartCard(title: "口味画像", caption: "由收藏与观看清单推算") {
            VStack(alignment: .leading, spacing: UI.Spacing.s3) {
                if !taste.topGenres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(taste.topGenres) { genre in
                            Text(genre.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(UI.Palette.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(UI.Palette.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("偏爱类型：" + taste.topGenres.map(\.name).joined(separator: "、"))
                }

                HStack(spacing: UI.Spacing.s4) {
                    if let decade = taste.favoriteDecade {
                        tasteFact(label: "最常看", value: "\(decade.year)s")
                    }
                    if let average = taste.averageRating, let text = Formatters.rating(average) {
                        tasteFact(label: "平均分", value: text)
                    }
                    tasteFact(
                        label: "候选",
                        value: taste.poolIsWatchlist
                            ? "观看清单 \(taste.pool.count) 部"
                            : "片库 \(taste.pool.count) 部"
                    )
                }

                HStack(spacing: UI.Spacing.s3) {
                    Button {
                        openTastePick()
                    } label: {
                        Label("按口味来一部", systemImage: "dice")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(taste.pool.isEmpty)
                    .help("按类型偏好加权，从\(taste.poolIsWatchlist ? "观看清单" : "片库")里随机打开一部")

                    Text(taste.poolIsWatchlist ? "从还没看的片子里挑" : "从片库里随机挑")
                        .font(.system(size: 11))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
            }
        }
    }

    private func tasteFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(UI.Palette.textSecondary)
            NumericText(text: value, size: 13)
        }
    }

    private func openTastePick() {
        guard let pick = statistics.taste.pick(excluding: lastTastePickID) else { return }
        lastTastePickID = pick.id
        guard let destination = DetailDestination.from(pick.asSummary) else { return }
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
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

    /// 预算 vs 票房：点越靠右下越像「以小博大」，虚线为回本线。
    private var budgetCard: some View {
        let points = statistics.budgetRevenue
        let maxValue = points.map { max($0.budget, $0.revenue) }.max() ?? 1
        let best = points.first

        return ChartCard(
            title: "预算 vs 票房",
            caption: "美元；虚线为回本线，右下角最赚"
        ) {
            Chart {
                ForEach(points) { point in
                    PointMark(
                        x: .value("预算", Double(point.budget)),
                        y: .value("票房", Double(point.revenue))
                    )
                    .foregroundStyle(UI.Palette.accent.opacity(0.75))
                    .symbolSize(48)
                }

                LineMark(
                    x: .value("预算", 0),
                    y: .value("票房", 0)
                )
                .foregroundStyle(UI.Palette.textSecondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                LineMark(
                    x: .value("预算", Double(maxValue)),
                    y: .value("票房", Double(maxValue))
                )
                .foregroundStyle(UI.Palette.textSecondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXScale(domain: 0...Double(maxValue))
            .chartYScale(domain: 0...Double(maxValue))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
                    AxisValueLabel {
                        Text(Self.axisMoney(value.as(Double.self)))
                            .font(.system(size: 10))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
                    AxisValueLabel {
                        Text(Self.axisMoney(value.as(Double.self)))
                            .font(.system(size: 10))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                }
            }
            .frame(height: 190)
            .accessibilityLabel("预算与票房散点图，共 \(points.count) 部")

            if let best, best.budget > 0 {
                Text("回本最高：\(best.title) · \(String(format: "%.1f", best.ratio))×")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    /// 观影护照：把有作品的制片国家在世界地图上点亮。
    private var passportCard: some View {
        ChartCard(
            title: "观影护照",
            caption: "已点亮 \(statistics.passport.count) 个国家和地区"
        ) {
            Map(
                initialPosition: .region(Self.region(fitting: statistics.passport)),
                interactionModes: [.pan, .zoom]
            ) {
                ForEach(statistics.passport) { stamp in
                    if let info = CountryDirectory.info(for: stamp.code) {
                        Annotation(stamp.name, coordinate: Self.coordinate(info)) {
                            Text("\(stamp.count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(UI.Palette.accent.opacity(0.9), in: Capsule())
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous)
                    .strokeBorder(UI.Palette.border, lineWidth: 1)
            }
            .accessibilityLabel("观影护照地图，已点亮 \(statistics.passport.count) 个国家和地区")
        }
    }

    /// 电影史长廊：每部作品按年份落在一条横轴上，圆点大小固定、数量沿纵轴升起。
    private var timelineCard: some View {
        let first = statistics.timeline.first?.year
        let last = statistics.timeline.last?.year
        let caption: String = {
            guard let first, let last else { return "按上映年份排列" }
            return first == last ? "\(first)" : "\(first) — \(last)"
        }()

        return ChartCard(title: "收藏时间轴", caption: caption) {
            Chart(statistics.timeline) { bucket in
                RuleMark(y: .value("基线", 0))
                    .foregroundStyle(UI.Palette.border)

                PointMark(
                    x: .value("年份", bucket.year),
                    y: .value("数量", bucket.count)
                )
                .foregroundStyle(UI.Palette.accent)
                .symbolSize(36)
            }
            .chartXScale(domain: (first ?? 0)...(last ?? 1))
            .chartXAxis {
                AxisMarks(values: Self.decadeTicks(from: first, to: last)) { _ in
                    AxisGridLine().foregroundStyle(UI.Palette.border)
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
            .frame(height: 140)
            .accessibilityLabel("收藏时间轴，从 \(first ?? 0) 到 \(last ?? 0)")
        }
    }

    private var radarCard: some View {
        ChartCard(title: "类型雷达", caption: "八维类型分布") {
            RadarChart(axes: statistics.radar)
                .frame(height: 200)
        }
    }

    // MARK: - 局部工具

    /// 每十年一个刻度；不足十年跨度时至少给首尾两个。
    private static func decadeTicks(from first: Int?, to last: Int?) -> [Int] {
        guard let first, let last else { return [] }
        guard last > first else { return [first] }
        var ticks = stride(from: (first / 10) * 10, through: last, by: 10).map { $0 }
        if ticks.first != first {
            ticks.insert(first, at: 0)
        }
        if ticks.last != last {
            ticks.append(last)
        }
        return ticks
    }

    /// 没有数据时的全球视野；跨度控制在 MapKit 稳定范围内（纬度 ≤ 150、经度 ≤ 320）。
    private static var worldRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 150, longitudeDelta: 320)
        )
    }

    /// 按实际标注点拟合视野：留 40% 边距，并保证最小跨度，
    /// 避免只点亮一个国家时相机怼到街道级别、也避免跨日期变更线时算出非法跨度。
    private static func region(
        fitting stamps: [LibraryStatistics.CountryStamp]
    ) -> MKCoordinateRegion {
        let infos = stamps.compactMap { CountryDirectory.info(for: $0.code) }
        guard let first = infos.first else { return worldRegion }
        guard infos.count > 1 else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude),
                span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 50)
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude
        for info in infos.dropFirst() {
            minLatitude = min(minLatitude, info.latitude)
            maxLatitude = max(maxLatitude, info.latitude)
            minLongitude = min(minLongitude, info.longitude)
            maxLongitude = max(maxLongitude, info.longitude)
        }

        let latitudeSpan = min(max((maxLatitude - minLatitude) * 1.4, 26), 150)
        let longitudeSpan = min(max((maxLongitude - minLongitude) * 1.4, 36), 320)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        )
    }

    private static func coordinate(_ info: CountryDirectory.Info) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: info.latitude, longitude: info.longitude)
    }

    /// 坐标轴金额：$200M 这种短写法；无值时留空。
    private static func axisMoney(_ amount: Double?) -> String {
        guard let amount, amount > 0 else { return "" }
        return Formatters.money(Int(amount)) ?? ""
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

/// 八维雷达图：Swift Charts 没有雷达类型，用 Canvas 自绘网格、轴线与数据多边形。
private struct RadarChart: View {
    let axes: [LibraryStatistics.RadarAxis]

    private let startAngle = -Double.pi / 2

    var body: some View {
        Canvas { context, size in
            guard axes.count >= 3 else { return }
            let maxCount = max(axes.map(\.count).max() ?? 0, 1)
            let radius = max(0, min(size.width, size.height) / 2 - 30)
            guard radius > 0 else { return }

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let step = 2 * Double.pi / Double(axes.count)

            for ring in 1...3 {
                let path = polygon(
                    center: center,
                    radius: radius * CGFloat(ring) / 3,
                    step: step
                )
                context.stroke(path, with: .color(UI.Palette.border), lineWidth: 1)
            }

            for index in axes.indices {
                var axisLine = Path()
                axisLine.move(to: center)
                axisLine.addLine(to: vertex(center: center, radius: radius, step: step, index: index))
                context.stroke(axisLine, with: .color(UI.Palette.border), lineWidth: 1)
            }

            let dataPoints = axes.indices.map { index -> CGPoint in
                let ratio = CGFloat(axes[index].count) / CGFloat(maxCount)
                return vertex(
                    center: center,
                    radius: radius * max(ratio, 0),
                    step: step,
                    index: index
                )
            }
            var dataPath = Path()
            dataPath.addLines(dataPoints)
            dataPath.closeSubpath()
            context.fill(dataPath, with: .color(UI.Palette.accent.opacity(0.22)))
            context.stroke(dataPath, with: .color(UI.Palette.accent), lineWidth: 1.5)

            for point in dataPoints {
                let dot = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(UI.Palette.accent))
            }

            for (index, axis) in axes.enumerated() {
                let labelPoint = vertex(
                    center: center,
                    radius: radius + 16,
                    step: step,
                    index: index
                )
                let label = context.resolve(
                    Text(axis.name)
                        .font(.system(size: 10))
                        .foregroundStyle(UI.Palette.textSecondary)
                )
                context.draw(label, at: labelPoint, anchor: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(axes))
    }

    private func vertex(
        center: CGPoint,
        radius: CGFloat,
        step: Double,
        index: Int
    ) -> CGPoint {
        let angle = startAngle + step * Double(index)
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func polygon(center: CGPoint, radius: CGFloat, step: Double) -> Path {
        var path = Path()
        for index in axes.indices {
            let point = vertex(center: center, radius: radius, step: step, index: index)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func summary(_ axes: [LibraryStatistics.RadarAxis]) -> String {
        let parts = axes.filter { $0.count > 0 }.map { "\($0.name) \($0.count) 部" }
        return parts.isEmpty ? "类型雷达，暂无数据" : "类型雷达：" + parts.joined(separator: "，")
    }
}

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
