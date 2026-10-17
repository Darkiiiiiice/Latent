import Foundation
import Testing
@testable import Latent

/// Keychain 存取（设计文档第 4 节、第 12 节）。
///
/// 这些用例运行在**真实环境**里：测试宿主就是 App 本体（App Sandbox + ad-hoc 签名），
/// 因此能覆盖「无 Team 签名下钥匙串是否可用」这一环境相关问题——
/// 数据保护钥匙串（`kSecUseDataProtectionKeychain`）在该环境下会返回 -34018。
@Suite("钥匙串", .timeLimit(.minutes(1)))
struct KeychainStoreTests {

    /// 专用 service，避免碰到真实 Token。
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "app.latent.tests", account: "read_token")
    }

    @Test("保存 → 读取 → 更新 → 删除 全链路")
    func roundTrip() async throws {
        let store = makeStore()
        try await store.deleteToken()          // 清理历史残留
        #expect(try await store.readToken() == nil)
        #expect(await store.hasToken() == false)

        try await store.saveToken("token-1")
        #expect(try await store.readToken() == "token-1")
        #expect(await store.hasToken() == true)

        try await store.saveToken("token-2")   // 走 SecItemUpdate 分支
        #expect(try await store.readToken() == "token-2")

        try await store.deleteToken()
        #expect(try await store.readToken() == nil)
    }

    @Test("空白视为删除；两端空白会被裁剪")
    func trimming() async throws {
        let store = makeStore()
        try await store.deleteToken()

        try await store.saveToken("  spaced-token \n")
        #expect(try await store.readToken() == "spaced-token")

        try await store.saveToken("   ")
        #expect(try await store.readToken() == nil)

        try await store.deleteToken()
    }

    @Test("重复删除不报错")
    func deleteIdempotent() async throws {
        let store = makeStore()
        try await store.deleteToken()
        try await store.deleteToken()
    }
}
