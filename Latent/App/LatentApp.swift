import SwiftUI
import SwiftData

/// 显影（Latent）—— macOS TMDB 元数据浏览器。
@main
struct LatentApp: App {
    /// SwiftData 本地容器（不启用 CloudKit）。
    private let modelContainer: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let container = LibraryContainerFactory.make()
        self.modelContainer = container
        _environment = State(initialValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: UI.Sizes.windowDefault.width, height: UI.Sizes.windowDefault.height)
        .commands { AppCommands() }

        // 设置窗口：⌘, 打开（原生 Settings scene；工具栏齿轮按钮也可打开）
        Settings {
            SettingsView()
                .environment(environment)
                .environment(environment.settings)
        }
    }
}

/// 根路由：无 Token → 全窗口引导页；有 Token → 主界面。
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings
    @State private var hasToken: Bool?

    var body: some View {
        Group {
            switch hasToken {
            case .none:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(UI.Palette.bg)
            case .some(false):
                OnboardingView(onFinished: { hasToken = true })
            case .some(true):
                MainSplitView()
                    .task {
                        // 冷启动不等待网络：先渲染骨架，连接验证异步进行
                        await appEnv.checkConnection()
                    }
            }
        }
        .background(UI.Palette.bg)
        .preferredColorScheme(settings.appearance.colorScheme)
        .overlay { ToastOverlay().environment(ToastCenter.shared) }
        .task {
            if hasToken == nil {
                hasToken = await KeychainStore.shared.hasToken()
            }
        }
    }
}
