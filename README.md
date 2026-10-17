# 显影（Latent）

macOS 上的 TMDB 元数据浏览器：搜索电影、剧集与人物，浏览趋势与筛选发现，收藏并管理自己的观看清单。纯 Swift + SwiftUI，零第三方依赖。

> 「显影」取意暗房工艺：影像在显影液里从无到有、缓缓浮现——这个应用让作品背后的信息同样浮现。英文名「Latent」指潜影（latent image）：信息一直都在，只待显现。

## 状态

规划完成，等待开发。设计文档（唯一事实来源）：

- [`docs/设计文档.md`](docs/设计文档.md) —— 完整方案：目标与约束 / TMDB API 设计 / 架构 / 图片管线 / UI 设计系统 / 里程碑（P0–P4）/ 验收与测试

## 关键决策

- 最低系统 macOS 27；Swift 6（严格并发）；0 第三方依赖
- 数据：SwiftData 纯本地（无 iCloud / CloudKit）；Token 仅本机 Keychain
- 纯元数据只读：不做任何播放（无预告片）；人物页与发现页在 v1；剧集含分集明细
- 界面：暗 / 浅双主题、单一强调色、海报是唯一大色块
- 分发：自用（无付费开发者账号，不做公证与上架）

## 环境

- macOS 27+（部署目标 27.0），Apple Silicon
- Xcode 27.1 / Swift 6.4

## 下一步（P0 技术验证）

1. 创建 Xcode 工程（App 模板，产品名 `Latent`）：App Sandbox + `network.client`、Hardened Runtime、macOS 27 目标、Swift 6 严格并发
2. Keychain 读写 + 最小设置页；Bearer 调 `GET /3/configuration` 验证 Token
3. SwiftData 本地容器骨架（收藏 / 清单 / 历史三张表 + 版本化 Schema）
4. `TMDBClient` 骨架 + Endpoint 枚举 + 错误分类（fixture 离线解码）
5. 图片管线原型：actor + NSCache + 磁盘 + ImageIO 下采样 + 取消

通过标准见设计文档「P0 技术验证」。

## 目录

```
Latent/
├── README.md          # 本文件
├── AGENTS.md          # 开发约定（开发 agent 执行说明）
└── docs/
    └── 设计文档.md     # 完整设计方案（拷贝自 Obsidian 库）
```

设计文档拷贝自 Obsidian 库 `20_项目/TMDB元数据客户端/`；开发期间如有修订，先更新本仓库 `docs/设计文档.md` 并说明原因，事后回写库中。
