import Foundation
import CryptoKit

/// 缓存键：端点 + 参数（含 language）的 SHA256（设计文档第 4 节）。
enum CacheKey {
    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 响应缓存键 = 完整 URL 的哈希（URL 已含端点、参数与 language）。
    static func responseKey(for url: URL) -> String {
        hash(url.absoluteString)
    }

    /// 图片缓存键 = file_path + 尺寸（下采样后的像素尺寸）。
    static func imageKey(path: String, pixelSize: Int) -> String {
        hash("\(path)|\(pixelSize)")
    }
}

/// 响应缓存协议（客户端只依赖这一层；测试可注入替身）。
protocol ResponseCacheProtocol: Sendable {
    func data(forKey key: String, maxAge: TimeInterval) async -> Data?
    func store(_ payload: Data, forKey key: String) async
}

/// 磁盘 JSON 缓存（响应级），带写入时间戳与 TTL。
///
/// 只面向 `Caches/Latent/API` 目录；缓存不入库（设计文档第 6 节）。
actor ResponseCache: ResponseCacheProtocol {
    private let directory: URL
    private let fileManager: FileManager
    private var didPrepareDirectory = false

    init(directory: URL? = nil) {
        let base = directory ?? CacheLocations.apiCacheDirectory
        self.directory = base
        self.fileManager = FileManager.default
    }

    private struct Envelope: Codable {
        let storedAt: Date
        let payload: Data
    }

    /// 读取并校验 TTL；过期或损坏视为未命中（损坏文件顺手清理）。
    func data(forKey key: String, maxAge: TimeInterval) -> Data? {
        let url = fileURL(forKey: key)
        guard let raw = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: raw) else {
            Log.network.warning("响应缓存文件损坏，已清理：\(key, privacy: .public)")
            try? fileManager.removeItem(at: url)
            return nil
        }

        guard Date().timeIntervalSince(envelope.storedAt) < maxAge else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return envelope.payload
    }

    func store(_ payload: Data, forKey key: String) {
        prepareDirectoryIfNeeded()
        let envelope = Envelope(storedAt: Date(), payload: payload)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(envelope) else { return }
        try? raw.write(to: fileURL(forKey: key), options: .atomic)
    }

    /// 清理过期条目（按各数据类型的最大 TTL 判断），返回清理的条目数。
    @discardableResult
    func purgeExpired(maxAge: TimeInterval = CacheTTL.settings) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var removed = 0
        let now = Date()
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let raw = try? Data(contentsOf: url),
                  let envelope = try? decoder.decode(Envelope.self, from: raw) else {
                try? fileManager.removeItem(at: url)
                removed += 1
                continue
            }
            if now.timeIntervalSince(envelope.storedAt) > maxAge {
                try? fileManager.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        didPrepareDirectory = false
        Log.network.info("已清空 API 响应缓存")
    }

    func sizeInBytes() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    private func prepareDirectoryIfNeeded() {
        guard !didPrepareDirectory else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        didPrepareDirectory = true
    }
}

/// 缓存目录（设计文档第 6 节：`Caches/Latent/…`）。
enum CacheLocations {
    static var root: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Latent", isDirectory: true)
    }

    static var apiCacheDirectory: URL {
        root.appendingPathComponent("API", isDirectory: true)
    }

    static var imageCacheDirectory: URL {
        root.appendingPathComponent("Images", isDirectory: true)
    }
}
