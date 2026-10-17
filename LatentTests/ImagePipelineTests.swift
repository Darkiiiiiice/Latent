import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Latent

/// 图片管线：并发去重、下采样、磁盘缓存（设计文档第 11 节）。
@Suite("图片管线", .serialized)
struct ImagePipelineTests {

    /// 生成指定尺寸的 PNG 测试图。
    private func makePNG(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// 同步枚举目录（`DirectoryEnumerator` 的迭代器在异步上下文不可用，故独立为同步函数）。
    private func files(in directory: URL, extension ext: String? = nil) -> [URL] {
        var result: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if let ext, url.pathExtension != ext { continue }
                result.append(url)
            }
        }
        return result
    }

    private func makePipeline(maxBytes: Int64 = 512 * 1024 * 1024) -> (ImagePipeline, URL) {
        URLProtocolStub.reset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("latent-image-tests-\(UUID().uuidString)", isDirectory: true)
        let pipeline = ImagePipeline(
            session: URLProtocolStub.makeSession(),
            disk: DiskImageCache(directory: directory, maxBytes: maxBytes),
            baseURL: URL(string: "https://image.tmdb.org/t/p/")!
        )
        return (pipeline, directory)
    }

    @Test("同一 URL + 尺寸并发 10 次：只下载一次")
    func concurrentDedupe() async throws {
        let (pipeline, _) = makePipeline()
        let png = makePNG(width: 64, height: 96)
        URLProtocolStub.handler = { _ in URLProtocolStub.Response(body: png) }

        let images = try await withThrowingTaskGroup(of: CGImage.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await pipeline.image(for: "/poster.jpg", pixelSize: 342)
                }
            }
            var collected: [CGImage] = []
            for try await image in group {
                collected.append(image)
            }
            return collected
        }

        #expect(images.count == 10)
        #expect(URLProtocolStub.requestCount == 1)
    }

    @Test("磁盘缓存命中：第二次加载不产生网络请求")
    func diskCacheHit() async throws {
        let (pipeline, _) = makePipeline()
        let png = makePNG(width: 64, height: 96)
        URLProtocolStub.handler = { _ in URLProtocolStub.Response(body: png) }

        _ = try await pipeline.image(for: "/poster.jpg", pixelSize: 342)
        await pipeline.clearMemoryCache() // 只保留磁盘缓存
        _ = try await pipeline.image(for: "/poster.jpg", pixelSize: 342)

        #expect(URLProtocolStub.requestCount == 1)
    }

    @Test("失败自动重试一次，仍失败则抛错")
    func retryThenFail() async throws {
        let (pipeline, _) = makePipeline()
        URLProtocolStub.handler = { _ in .status(500) }

        await #expect(throws: (any Error).self) {
            _ = try await pipeline.image(for: "/missing.jpg", pixelSize: 342)
        }
        #expect(URLProtocolStub.requestCount == 2) // 首次 + 重试一次
    }

    @Test("损坏的磁盘缓存自愈（重新下载）")
    func corruptedDiskCache() async throws {
        let (pipeline, directory) = makePipeline()
        let png = makePNG(width: 64, height: 96)
        URLProtocolStub.handler = { _ in URLProtocolStub.Response(body: png) }

        _ = try await pipeline.image(for: "/poster.jpg", pixelSize: 342)
        #expect(URLProtocolStub.requestCount == 1)

        // 找到磁盘缓存文件并破坏内容，再清空内存缓存
        let cacheFiles = files(in: directory)
        for url in cacheFiles {
            try? Data("坏了".utf8).write(to: url)
        }
        #expect(cacheFiles.isEmpty == false)

        await pipeline.clearMemoryCache()
        _ = try await pipeline.image(for: "/poster.jpg", pixelSize: 342)
        #expect(URLProtocolStub.requestCount == 2) // 损坏缓存触发重新下载
    }

    @Test("磁盘缓存超限：LRU 清理最旧 20%")
    func diskLRU() async throws {
        let png = makePNG(width: 64, height: 96)
        // 上限 = 3 张图的体积：第 4 张开始必然超限，触发清理。
        let (pipeline, directory) = makePipeline(maxBytes: Int64(png.count) * 3)

        URLProtocolStub.handler = { request in
            // 每个路径返回同样的图（内容不重要，重要的是体积与数量）
            URLProtocolStub.Response(body: png)
        }
        for index in 0..<8 {
            _ = try await pipeline.image(for: "/poster-\(index).jpg", pixelSize: 342)
        }
        _ = URLProtocolStub.requestCount

        let fileCount = files(in: directory, extension: "img").count
        // 8 张 × 每张 >250B 远超 3 张上限，清理最旧 20% 后必然少于 8 个文件
        #expect(fileCount < 8)
    }

    @Test("像素尺寸分桶：对齐 TMDB 尺寸，Retina ×2")
    func pixelBuckets() {
        #expect(PixelBucket.pixelSize(forDisplayWidth: 168) == 342) // 336 → w342（网格海报）
        #expect(PixelBucket.pixelSize(forDisplayWidth: 250) == 500) // 500 → w500（详情海报）
        #expect(PixelBucket.pixelSize(forDisplayWidth: 640) == 1280) // 1280 → w1280（Hero）
        #expect(PixelBucket.pixelSize(forDisplayWidth: 1000) == 1280) // 超出上限 → 最大桶（TMDB 无 w2000）
    }

    @Test("尺寸段：桶 → w185 / w342 / w500 / w780 / w1280")
    func sizeNames() {
        #expect(PixelBucket.sizeName(forPixelSize: 185) == "w185")
        #expect(PixelBucket.sizeName(forPixelSize: 342) == "w342")
        #expect(PixelBucket.sizeName(forPixelSize: 500) == "w500")
        #expect(PixelBucket.sizeName(forPixelSize: 780) == "w780")
        #expect(PixelBucket.sizeName(forPixelSize: 1280) == "w1280")
        #expect(PixelBucket.sizeName(forPixelSize: 2000) == "w1280") // 上限收敛
    }

    @Test("图片地址：必须含 w<尺寸> 段（缺段即 404 的回归）")
    func imageURLKeepsSizeSegment() {
        let base = URL(string: "https://image.tmdb.org/t/p/")!
        #expect(
            ImagePipeline.imageURL(baseURL: base, path: "/poster.jpg", pixelSize: 342).absoluteString
                == "https://image.tmdb.org/t/p/w342/poster.jpg"
        )
        // 无前导斜杠同样成立
        #expect(
            ImagePipeline.imageURL(baseURL: base, path: "poster.jpg", pixelSize: 500).absoluteString
                == "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        // 传入非桶值时收敛到最近的更大桶；超上限收敛到 w1280
        #expect(
            ImagePipeline.imageURL(baseURL: base, path: "/poster.jpg", pixelSize: 100).absoluteString
                == "https://image.tmdb.org/t/p/w185/poster.jpg"
        )
        #expect(
            ImagePipeline.imageURL(baseURL: base, path: "/poster.jpg", pixelSize: 4096).absoluteString
                == "https://image.tmdb.org/t/p/w1280/poster.jpg"
        )
    }

    @Test("实际请求地址含尺寸段：不含则 404（回归）")
    func requestCarriesSizeSegment() async throws {
        let (pipeline, _) = makePipeline()
        let png = makePNG(width: 64, height: 96)
        URLProtocolStub.handler = { request in
            let url = request.url?.absoluteString ?? ""
            // 形如 …/t/p/w342/poster.jpg；缺尺寸段（曾经的真实 bug）时返回 404 → 用例失败
            guard url.range(of: "/t/p/w[0-9]+/", options: .regularExpression) != nil else {
                return .status(404)
            }
            return URLProtocolStub.Response(body: png)
        }

        _ = try await pipeline.image(for: "/poster.jpg", pixelSize: 342)
    }

    @Test("下采样：按最长边缩放")
    func downsample() async {
        let png = makePNG(width: 400, height: 600)
        let image = await ImagePipeline.downsample(data: png, maxPixelSize: 300)
        #expect(image != nil)
        #expect(image!.height == 300)
        #expect(image!.width == 200) // 保持 2:3 比例
    }

    @Test("非法图片数据：下采样返回 nil")
    func invalidData() async {
        let image = await ImagePipeline.downsample(data: Data("不是图片".utf8), maxPixelSize: 100)
        #expect(image == nil)
    }
}
