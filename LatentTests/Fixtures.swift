import Foundation

/// 读取测试 bundle 中的 fixture JSON。
enum Fixtures {
    static func data(_ name: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json") else {
            fatalError("缺少 fixture：\(name).json")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("读取 fixture 失败 \(name).json：\(error)")
        }
    }

    /// 小尺寸 PNG（1×1 透明），用于图片管线测试。
    static var pngData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    }
}

private final class BundleToken {}
