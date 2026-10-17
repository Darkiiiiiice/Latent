# 显影（Latent）

macOS 上的 TMDB 元数据浏览器：搜索电影、剧集与人物，浏览趋势与筛选发现，收藏并管理自己的观看清单。纯 Swift + SwiftUI，零第三方依赖。

> 「显影」取意暗房工艺：影像在显影液里从无到有、缓缓浮现——这个应用让作品背后的信息同样浮现。英文名「Latent」指潜影（latent image）：信息一直都在，只待显现。

## 状态

**P0–P3 完成，P4 剩余人工走查项。** 设计文档（唯一事实来源）：

- [`docs/设计文档.md`](docs/设计文档.md) —— 完整方案：目标与约束 / TMDB API 设计 / 架构 / 图片管线 / UI 设计系统 / 里程碑（P0–P4）/ 验收与测试

已实现：引导页 + Token 验证、两栏导航（趋势 / 发现 / 收藏 / 观看清单 / 历史）、搜索浮层（防抖 + 分组 + 最近搜索）、电影 / 剧集 / 人物详情（Hero、演职员、剧照、相似推荐、季与分集）、本地库（SwiftData）、设置页（⌘,，常规 / 网络 / 缓存 / 关于，含**网络代理**）、图片管线（内存 + 磁盘 LRU + ImageIO 下采样）、响应缓存（TTL）。

测试：`xcodebuild test -project Latent.xcodeproj -scheme Latent` —— **84 项、15 个套件全绿**（Swift Testing + URLProtocol stub + fixture JSON + 内存 SwiftData 容器；含真实沙箱环境下的 Keychain 用例）。

## 关键决策

- 最低系统 macOS 27；Swift 6（严格并发）；0 第三方依赖
- 数据：SwiftData 纯本地（无 iCloud / CloudKit）；Token 仅本机 Keychain
- 纯元数据只读：不做任何播放（无预告片）；人物页与发现页在 v1；剧集含分集明细
- 界面：暗 / 浅双主题、单一强调色、海报是唯一大色块
- 分发：自用（无付费开发者账号，不做公证与上架）

## 环境

- macOS 27+（部署目标 27.0），Apple Silicon
- Xcode 27.1 / Swift 6.4
- [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）：`Latent.xcodeproj` 是生成物，不入库

## 构建 / 测试

```sh
xcodegen generate                                             # 新增源文件后重跑（工程文件由 project.yml 生成）
xcodebuild -project Latent.xcodeproj -scheme Latent -configuration Debug build
xcodebuild test -project Latent.xcodeproj -scheme Latent
```

## 目录

```
Latent/
├── README.md            # 本文件
├── AGENTS.md            # 开发约定（开发 agent 执行说明）
├── project.yml          # XcodeGen 工程描述（唯一的工程配置来源）
├── docs/
│   └── 设计文档.md       # 完整设计方案（拷贝自 Obsidian 库）
├── scripts/
│   └── gen_colors.py    # 颜色资产生成脚本（记录用；资产以文件为准）
├── Latent/              # 应用源码
│   ├── App/             # 入口、依赖容器、菜单、导航模型
│   ├── Core/            # 网络 / 模型 / 持久化 / 图片管线 / 工具（不 import SwiftUI）
│   ├── Features/        # 引导 / 主界面 / 趋势 / 搜索 / 详情 / 库 / 设置
│   ├── UI/              # 设计 tokens 与通用组件
│   └── Resources/       # Assets（颜色资产 + AppIcon 占位）、entitlements
└── LatentTests/         # Swift Testing 单测与集成测试（fixture 在 Fixtures/）
```

## 下一步（P4）

1. **人工走查**：视觉 / 动效（Reduce Motion）/ 无障碍（VoiceOver、全键盘）/ 手工矩阵。
2. 真实 Token 走通「引导 → 搜索 → 详情 → 收藏 → 重启 → 库」并记录性能基准（滚动帧率、内存）。
3. 应用图标（当前为空占位）；窗口尺寸 / 位置恢复。

## 常见问题

- **国内直连不通**：`设置（⌘,）→ 网络 → 代理` 选「手动」，填 HTTP(S) 或 SOCKS5 的主机与端口（如 `127.0.0.1:7890`），改完点「重新验证」。首次启动若 shell 里有 `https_proxy`，会**自动预填**一次（从 Finder 双击启动读不到环境变量）。
- **弹出钥匙串授权对话框**：ad-hoc 签名（自用构建）的钥匙串条目按代码签名设 ACL，少数情况下读取 Token 时会弹一次「想要使用您存储在钥匙串中的机密信息」——选「始终允许」即可。若对话框被误关，钥匙串操作会一直阻塞，可在「活动监视器」结束 `SecurityAgent` 后重试。

设计文档拷贝自 Obsidian 库 `20_项目/TMDB元数据客户端/`；开发期间如有修订，先更新本仓库 `docs/设计文档.md` 并说明原因，事后回写库中。
