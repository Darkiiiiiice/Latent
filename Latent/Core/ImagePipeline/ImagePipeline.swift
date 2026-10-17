import Foundation
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// 图片管线（actor）——纯原生替代 Nuke / Kingfisher 的常用能力（设计文档第 7 节）。
///
/// 流程：
/// ```
/// load(path:displayWidth:)
///   → 像素尺寸分桶（对齐 TMDB 提供尺寸，避免无界缓存键）
///   → 内存缓存命中？返回
///   → 磁盘缓存命中？（ImageIO 校验并解码）
///   → in-flight 去重（同 URL + 尺寸共享同一 Task）
///   → 下载 → ImageIO 下采样 → 双写缓存 → 返回
/// ```
/// - 取消：调用方取消任务即传播；取消不产生缓存写入。
/// - 失败：占位由视图层决定，管线本身只抛错。
actor ImagePipeline {
    static let shared = ImagePipeline()

    /// 内存缓存：NSCache<NSString, AnyObject>，按解码字节数计 cost。
    private final class MemoryCache: @unchecked Sendable {
        let cache = NSCache<NSString, CachedImageBox>()
        init() {
            cache.countLimit = 400
            cache.totalCostLimit = 256 * 1024 * 1024
        }
    }

    private final class CachedImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let memory = MemoryCache()
    private let sessions: SessionProvider
    private let disk: DiskImageCache
    private let baseURL: URL

    /// in-flight 去重：同 (path, 像素尺寸) 共享同一个加载任务。
    private var inFlight: [String: Task<CGImage, any Error>] = [:]

    /// URL → 原始文件大小（用于磁盘告警日志；不参与逻辑）。
    private var needsDiskSweep = false

    init(session: URLSession? = nil, sessions: SessionProvider? = nil, disk: DiskImageCache? = nil, baseURL: URL? = nil) {
        if let sessions {
            self.sessions = sessions
        } else if let session {
            self.sessions = SessionProvider(fixed: session)
        } else {
            self.sessions = SessionProvider(configuration: Self.makeConfiguration)
        }
        self.disk = disk ?? DiskImageCache()
        self.baseURL = baseURL ?? URL(string: "https://image.tmdb.org/t/p/")!
    }

    /// 基础会话配置（代理由 `SessionProvider` 按当前设置注入）。
    nonisolated static func makeConfiguration(proxy: ProxyConfiguration) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "image/*"]
        configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        return configuration
    }

    // MARK: - 对外入口

    /// 加载图片并按展示宽度下采样（Retina ×2）。
    ///
    /// - Parameters:
    ///   - path: TMDB `file_path`（形如 `/abc.jpg`）。
    ///   - displayWidth: 界面上的逻辑宽度（pt）。
    func image(for path: String, displayWidth: CGFloat) async throws -> CGImage {
        let pixelSize = PixelBucket.pixelSize(forDisplayWidth: displayWidth)
        return try await image(for: path, pixelSize: pixelSize)
    }

    func image(for path: String, pixelSize: Int) async throws -> CGImage {
        let key = CacheKey.imageKey(path: path, pixelSize: pixelSize)

        if let hit = memory.cache.object(forKey: key as NSString)?.image {
            return hit
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<CGImage, any Error> { [weak self] in
            guard let self else { throw CancellationError() }
            defer { Task { await self.finish(key: key) } }
            return try await self.produce(path: path, pixelSize: pixelSize, key: key)
        }
        inFlight[key] = task
        return try await task.value
    }

    private func finish(key: String) {
        inFlight[key] = nil
    }

    // MARK: - 生产与缓存

    private func produce(path: String, pixelSize: Int, key: String) async throws -> CGImage {
        try Task.checkCancellation()

        // 1) 磁盘缓存
        if let data = await disk.data(forKey: key) {
            if let image = await Self.downsample(data: data, maxPixelSize: pixelSize) {
                storeInMemory(image, key: key, pixelSize: pixelSize)
                return image
            }
            // 损坏文件自愈
            await disk.remove(forKey: key)
        }

        // 2) 网络下载（最多自动重试一次）
        let url = makeURL(path: path, pixelSize: pixelSize)
        var lastError: (any Error)?
        for attempt in 1...2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await sessions.session().data(from: url)
                try Task.checkCancellation()

                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard (200..<300).contains(status) else {
                    throw APIError.serverError(status: status)
                }
                guard let image = await Self.downsample(data: data, maxPixelSize: pixelSize) else {
                    throw ImagePipelineError.invalidImageData
                }
                // 取消不产生缓存写入；写盘失败不影响返回
                await disk.store(data, forKey: key)
                storeInMemory(image, key: key, pixelSize: pixelSize)
                return image
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 1 {
                    try await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
        throw lastError ?? ImagePipelineError.invalidImageData
    }

    private func storeInMemory(_ image: CGImage, key: String, pixelSize: Int) {
        let cost = image.bytesPerRow * image.height
        memory.cache.setObject(CachedImageBox(image), forKey: key as NSString, cost: cost)
    }

    private func makeURL(path: String, pixelSize: Int) -> URL {
        Self.imageURL(baseURL: baseURL, path: path, pixelSize: pixelSize)
    }

    /// 图片地址 = `base_url` + `w<尺寸段>` + `file_path`（设计文档第 4 节）。
    ///
    /// 尺寸段**不可省略**：`…/t/p/{file_path}` 一律 404。
    nonisolated static func imageURL(baseURL: URL, path: String, pixelSize: Int) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL
            .appendingPathComponent(PixelBucket.sizeName(forPixelSize: pixelSize))
            .appendingPathComponent(trimmed)
    }

    /// ImageIO 下采样（`CGImageSourceCreateThumbnailAtIndex`），避免全尺寸解码。
    nonisolated static func downsample(data: Data, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }

    /// 内存警告：清空内存缓存（磁盘不受影响）。
    func clearMemoryCache() {
        memory.cache.removeAllObjects()
        Log.images.info("图片内存缓存已清空")
    }

    func clearDiskCache() async {
        await disk.clear()
        needsDiskSweep = false
        Log.images.info("图片磁盘缓存已清空")
    }

    func diskSizeInBytes() async -> Int64 {
        await disk.sizeInBytes()
    }

    /// 磁盘超限提示（设置页展示）。
    func diskUsageWarning() async -> Bool {
        await disk.isOverLimit
    }
}

enum ImagePipelineError: Error, Sendable {
    case invalidImageData
}

/// 像素尺寸分桶：把展示宽度（×2 Retina）映射到对齐 TMDB 的固定桶，
/// 限制内存/磁盘缓存键数量，同时在视网膜屏上保留足够清晰度。
///
/// 桶与 TMDB 尺寸段一一对应（`185 → w185`、`1280 → w1280`）；TMDB 无 `w2000`，
/// 故最大桶取 1280（设计文档第 4 节）。
enum PixelBucket {
    static let buckets: [Int] = [185, 342, 500, 780, 1280]

    static func pixelSize(forDisplayWidth width: CGFloat) -> Int {
        let desired = Int((width * 2).rounded())
        return buckets.first(where: { $0 >= desired }) ?? buckets[buckets.count - 1]
    }

    /// 桶 → TMDB 尺寸段名（`w185` / `w342` / `w500` / `w780` / `w1280`）。
    static func sizeName(forPixelSize pixelSize: Int) -> String {
        let bucket = buckets.first(where: { $0 >= pixelSize }) ?? buckets[buckets.count - 1]
        return "w\(bucket)"
    }
}
