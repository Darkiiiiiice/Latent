import Foundation
import Security

/// Keychain 存取（设计文档第 4 节：`service = app.latent.tmdb`，`account = read_token`）。
///
/// 只存本机（不使用 iCloud 同步项）；Token 不写日志、不进数据库。
///
/// 说明：不使用 `kSecUseDataProtectionKeychain`——该路径要求签名带
/// `keychain-access-groups` / `application-identifier`（即需要 Team），
/// 自用构建是 ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），会直接返回
/// `errSecMissingEntitlement (-34018)`。传统登录钥匙串路径在沙箱 + ad-hoc 下可用。
actor KeychainStore {
    static let shared = KeychainStore()

    private let service: String
    private let account: String

    init(service: String = "app.latent.tmdb", account: String = "read_token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 读取 Token；不存在返回 nil。
    /// 注意：本类型是 actor，`shared` 的调用都在 async 上下文中，不会触发钥匙串 UI 弹窗。
    func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// 保存或更新 Token（空字符串视为删除）。
    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteToken()
            return
        }
        let data = Data(trimmed.utf8)

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var insertQuery = baseQuery
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Token 是否存在（引导页路由用，不读取内容本身）。
    func hasToken() -> Bool {
        (try? readToken())?.isEmpty == false
    }
}

/// Keychain 失败（带 OSStatus 便于排查；不打印 Token 内容）。
struct KeychainError: Error, Equatable, Sendable {
    let status: OSStatus

    var errorDescription: String {
        switch status {
        case errSecAuthFailed:
            return "钥匙串访问被拒绝（\(status)）：请在系统弹窗中选择「始终允许」后重试"
        case errSecUserCanceled:
            return "钥匙串访问被取消（\(status)）"
        case errSecInteractionNotAllowed:
            return "钥匙串当前不可用（\(status)）"
        default:
            return "钥匙串访问失败（\(status)）"
        }
    }
}
