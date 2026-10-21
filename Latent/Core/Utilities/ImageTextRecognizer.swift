import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 从图片里识别文字（v1.16「截图识别」）。
///
/// 用系统 Vision（0 第三方依赖），识别语言覆盖简中 / 英文；只读本地图片文件，
/// 不上传、不联网。解码用 ImageIO，避免把整个图读进内存再转格式。
enum ImageTextRecognizer {

    enum Failure: LocalizedError, Sendable {
        case unreadableImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "无法读取这张图片，请换一张再试"
            case .recognitionFailed(let message): return "文字识别失败：\(message)"
            }
        }
    }

    /// 识别图片中的文字，按读序（自上而下、自左而右）返回行文本；空行已剔除。
    ///
    /// 用户选中的文件在沙盒里需要安全作用域访问，这里自行成对持有 / 释放。
    static func lines(from url: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) { () throws -> [String] in
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Failure.unreadableImage
            }
            return try recognize(in: image)
        }.value
    }

    /// 直接对图片数据做识别（调用方已把内容读进内存时使用）。
    static func lines(from data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) { () throws -> [String] in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Failure.unreadableImage
            }
            return try recognize(in: image)
        }.value
    }

    /// 同步识别（已在后台线程时使用）。
    static func recognize(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw Failure.recognitionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
