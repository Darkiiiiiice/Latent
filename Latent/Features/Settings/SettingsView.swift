import SwiftUI

/// 设置页（设计文档第 8.6 节）：原生 `Form` —— 常规 / 网络 / 缓存 / 关于。
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(AppSettings.self) private var settings

    enum Tab: String, CaseIterable, Identifiable {
        case general, network, cache, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "常规"
            case .network: return "网络"
            case .cache: return "缓存"
            case .about: return "关于"
            }
        }
        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .network: return "network"
            case .cache: return "internaldrive"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: Tab = .general
    @State private var tokenInput = ""
    @State private var isVerifying = false
    @State private var verificationMessage: String?
    @State private var verificationSucceeded = false
    @State private var apiCacheSize: Int64 = 0
    @State private var imageCacheSize: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(UI.Spacing.s4)

            Divider().overlay(UI.Palette.border)

            Form {
                switch tab {
                case .general: generalSection
                case .network: networkSection
                case .cache: cacheSection
                case .about: aboutSection
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 460)
        .background(UI.Palette.bg)
        .task {
            await refreshCacheSizes()
            tokenInput = ""
        }
    }

    // MARK: - 常规

    @ViewBuilder
    private var generalSection: some View {
        Section("元数据语言") {
            Picker("语言", selection: Bindable(settings).language) {
                ForEach(AppSettings.availableLanguages, id: \.self) { code in
                    Text(Formatters.languageLabel(code)).tag(code)
                }
            }
            .pickerStyle(.segmented)
            Text("切换后重新打开页面即可看到新语言的标题与简介。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }

        Section("外观") {
            Picker("主题", selection: Bindable(settings).appearance) {
                ForEach(AppSettings.AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("默认跟随系统；海报是界面上唯一的大色块。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }

        Section("搜索") {
            HStack {
                Text("最近搜索")
                Spacer()
                Text("\(settings.recentSearches.count) / \(AppSettings.recentSearchesLimit)")
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Button("清空最近搜索") {
                settings.clearRecentSearches()
                ToastCenter.shared.show("已清空最近搜索")
            }
            .disabled(settings.recentSearches.isEmpty)
        }

        Section("数据") {
            Text("导出收藏、观看清单与浏览历史，不包含 Token、代理与缓存。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)

            HStack(spacing: UI.Spacing.s3) {
                Button("导出全部（JSON）…") {
                    appEnv.export(.all, as: .json)
                }
                Button("导出全部（Markdown）…") {
                    appEnv.export(.all, as: .markdown)
                }
            }
        }
    }

    // MARK: - 网络

    @ViewBuilder
    private var networkSection: some View {
        Section("TMDB Read Access Token") {
            SecureField("粘贴新的 Token（留空则不修改）", text: $tokenInput)
                .font(.system(size: 12, design: .monospaced))

            HStack(spacing: UI.Spacing.s3) {
                Button {
                    Task { await verifyAndSave() }
                } label: {
                    if isVerifying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("验证并保存")
                    }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)

                Button("移除 Token") {
                    Task {
                        try? await KeychainStore.shared.deleteToken()
                        appEnv.connectionState = .unknown
                        verificationMessage = "已移除 Token"
                        verificationSucceeded = false
                        ToastCenter.shared.show("已移除 Token")
                    }
                }
            }

            if let verificationMessage {
                Label(verificationMessage, systemImage: verificationSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(verificationSucceeded ? UI.Palette.success : UI.Palette.warning)
            }
        }

        Section("代理") {
            Picker("模式", selection: Bindable(settings).proxy.mode) {
                ForEach(ProxyConfiguration.Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.proxy.mode == .manual {
                Picker("类型", selection: Bindable(settings).proxy.kind) {
                    ForEach(ProxyConfiguration.Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("主机") {
                    TextField("127.0.0.1", text: Bindable(settings).proxy.host)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 180)
                }
                LabeledContent("端口") {
                    TextField("7890", value: Bindable(settings).proxy.port, format: .number)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 80)
                }
            }

            Label(settings.proxy.summary, systemImage: settings.proxy.isUsable || settings.proxy.mode == .system ? "arrow.triangle.branch" : "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(settings.proxy.mode == .manual && !settings.proxy.isUsable ? UI.Palette.warning : UI.Palette.textSecondary)

            Text("改动立即生效（无需重启），API 与图片请求都走这里；只影响本 App，不改系统设置。改完点下方「重新验证」确认连通性；不支持代理认证与 PAC。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
        .onChange(of: settings.proxy) { _, _ in
            appEnv.connectionState = .unknown
        }

        Section("连接状态") {
            HStack(spacing: UI.Spacing.s2) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text(connectionLabel)
                Spacer()
                Button("重新验证") {
                    Task { await appEnv.checkConnection() }
                }
                .controlSize(.small)
            }
            Text("Token 仅存本机钥匙串；网络请求仅发往 api.themoviedb.org 与 image.tmdb.org（可经代理）。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    private var connectionColor: Color {
        switch appEnv.connectionState {
        case .connected: return UI.Palette.success
        case .failed: return UI.Palette.error
        case .unknown: return UI.Palette.textSecondary
        }
    }

    private var connectionLabel: String {
        switch appEnv.connectionState {
        case .connected: return "TMDB 已连接"
        case .failed(let message): return message
        case .unknown: return "未验证"
        }
    }

    // MARK: - 缓存

    @ViewBuilder
    private var cacheSection: some View {
        Section("API 响应缓存") {
            HStack {
                Text("占用")
                Spacer()
                Text(Formatters.bytes(apiCacheSize))
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Button("清除 API 响应缓存") {
                Task {
                    await appEnv.apiCache.clear()
                    await refreshCacheSizes()
                    ToastCenter.shared.show("API 缓存已清除")
                }
            }
        }

        Section("图片缓存") {
            HStack {
                Text("磁盘占用")
                Spacer()
                Text("\(Formatters.bytes(imageCacheSize)) / 512 MB")
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            HStack {
                Text("内存缓存")
                Spacer()
                Text("上限 256 MB")
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Button("清除图片缓存") {
                Task {
                    await appEnv.imagePipeline.clearDiskCache()
                    await appEnv.imagePipeline.clearMemoryCache()
                    await refreshCacheSizes()
                    ToastCenter.shared.show("图片缓存已清除")
                }
            }
            Button("清除全部缓存") {
                Task {
                    await appEnv.apiCache.clear()
                    await appEnv.imagePipeline.clearDiskCache()
                    await refreshCacheSizes()
                    ToastCenter.shared.show("缓存已清空")
                }
            }
            Text("缓存不入库；超限时按最后访问时间自动清理。")
                .font(.system(size: 11))
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    // MARK: - 关于

    @ViewBuilder
    private var aboutSection: some View {
        Section("应用") {
            HStack {
                Text("显影 Latent")
                Spacer()
                Text(versionText)
                    .monospacedDigit()
                    .foregroundStyle(UI.Palette.textSecondary)
            }
            Text("macOS 上的 TMDB 元数据浏览器：搜索电影、剧集与人物，浏览趋势与筛选发现，收藏并管理自己的观看清单。")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
        }

        Section("数据与隐私") {
            Text("无账号、无遥测；收藏、清单与历史只保存在本机；Token 仅存本机钥匙串。")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
        }

        Section("TMDB") {
            // 合规要求：固定展示，不得改写
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textPrimary)
                .textSelection(.enabled)

            Link("TMDB 官网", destination: URL(string: "https://www.themoviedb.org")!)
            Link("TMDB 使用条款", destination: URL(string: "https://www.themoviedb.org/documentation/api/terms-of-use")!)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.34.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "46"
        return "\(version)（\(build)）"
    }

    // MARK: - 动作

    private func verifyAndSave() async {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isVerifying = true
        verificationMessage = nil
        defer { isVerifying = false }

        do {
            try await KeychainStore.shared.saveToken(trimmed)
        } catch {
            verificationSucceeded = false
            verificationMessage = "保存失败：\((error as? KeychainError)?.errorDescription ?? error.localizedDescription)"
            return
        }

        await appEnv.checkConnection()
        switch appEnv.connectionState {
        case .connected:
            verificationSucceeded = true
            verificationMessage = "验证通过，Token 已保存"
            tokenInput = ""
            ToastCenter.shared.show("Token 已验证并保存")
        case .failed(let message):
            verificationSucceeded = false
            verificationMessage = message
        case .unknown:
            verificationSucceeded = false
            verificationMessage = "验证失败"
        }
    }

    private func refreshCacheSizes() async {
        apiCacheSize = await appEnv.apiCache.sizeInBytes()
        imageCacheSize = await appEnv.imagePipeline.diskSizeInBytes()
    }
}
