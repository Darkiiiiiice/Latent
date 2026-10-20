import SwiftUI

/// 人物页：头像 + 简介 + 生卒 / 出生地 + 作品年表（原生 `Table`，设计文档第 8.6 节）。
struct PersonDetailView: View {
    let personID: Int

    @Environment(AppEnvironment.self) private var appEnv
    @State private var person: PersonDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var sortOrder = [KeyPathComparator(\FilmographyRow.year, order: .reverse)]
    @State private var filter: FilmFilter = .all
    @State private var isBiographyExpanded = false
    @State private var showsReceipt = false

    enum FilmFilter: String, CaseIterable, Identifiable {
        case all, movie, tv
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部"
            case .movie: return "电影"
            case .tv: return "剧集"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.Spacing.s6) {
                header

                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                }

                if isLoading && person == nil {
                    Skeleton.textLines(width: 420, lines: 4)
                } else if let person {
                    biographySection(person)
                    filmographySection(person)
                }
            }
            .padding(.horizontal, UI.Spacing.contentMargin)
            .padding(.vertical, UI.Spacing.s6)
        }
        .background(UI.Palette.bg)
        .task(id: personID) { await load() }
        .toolbar {
            if person != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsReceipt = true
                    } label: {
                        Label("分享卡", systemImage: "rectangle.portrait.on.rectangle.portrait.angled")
                    }
                    .help("生成分享卡（发朋友圈用）")
                }
            }
        }
        .sheet(isPresented: $showsReceipt) {
            if let person {
                ReceiptSheet(data: ReceiptData.build(from: person))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: UI.Spacing.s6) {
            PosterImage(path: person?.profilePath, displayWidth: 120, cornerRadius: 8)
                .frame(width: 120, height: 180)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(UI.Palette.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: UI.Spacing.s2) {
                Text(person?.name ?? "载入中…")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)

                if let department = person?.knownForDepartment {
                    Text(department)
                        .font(.system(size: 12))
                        .foregroundStyle(UI.Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let life = person?.lifeText {
                        factLine("生卒", life)
                    }
                    if let place = person?.placeOfBirth {
                        factLine("出生地", place)
                    }
                    if let imdb = person?.externalIDs?.imdbID, let url = TMDBLinks.imdbURL(imdbID: imdb) {
                        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
                            Text("IMDB")
                                .font(.system(size: 11, weight: .medium))
                                .kerning(0.4)
                                .foregroundStyle(UI.Palette.textSecondary)
                                .frame(width: 48, alignment: .leading)
                            Link(imdb, destination: url)
                                .font(.system(size: 12))
                        }
                    }
                    factLine("TMDB", "\(personID)")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private func factLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UI.Spacing.s2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(UI.Palette.textSecondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(UI.Palette.textPrimary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func biographySection(_ person: PersonDetail) -> some View {
        let biography = person.biography?.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            SectionHeader(title: "简介")
            if let biography, !biography.isEmpty {
                Text(biography)
                    .font(.system(size: 13))
                    .foregroundStyle(UI.Palette.textPrimary)
                    .lineSpacing(3)
                    .lineLimit(isBiographyExpanded ? nil : 6)
                Button(isBiographyExpanded ? "收起" : "展开全文") {
                    withAnimation(UI.Motion.hover) { isBiographyExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.accent)
            } else {
                Text("暂无简介")
                    .font(.system(size: 13))
                    .foregroundStyle(UI.Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func filmographySection(_ person: PersonDetail) -> some View {
        let rows = filteredRows(person)
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            HStack {
                SectionHeader(title: "作品年表")
                Spacer()
                Picker("筛选", selection: $filter) {
                    ForEach(FilmFilter.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }

            if rows.isEmpty {
                Text("暂无作品记录")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("年份", value: \.year) { row in
                        NumericText(text: row.year > 0 ? "\(row.year)" : "—", size: 11)
                    }
                    .width(56)

                    TableColumn("作品", value: \.title) { row in
                        Button {
                            open(row.summary)
                        } label: {
                            Text(row.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("查看《\(row.title)》")
                    }

                    TableColumn("类型", value: \.kindLabel) { row in
                        Text(row.kindLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(UI.Palette.textSecondary)
                    }
                    .width(52)
                }
                .frame(minHeight: min(CGFloat(rows.count) * 26 + 36, 560))
            }
        }
    }

    private func open(_ summary: MediaSummary) {
        guard let destination = DetailDestination.from(summary) else { return }
        NotificationCenter.default.post(name: AppCommandBus.pushDetail, object: destination)
    }

    private func filteredRows(_ person: PersonDetail) -> [FilmographyRow] {
        let filmography = person.combinedCredits?.filmography ?? []
        let filtered: [MediaSummary]
        switch filter {
        case .all: filtered = filmography
        case .movie: filtered = filmography.filter { $0.mediaKind == .movie }
        case .tv: filtered = filmography.filter { $0.mediaKind == .tv }
        }
        return filtered
            .map { FilmographyRow(summary: $0) }
            .sorted(using: sortOrder)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            person = try await appEnv.client.personDetail(id: personID)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = APIError.offline.errorDescription
        }
        isLoading = false
    }
}

/// 作品年表行。
struct FilmographyRow: Identifiable, Sendable {
    let summary: MediaSummary

    var id: String { "\(summary.mediaKind.rawValue)-\(summary.id)" }
    var year: Int { summary.year ?? 0 }
    var title: String { summary.title }
    var kindLabel: String { summary.mediaKind.label }

    init(summary: MediaSummary) {
        self.summary = summary
    }
}
