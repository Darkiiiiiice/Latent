import SwiftUI

/// 首次启动引导页：三步说明（申请 Token → 粘贴 → 验证）（设计文档第 8.6 节）。
struct OnboardingView: View {
    /// 验证通过后回调（根视图切到主界面）。
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var appEnv
    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let applyURL = URL(string: "https://www.themoviedb.org/settings/api")!

    var body: some View {
        VStack(spacing: UI.Spacing.s8) {
            header
            steps
            tokenForm
            hint
        }
        .frame(maxWidth: 560)
        .padding(UI.Spacing.s8 * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UI.Palette.bg)
    }

    private var header: some View {
        VStack(spacing: UI.Spacing.s2) {
            Text("显影")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(UI.Palette.textPrimary)
            Text("Latent · TMDB 元数据浏览器")
                .font(.system(size: 12))
                .foregroundStyle(UI.Palette.textSecondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            stepRow(index: 1, title: "申请 API 凭据", detail: "在 TMDB 官网免费注册并申请 API，取得「Read Access Token」。")
            stepRow(index: 2, title: "粘贴 Token", detail: "把 Token 粘贴到下方输入框；只保存在本机钥匙串。")
            stepRow(index: 3, title: "验证并开始", detail: "应用会调用 TMDB 接口验证；通过后即可使用。")
        }
        .padding(UI.Spacing.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UI.Palette.surface, in: RoundedRectangle(cornerRadius: UI.Radius.button, style: .continuous))
        .hairlineBorder(UI.Palette.border, radius: UI.Radius.button)
    }

    private func stepRow(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: UI.Spacing.s3) {
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(UI.Palette.accentText)
                .frame(width: 18, height: 18)
                .background(UI.Palette.accent, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UI.Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tokenForm: some View {
        VStack(alignment: .leading, spacing: UI.Spacing.s3) {
            SecureField("粘贴 TMDB Read Access Token", text: $token)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit { Task { await validate() } }

            HStack(spacing: UI.Spacing.s3) {
                Button {
                    Task { await validate() }
                } label: {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("验证并开始")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

                Link("在 TMDB 官网申请 →", destination: applyURL)
                    .font(.system(size: 12))

                Spacer(minLength: 0)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.warning)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.Palette.success)
            }
        }
    }

    private var hint: some View {
        Text("Token 仅存于本机钥匙串，不同步 iCloud，也不会写入日志。")
            .font(.system(size: 11))
            .foregroundStyle(UI.Palette.textSecondary)
    }

    private func validate() async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isValidating = true
        errorMessage = nil
        successMessage = nil
        defer { isValidating = false }

        do {
            try await KeychainStore.shared.saveToken(trimmed)
        } catch {
            errorMessage = "保存到钥匙串失败：\((error as? KeychainError)?.errorDescription ?? error.localizedDescription)"
            return
        }

        do {
            // 验证：GET /3/configuration
            _ = try await appEnv.client.validateToken()
            successMessage = "验证通过，正在进入显影…"
            await appEnv.checkConnection()
            onFinished()
        } catch let error as APIError {
            errorMessage = error.errorDescription
            // 验证失败不保留无效 Token，避免下次启动卡在坏状态
            try? await KeychainStore.shared.deleteToken()
        } catch {
            errorMessage = "验证失败：\(error.localizedDescription)"
            try? await KeychainStore.shared.deleteToken()
        }
    }
}
