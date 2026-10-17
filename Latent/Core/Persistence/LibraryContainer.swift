import Foundation
import SwiftData
import OSLog

/// SwiftData 本地容器（不启用 CloudKit）。
///
/// - 容器损坏或迁移失败：备份并重建，不崩溃、不静默丢数据（设计文档第 6 节）。
/// - 单测用 `makeInMemory()`（覆盖迁移与 Store 逻辑）。
enum LibraryContainerFactory {
    /// 正式容器（磁盘）。
    static func make() -> ModelContainer {
        let schema = Schema(CurrentLibrarySchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
        } catch {
            Log.store.error("SwiftData 容器打开失败，尝试备份并重建：\(error.localizedDescription, privacy: .public)")
        }

        // 兜底：把现有库文件备份到一旁，重建空容器
        backupExistingStore()
        do {
            return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
        } catch {
            // 仍失败说明环境异常（磁盘满 / 权限），明确崩溃以便排查，不静默丢数据
            fatalError("SwiftData 容器无法创建：\(error)")
        }
    }

    /// 内存容器（单测 / 预览）。
    static func makeInMemory() -> ModelContainer {
        let schema = Schema(CurrentLibrarySchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
        } catch {
            fatalError("内存 ModelContainer 创建失败：\(error)")
        }
    }

    /// 备份现有库文件（附带时间戳），不删除数据。
    private static func backupExistingStore() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDir = support.appendingPathComponent("LatentBackup-\(stamp)", isDirectory: true)

        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let source = support.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: backupDir.appendingPathComponent(name))
            } catch {
                Log.store.error("备份 \(name, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)")
            }
        }
        Log.store.warning("已备份原容器至 \(backupDir.path, privacy: .public)")
    }
}
