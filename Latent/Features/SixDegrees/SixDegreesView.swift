import SwiftUI

/// 六度分隔页（v1.35）：两部作品之间经演员 / 导演的最短关系路径。
///
/// 竖向时间线——作品卡与人物卡交替，箭头旁标注每一跳的连接说明；
/// 搜索中显示实时探索进度，未找到与失败都有明确提示。
struct SixDegreesView: View {
    let left: MediaSummary
    let right: MediaSummary

    @Environment(AppEnvironment.self) private var appEnv
    @State private var phase: Phase = .searching(exploredMovies: 0, exploredPeople: 0)
    @State private var reloadToken = 0

    enum Phase: Equatable {
        case searching(exploredMovies: Int, exploredPeople: Int)
        case found(SixDegreesPath)
        case notFound(exploredMovies: Int, exploredPeople: Int)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s4) {
                heading

                switch phase {
                case .searching(let movies, let people):
                    searchingState(movies, people)
                case .found(let path):
                    timeline(path)
                case .notFound(let movies, let people):
                    notFoundState(movies, people)
                case .failed(let message):
                    ErrorBanner(message: message) {
                        reloadToken += 1
                    }
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: reloadToken) {
            await search()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommandBus.refresh)) { _ in
            reloadToken += 1
        }
    }

    // MARK: - 页头

    private var heading: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s1) {
            Text("六度分隔")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("\(left.title)　与　\(right.title)")
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    // MARK: - 状态

    private func searchingState(_ movies: Int, _ people: Int) -> some View {
        VStack(spacing: UI.Spacing.s3) {
            ProgressView()
                .controlSize(.regular)
            Text("正在搜索关系路径…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("已探索 \(movies) 部作品 · \(people) 位影人")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, UI.Spacing.s6)
    }

    private func notFoundState(_ movies: Int, _ people: Int) -> some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            Text("预算内没有找到关系路径")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("在探索 \(movies) 部作品、\(people) 位影人后仍未连通。试试换两部更知名的作品——冷门片的演职员数据往往撑不起一条路径。")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
            Button("重新搜索") {
                reloadToken += 1
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UI.Spacing.s4)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    // MARK: - 时间线

    private func timeline(_ path: SixDegreesPath) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(path.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    linkLabel(path.links[index - 1])
                }
                nodeCard(node)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func linkLabel(_ text: String) -> some View {
        HStack(spacing: UI.Spacing.s2) {
            Image(systemName: "arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UI.Palette.accent)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UI.Palette.accentText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(UI.Palette.accent.opacity(0.14), in: Capsule())
        .padding(.vertical, UI.Spacing.s2)
    }

    @ViewBuilder
    private func nodeCard(_ node: SixDegreesPathNode) -> some View {
        switch node {
        case .movie(let movie):
            Button {
                let destination = DetailDestination.from(movie.summary) ?? .movie(id: movie.id, fallback: movie.summary)
                NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
            } label: {
                HStack(spacing: UI.Spacing.s3) {
                    PosterImage(path: movie.posterPath, displayWidth: 44)
                        .frame(width: 44, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .hairlineBorder(radius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movie.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(UI.Palette.textPrimary)
                            .lineLimit(1)
                        Text(nodeSubtitle(movie))
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .padding(UI.Spacing.s3)
                .frame(maxWidth: 420)
                .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
                .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
                .contentShape(RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)

        case .person(let person):
            Button {
                NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: DetailDestination.person(id: person.id))
            } label: {
                HStack(spacing: UI.Spacing.s3) {
                    PosterImage(path: person.profilePath, displayWidth: 36)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .hairlineBorder(radius: 18)
                    Text(person.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(UI.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(UI.Palette.textSecondary)
                }
                .padding(.horizontal, UI.Spacing.s3)
                .padding(.vertical, UI.Spacing.s2)
                .frame(maxWidth: 420)
                .background(UI.Palette.surfaceElevated, in: Capsule())
                .hairlineBorder(UI.Palette.border, radius: 21)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func nodeSubtitle(_ movie: SixDegreesMovie) -> String {
        var parts: [String] = [movie.mediaKind == .tv ? "剧集" : "电影"]
        if let year = Formatters.year(from: movie.dateString) {
            parts.append("\(year)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 搜索

    private func search() async {
        let leftMovie = SixDegreesMovie(summary: left)
        let rightMovie = SixDegreesMovie(summary: right)

        guard leftMovie.stableID != rightMovie.stableID else {
            phase = .notFound(exploredMovies: 0, exploredPeople: 0)
            return
        }

        phase = .searching(exploredMovies: 0, exploredPeople: 0)
        let fetcher = LiveSixDegreesFetcher(client: appEnv.client)
        do {
            let outcome = try await SixDegreesSearch.find(
                left: leftMovie,
                right: rightMovie,
                fetcher: fetcher,
                onProgress: { movies, people in
                    Task { @MainActor in
                        phase = .searching(exploredMovies: movies, exploredPeople: people)
                    }
                }
            )
            switch outcome {
            case .found(let path):
                phase = .found(path)
            case .notFound(let movies, let people):
                phase = .notFound(exploredMovies: movies, exploredPeople: people)
            }
        } catch let error as APIError {
            phase = .failed(error.errorDescription)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
