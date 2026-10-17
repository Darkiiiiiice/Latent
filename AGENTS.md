# AGENTS.md — 显影（Latent）开发约定

本目录是「显影（Latent）」——macOS TMDB 元数据浏览器——的开发项目。**动手前先完整阅读 `docs/设计文档.md`，一切以它为准。**

## 先读

- `docs/设计文档.md`：目标与非目标、硬性约束、TMDB API 设计、架构、图片管线、UI 设计系统（第 8 节）、里程碑（P0–P4）、验收与测试。
- `README.md`：项目速览与下一步。

## 硬性约束（不可违反）

1. 纯 Swift + SwiftUI，**0 第三方依赖**——不得通过 SwiftPM / CocoaPods / Carthage 引入任何外部包（开发期工具除外）。
2. 最低系统 **macOS 27**，不写任何向下兼容分支；Swift 6 严格并发（actor / `@MainActor` 分层，DTO 全 `Sendable`）。
3. 数据持久化：**SwiftData 纯本地**，不启用 CloudKit / iCloud；TMDB Read Access Token 存**本机 Keychain**，不写日志、不硬编码、不进数据库。
4. **不做任何媒体播放**（无预告片、无内嵌播放器）；应用是纯元数据只读浏览器。
5. 应用名与图标不使用 TMDB 商标；关于页固定展示 "This product uses the TMDB API but is not endorsed or certified by TMDB."。
6. UI 遵循设计文档第 8 节：暗 / 浅双主题、单一强调色（星紫 `#7C6CFF`）、海报是唯一大色块、动效克制（120–220ms easeOut，无弹簧 / 粒子）、Reduce Motion 全降级。
7. 分发定位自用：不做公证与上架，但 App Sandbox + Hardened Runtime 照常配置。

## 工作方式

- 按 **P0 → P1 → P2 → P3 → P4** 顺序推进；每个阶段按设计文档清单逐项完成，并以该阶段的「通过标准」验收。
- 文档与实现出现冲突时：**先更新 `docs/设计文档.md` 并说明原因，再改代码**，保持文档是唯一事实来源。
- 工程创建（P0 第一项）：Xcode 工程尚未创建。优先由用户在 Xcode 新建 App 模板工程（产品名 `Latent`）；请勿手工拼 `.pbxproj`。
- 单元测试用 Swift Testing + 内存 `ModelContainer`（`isStoredInMemoryOnly: true`）；网络测试用 URLProtocol stub + fixture JSON。
- 构建 / 测试命令（工程创建后）：
  - `xcodebuild -project Latent.xcodeproj -scheme Latent -configuration Debug build`
  - `xcodebuild test -project Latent.xcodeproj -scheme Latent`
- 面向用户的文案、注释与提交信息使用中文。
