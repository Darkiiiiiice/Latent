import Foundation
import OSLog

/// 图片磁盘缓存：`Caches/Latent/Images`，按最后访问时间 LRU，默认上限 512MB。
///
/// - 文件名 = 缓存键的 SHA256（每张图一个子目录，尺寸以文件名区分）。
/// - 超限时清理最旧 20%（设计文档第 7 节）。
/// - 所有读写都带容错：缓存失败不影响主流程。
actor DiskImageCache {
    struct Entry {
        let url: URL
        let size: Int64
    }

    private let directory: URL
    private let fileManager: FileManager
    private let maxBytes: Int64
    private let evictionRatio: Double = 0.2

    private var index: [String: Entry]? // 懒加载；key = 相对路径
    private var currentBytes: Int64 = 0

    init(directory: URL? = nil, fileManager: FileManager = .default, maxBytes: Int64 = 512 * 1024 * 1024) {
        self.directory = directory ?? CacheLocations.imageCacheDirectory
        self.fileManager = fileManager
        self.maxBytes = maxBytes
    }

    var isOverLimit: Bool {
        get async {
            loadIndexIfNeeded()
            return currentBytes > maxBytes
        }
    }

    /// 读取并刷新访问时间（LRU 依据）。
    func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, forKey key: String) {
        let url = fileURL(forKey: key)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            // 先建立索引，否则 evictIfNeeded 会因 index == nil 静默跳过，LRU 失效。
            loadIndexIfNeeded()
            index?[key] = Entry(url: url, size: Int64(data.count))
            currentBytes += Int64(data.count)
            evictIfNeeded()
        } catch {
            Log.images.warning("图片缓存写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(forKey key: String) {
        let url = fileURL(forKey: key)
        try? fileManager.removeItem(at: url)
        if let entry = index?[key] {
            currentBytes -= entry.size
        }
        index?[key] = nil
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        index = [:]
        currentBytes = 0
    }

    func sizeInBytes() async -> Int64 {
        loadIndexIfNeeded()
        return currentBytes
    }

    // MARK: - 内部

    private func fileURL(forKey key: String) -> URL {
        let hash = CacheKey.hash(key)
        let shard = String(hash.prefix(2))
        return directory
            .appendingPathComponent(shard, isDirectory: true)
            .appendingPathComponent(hash + ".img")
    }

    private func loadIndexIfNeeded() {
        guard index == nil else { return }
        // 不用 FileManager.enumerator（异步上下文不可用）：两层目录直接枚举。
        var newIndex: [String: Entry] = [:]
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]

        let shards = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for shard in shards {
            let files = (try? fileManager.contentsOfDirectory(at: shard, includingPropertiesForKeys: Array(keys))) ?? []
            for file in files {
                guard let values = try? file.resourceValues(forKeys: keys),
                      values.isRegularFile == true else { continue }
                let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
                let size = Int64(values.fileSize ?? 0)
                newIndex[relative] = Entry(url: file, size: size)
                total += size
            }
        }
        index = newIndex
        currentBytes = total
    }

    /// 超限时按最后修改（≈最后访问）时间清理最旧 20%。
    private func evictIfNeeded() {
        guard index != nil else { return }
        guard currentBytes > maxBytes else { return }

        let sorted = (index ?? [:]).sorted { lhs, rhs in
            let lDate = (try? lhs.value.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.value.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate < rDate
        }
        let targetRemoval = max(1, Int(Double(sorted.count) * evictionRatio))
        for (key, entry) in sorted.prefix(targetRemoval) {
            try? fileManager.removeItem(at: entry.url)
            currentBytes -= entry.size
            index?[key] = nil
        }
        Log.images.info("图片磁盘缓存超限，已清理 \(targetRemoval) 个最旧条目（当前 \(self.currentBytes) 字节）")
    }
}
