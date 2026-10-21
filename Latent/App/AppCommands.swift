import SwiftUI

/// 菜单与快捷键（设计文档第 8.7 节）。
struct AppCommands: Commands {
    var body: some Commands {
        // 侧边栏范围快捷键：⌘1 趋势、⌘2 发现、⌘3 收藏、⌘4 观看清单、⌘5 历史、⌘6 统计
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(SidebarScope.allCases) { scope in
                Button(scope.title) {
                    AppCommandBus.select(scope)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(scope.shortcutIndex)")), modifiers: .command)
            }
        }

        // 视图菜单：刷新 / 返回 / 搜索
        CommandGroup(after: .toolbar) {
            Divider()
            Button("刷新") {
                NotificationCenter.default.post(name: AppCommandBus.refresh, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("返回") {
                NotificationCenter.default.post(name: AppCommandBus.back, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)

            Divider()

            Button("搜索…") {
                NotificationCenter.default.post(name: AppCommandBus.focusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // 文件菜单：从图片识别（截图） + 导出全部库（本地 JSON / Markdown）
        CommandGroup(after: .saveItem) {
            Button("从图片识别…") {
                NotificationCenter.default.post(name: AppCommandBus.recognizeImage, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("导出全部库为 JSON…") {
                NotificationCenter.default.post(name: AppCommandBus.exportAllJSON, object: nil)
            }
            Button("导出全部库为 Markdown…") {
                NotificationCenter.default.post(name: AppCommandBus.exportAllMarkdown, object: nil)
            }
        }

        // 帮助菜单：关于显影 + TMDB 署名
        CommandGroup(replacing: .help) {
            Link("关于显影", destination: URL(string: "https://www.themoviedb.org")!)
            Divider()
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
        }
    }
}
