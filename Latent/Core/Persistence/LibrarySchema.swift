import Foundation
import SwiftData

/// 版本化 Schema（设计文档第 6 节）：从 V1 起即版本化，为后续加字段（笔记、标签、个人评分）留迁移路径。
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [FavoriteItem.self, WatchlistItem.self, HistoryEntry.self]
    }
}

/// 迁移计划：V1 是起点，暂无旧版本；后续新增 Schema 版本时在此追加 stage。
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// 当前 Schema 类型别名，供容器与 Store 使用。
typealias CurrentLibrarySchema = LibrarySchemaV1
