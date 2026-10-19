# 显影（Latent）

macOS 上的 TMDB 元数据浏览器：搜索电影、剧集与人物，浏览趋势与筛选发现，收藏并管理自己的观看清单。纯 Swift + SwiftUI，零第三方依赖。

> 「显影」取意暗房工艺：影像在显影液里从无到有、缓缓浮现——这个应用让作品背后的信息同样浮现。英文名「Latent」指潜影（latent image）：信息一直都在，只待显现。

![显影主界面](docs/images/app-main.png)

## 状态

**v1 完成（P0–P4）。** 视觉 / 动效 / 无障碍人工走查通过；按「自用」定位不做公证与上架。设计文档是唯一事实来源：

- [`docs/设计文档.md`](docs/设计文档.md) —— 目标与约束 / TMDB API 设计 / 架构 / 图片管线 / UI 设计系统 / 里程碑（P0–P4）/ 验收与测试

已实现：

- **浏览**：今日 / 本周 × 电影 / 剧集的趋势页，网格 / 列表双视图，滚动到底自动加载下一页
- **搜索**：工具栏全局搜索（`⌘F`）、300ms 防抖、电影 / 剧集 / 人物分组、最近搜索、分页加载
- **发现**：类型多选、年份区间、最低评分、排序，筛选变化防抖刷新，无限滚动
- **详情**：Hero、简介折叠、演职员、剧照、相似 / 推荐；剧集含季选择器与分集明细；人物页含作品年表
- **本地库**：收藏 / 观看清单 / 历史（SwiftData 纯本地），右键菜单、Toast 反馈
- **设置**：Token 验证、语言、外观、网络代理、缓存统计与清理（`⌘,`）
- **基础设施**：Keychain 存 Token、URLSession 代理、响应缓存 TTL、图片管线（内存 + 磁盘 LRU + ImageIO 下采样）、暗 / 浅双主题与 Reduce Motion 降级

测试：`xcodebuild test -project Latent.xcodeproj -scheme Latent` —— **85 项、15 个套件全绿**（Swift Testing + URLProtocol stub + fixture JSON + 内存 SwiftData 容器；含真实沙箱环境下的 Keychain 用例）。

性能基线（M1 Pro，Debug 自用构建）：空闲 CPU **0.0%**（5 秒采样）、首屏加载后常驻内存约 **125MB**、网格滚动流畅。窗口尺寸与位置由 SwiftUI `WindowGroup` 自动恢复。

## 关键决策

- 最低系统 macOS 27；Swift 6（严格并发）；0 第三方依赖
- 数据：SwiftData 纯本地（无 iCloud / CloudKit）；Token 仅本机 Keychain，不入库、不写日志
- 纯元数据只读：不做任何媒体播放（无预告片）；人物页与发现页在 v1；剧集含分集明细
- 界面：暗 / 浅双主题、单一强调色、海报是唯一大色块；不使用 `repeatForever` 无限动画
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

首次启动会要求粘贴自己的 TMDB **Read Access Token**（在 [TMDB 设置 → API](https://www.themoviedb.org/settings/api) 申请），Token 只保存在本机钥匙串。

## 目录

```
Latent/
├── README.md            # 本文件
├── AGENTS.md            # 开发约定（开发 agent 执行说明）
├── project.yml          # XcodeGen 工程描述（唯一的工程配置来源）
├── docs/
│   ├── 设计文档.md       # 完整设计方案
│   └── images/          # README 截图
├── Design/
│   └── AppIcon-source.png  # 应用图标源稿（1254×1254）
├── scripts/
│   ├── gen_colors.py    # 颜色资产生成脚本（记录用；资产以文件为准）
│   └── make_appicon.py  # 应用图标生成脚本（源稿 → AppIcon.appiconset 全套）
├── Latent/              # 应用源码
│   ├── App/             # 入口、依赖容器、菜单、导航模型
│   ├── Core/            # 网络 / 模型 / 持久化 / 图片管线 / 工具（不 import SwiftUI）
│   ├── Features/        # 引导 / 主界面 / 趋势 / 搜索 / 详情 / 库 / 设置
│   ├── UI/              # 设计 tokens 与通用组件
│   └── Resources/       # Assets（颜色资产 + AppIcon）、entitlements
└── LatentTests/         # Swift Testing 单测与集成测试（fixture 在 Fixtures/）
```

## 常见问题

- **国内直连不通**：`设置（⌘,）→ 网络 → 代理` 选「手动」，填 HTTP(S) 或 SOCKS5 的主机与端口（如 `127.0.0.1:7890`），改完点「重新验证」。首次启动若 shell 里有 `https_proxy`，会**自动预填**一次（从 Finder 双击启动读不到环境变量）。
- **弹出钥匙串授权对话框**：ad-hoc 签名（自用构建）的钥匙串条目按代码签名设 ACL，少数情况下读取 Token 时会弹一次「想要使用您存储在钥匙串中的机密信息」——选「始终允许」即可。若对话框被误关，钥匙串操作会一直阻塞，可在「活动监视器」结束 `SecurityAgent` 后重试。

## 许可与署名

本仓库为个人项目，暂未附开源许可证；代码可供参考，转载或复用请先联系作者。

This product uses the TMDB API but is not endorsed or certified by TMDB.
