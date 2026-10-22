import CoreImage
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 动态显影分享卡（v1.36）：把最终卡面生成一段「显影过程」GIF。
///
/// 三阶段（全部基于最终卡面 + 纸底色合成，不改动七款版式内部）：
/// 1. 纸底上的幽灵像浮现（低亮度、去饱和）；
/// 2. 自上而下软边显影 wipe（读感近似文字与海报逐行浮现）；
/// 3. 饱和度与对比度从低到满（配色浮现）。
///
/// 规格：GIF 统一 **540 宽**（长边按比例），15fps、约 1.6 秒 24 帧，
/// 末帧停留 1 秒后无限循环；界面预览保持静态，动效只存在于导出文件。
enum ReceiptDeveloper {
    /// 动画规格。
    struct Spec: Sendable, Equatable {
        /// 输出宽度（GIF 按此宽等比缩放，控制文件体积）。
        var outputWidth: CGFloat = 540
        /// 帧率。
        var fps: Int = 15
        /// 动画时长（秒，不含末帧停留）。
        var duration: TimeInterval = 1.6
        /// 末帧停留（秒），随后循环。
        var finalHold: TimeInterval = 1.0
        /// 显影 wipe 的软边高度占画布比例。
        var featherFraction: CGFloat = 0.06

        var frameCount: Int { max(1, Int((duration * Double(fps)).rounded())) }
        var frameDelay: TimeInterval { 1.0 / Double(fps) }
    }

    /// 生成显影动画 GIF（异步只是为了 CIContext 渲染让出主线程，无网络请求）。
    @MainActor
    static func gifData(
        data: ReceiptData,
        style: ReceiptStyle,
        palette: ReceiptPalette,
        posterMode: ReceiptPosterMode,
        poster: CGImage?,
        layout: ReceiptLayout = .classic,
        aspect: ReceiptAspect = .portrait,
        tuning: ReceiptTuning = .standard,
        spec: Spec = Spec()
    ) -> Data? {
        // 1. 最终卡面（全分辨率渲染，交给 CI 处理）。
        guard let card = ReceiptRenderer.cgImage(
            data: data, style: style, palette: palette, posterMode: posterMode,
            poster: poster, layout: layout, aspect: aspect, tuning: tuning
        ) else { return nil }

        let width = spec.outputWidth
        let scale = width / aspect.size.width
        let outputSize = CGSize(width: width, height: aspect.size.height * scale)
        let extent = CGRect(origin: .zero, size: outputSize)

        let context = CIContext()
        let cardCI = CIImage(cgImage: card).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let paperNS = NSColor(palette.paper.color).usingColorSpace(.deviceRGB) ?? .white
        let paperColor = CIColor(
            red: paperNS.redComponent, green: paperNS.greenComponent, blue: paperNS.blueComponent
        )
        let paperCI = CIImage(color: paperColor).cropped(to: extent)

        // 2. 逐帧合成。
        var frames: [CGImage] = []
        for index in 0..<spec.frameCount {
            let t = spec.frameCount > 1 ? CGFloat(index) / CGFloat(spec.frameCount - 1) : 1
            let frame = composeFrame(
                cardCI: cardCI, paperCI: paperCI, extent: extent,
                progress: t, featherFraction: spec.featherFraction,
                ciContext: context
            )
            guard let frame else { return nil }
            frames.append(frame)
        }

        // 3. 编码 GIF：无限循环，末帧停留。
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        let loopProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, loopProperties as CFDictionary)

        for (index, frame) in frames.enumerated() {
            let isLast = index == frames.count - 1
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: isLast ? spec.finalHold : spec.frameDelay
                ]
            ]
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 单帧合成：色彩显影 + 自上而下软边 wipe。
    private static func composeFrame(
        cardCI: CIImage,
        paperCI: CIImage,
        extent: CGRect,
        progress: CGFloat,
        featherFraction: CGFloat,
        ciContext: CIContext
    ) -> CGImage? {
        // 阶段曲线：wipe 15%–70% 推进，配色 55%–100% 到位。
        let wipeT = min(1, max(0, (progress - 0.15) / 0.55))
        let colorT = min(1, max(0, (progress - 0.55) / 0.45))

        // 色彩显影：亮度整体从偏亮压回，饱和度与对比度从低到满。
        var filter = CIFilter(name: "CIColorControls")
        filter?.setValue(cardCI, forKey: kCIInputImageKey)
        filter?.setValue(colorT, forKey: kCIInputSaturationKey)
        filter?.setValue(0.18 * (1 - progress), forKey: kCIInputBrightnessKey)
        filter?.setValue(0.7 + 0.3 * colorT, forKey: kCIInputContrastKey)
        guard let developed = filter?.outputImage else { return nil }

        // 软边 wipe 遮罩：白色区域露出卡面，黑色区域留纸底。
        let revealHeight = extent.height * wipeT
        let feather = extent.height * featherFraction
        var gradient = CIFilter(name: "CILinearGradient")
        gradient?.setValue(CIVector(x: 0, y: extent.height - revealHeight), forKey: "inputPoint0")
        gradient?.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor0")
        gradient?.setValue(CIVector(x: 0, y: extent.height - revealHeight - feather), forKey: "inputPoint1")
        gradient?.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor1")
        guard let mask = gradient?.outputImage?.cropped(to: extent) else { return nil }

        var blend = CIFilter(name: "CIBlendWithMask")
        blend?.setValue(developed, forKey: kCIInputImageKey)
        blend?.setValue(paperCI, forKey: kCIInputBackgroundImageKey)
        blend?.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let composed = blend?.outputImage?.cropped(to: extent) else { return nil }

        return ciContext.createCGImage(composed, from: extent)
    }

    /// GIF 保存文件名：`显影-<片名>-显影.gif`。
    static func filename(title: String) -> String {
        let sanitized = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters))
            .joined(separator: "-")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "显影-显影.gif" : "显影-\(trimmed)-显影.gif"
    }
}

/// GIF 文档包装（`FileExporter` 保存显影动画用）。
struct ReceiptGIFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.gif] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
