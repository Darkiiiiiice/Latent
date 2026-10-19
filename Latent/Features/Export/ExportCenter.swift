import SwiftUI
import UniformTypeIdentifiers

/// 导出请求（FileExporter 的文档 + 类型 + 默认文件名）。
struct ExportRequest: Identifiable {
    let id = UUID()
    let document: ExportDocument
    let contentType: UTType
    let filename: String
}

/// `FileDocument` 包装：内容在生成时已确定，导出过程不访问网络。
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, UTType(filenameExtension: "md") ?? .plainText]
    }

    static var writableContentTypes: [UTType] {
        readableContentTypes
    }

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

/// 导出协调器：视图只提出「范围 + 格式」，根视图统一挂一个 `fileExporter`。
///
/// 纯本地操作；不读取 Token、不发起网络请求。
@MainActor
@Observable
final class ExportCenter {
    private(set) var request: ExportRequest?

    var isPresented: Bool {
        get { request != nil }
        set { if !newValue { request = nil } }
    }

    func prepare(
        scope: ExportScope,
        format: ExportFormat,
        favorites: [LibrarySnapshot],
        watchlist: [LibrarySnapshot],
        history: [LibrarySnapshot],
        language: String,
        date: Date = Date()
    ) {
        let export = LibraryExportBuilder.build(
            scope: scope,
            favorites: favorites,
            watchlist: watchlist,
            history: history,
            language: language,
            exportedAt: date
        )

        let data: Data
        switch format {
        case .json:
            do {
                data = try LibraryExportBuilder.jsonData(export)
            } catch {
                Log.export.error("JSON 导出编码失败：\(error.localizedDescription, privacy: .public)")
                return
            }
        case .markdown:
            data = Data(LibraryExportBuilder.markdown(export).utf8)
        }

        request = ExportRequest(
            document: ExportDocument(data: data),
            contentType: format.contentType,
            filename: LibraryExportBuilder.suggestedFilename(scope: scope, format: format, date: date)
        )
    }

    func clear() {
        request = nil
    }
}
