import Foundation
import SwiftData

/// 库条目的统一形态（收藏 / 观看清单 / 历史共用字段）。
///
/// 设计文档第 6 节：去重键 = `(mediaType, tmdbID)`；属性可选或带默认值。
/// 详情富化字段（`genreNames` 起）自 Schema V2 加入，供统计页纯本地计算。
protocol LibraryModel: AnyObject {
    var mediaType: String { get set }
    var tmdbID: Int { get set }
    var title: String { get set }
    var originalTitle: String? { get set }
    var year: Int? { get set }
    var posterPath: String? { get set }
    var voteAverage: Double? { get set }
    var addedAt: Date { get set }

    // MARK: 详情富化（V2）
    var genreNames: [String]? { get set }
    var runtime: Int? { get set }
    var director: String? { get set }
    var topCast: [String]? { get set }
    var countries: [String]? { get set }
    var budget: Int64? { get set }
    var revenue: Int64? { get set }
    /// 详情回填时间；nil 表示尚未富化（统计页会提示还有多少条待补）。
    var detailFetchedAt: Date? { get set }

    // MARK: 详情富化（V3）
    /// 评分人数，用于「冷门 / 大众指数」——只有均分不足以判断一部片是否小众。
    var voteCount: Int? { get set }
}

extension LibraryModel {
    var mediaKind: MediaKind { MediaKind(tmdbValue: mediaType) }
}

/// 详情富化字段（Schema V2 / V3）。
///
/// 收藏 / 入清单时从详情页已有数据顺手写入，不额外发请求；
/// 旧数据由启动时的回填任务补齐（见 `LibraryStore.backfillDetails`）。
struct LibraryDetails: Sendable, Equatable {
    var genreNames: [String] = []
    var runtime: Int?
    var director: String?
    var topCast: [String] = []
    var countries: [String] = []
    var budget: Int64?
    var revenue: Int64?
    /// 评分人数（V3）。
    var voteCount: Int?

    init(
        genreNames: [String] = [],
        runtime: Int? = nil,
        director: String? = nil,
        topCast: [String] = [],
        countries: [String] = [],
        budget: Int64? = nil,
        revenue: Int64? = nil,
        voteCount: Int? = nil
    ) {
        self.genreNames = genreNames
        self.runtime = runtime
        self.director = director
        self.topCast = topCast
        self.countries = countries
        self.budget = budget
        self.revenue = revenue
        self.voteCount = voteCount
    }

    /// 电影详情映射。TMDB 未提供预算 / 票房时返回 0，这里视作「没有数据」。
    init(movie: MovieDetail) {
        self.genreNames = (movie.genres ?? []).map(\.name)
        self.runtime = movie.runtime
        self.director = movie.credits?.crew?.first(where: { $0.job == "Director" })?.name
        self.topCast = (movie.credits?.cast ?? []).prefix(5).map(\.name)
        self.countries = movie.productionCountries?.map(\.iso3166_1)
            ?? movie.originCountry
            ?? []
        self.budget = (movie.budget ?? 0) > 0 ? Int64(movie.budget ?? 0) : nil
        self.revenue = (movie.revenue ?? 0) > 0 ? Int64(movie.revenue ?? 0) : nil
        self.voteCount = movie.voteCount
    }

    /// 剧集详情映射：时长取单集时长，导演位取主创。
    init(tv: TVShowDetail) {
        self.genreNames = (tv.genres ?? []).map(\.name)
        self.runtime = tv.episodeRunTime?.first
        let creators = (tv.createdBy ?? []).prefix(2).map(\.name)
        self.director = creators.isEmpty ? nil : creators.joined(separator: " / ")
        self.topCast = (tv.credits?.cast ?? []).prefix(5).map(\.name)
        self.countries = tv.originCountry ?? []
        self.budget = nil
        self.revenue = nil
        self.voteCount = tv.voteCount
    }

    /// 把字段写进具体模型（抽取自三个模型各自的分支）。
    func apply(to model: any LibraryModel, fetchedAt: Date = Date()) {
        model.genreNames = genreNames.isEmpty ? nil : genreNames
        model.runtime = runtime
        model.director = director
        model.topCast = topCast.isEmpty ? nil : topCast
        model.countries = countries.isEmpty ? nil : countries
        model.budget = budget
        model.revenue = revenue
        model.voteCount = voteCount
        model.detailFetchedAt = fetchedAt
    }
}
