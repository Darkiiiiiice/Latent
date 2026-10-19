import SwiftUI

/// 库页 / 历史页的导出菜单：当前范围 → JSON / Markdown（设计文档第 8.9 节）。
struct ExportMenu: View {
    let scope: ExportScope

    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        Menu {
            Button("导出为 JSON…") {
                appEnv.export(scope, as: .json)
            }
            Button("导出为 Markdown…") {
                appEnv.export(scope, as: .markdown)
            }
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("导出\(scope.title)（JSON / Markdown）")
        .accessibilityLabel("导出\(scope.title)")
    }
}
