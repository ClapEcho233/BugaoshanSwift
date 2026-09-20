# 不高山上 · BugaoshanSwift

四川大学校园助手 **「不高山上」** 的 iOS 原生重构版。基于 Swift + SwiftUI，采用 iOS 26 液态玻璃（Liquid Glass）设计语言。

> 本仓库是 Flutter 版 [Bugaoshan](https://github.com/ClapEcho233/Bugaoshan) 的原生重构 + 改进。与官方 Flutter 版不互通数据，无需迁移。

## 功能

- **课表（核心）** — 多课表管理、教务导入、手动编辑、ICS 日历导出、桌面小组件
- **学业** — 成绩查询、培养方案、计划完成度、考表、体测成绩
- **校园生活** — 校园卡余额与趋势、电费/空调余额、宿舍报修、Passpoint 无感认证、办事大厅、第二课堂、校历
- **通知** — 教务处 / 学工部 / 团委通知（WebView + JS 美化）
- **更多** — 统一身份认证登录、深浅色、中英双语、锁屏与桌面小组件（4 尺寸）

## 技术栈

| 项 | 说明 |
|---|---|
| 语言 / UI | Swift 6 · SwiftUI，最低部署 iOS 26.0 |
| 依赖 | SwiftSoup（HTML 解析）· BigInt（SM2 大数运算）· GRDB（SQLite） |
| 状态管理 | 原生 `ObservableObject` / `@Observable`，无第三方状态库 |
| 依赖注入 | 手动 DI 容器（`AppEnvironment`） |
| 小组件 | WidgetKit，App Group 直读 SQLite，含锁屏小组件 |

## 架构

三层认证体系为核心（详见 Flutter 版 `docs/architecture/authentication.md` 的 16 条不变量）：

```
L3  ScuAuth          统一身份认证（id.scu.edu.cn，SM2 加密 + 验证码 OCR）
L2  子系统认证        SsoRelayAuth / WfwAuth / CcylAuth / ZhhqAuth
L1  API 服务         ZhjwApiService / WfwApiService / …
```

自研移植件：SM2/SM3 国密算法、验证码 OCR（质心模板，复用 `model.scuocr`）、CookieClient（per-host cookie jar + 手动重定向）等。

目录结构：

```
BugaoshanSwift/
├── App/            # 入口、DI 容器、根视图、主题
├── Core/           # 认证 / 加密 / 网络 / OCR / 模型 / 存储 / 工具
├── Features/       # 按功能组织页面（课表、校园、学业、通知、设置…）
└── Resources/      # 校历数据、OCR 模型、JS 资产
CourseWidget/       # WidgetKit 小组件
```

## 构建

- Xcode 27+，iOS 26.0+ 模拟器或真机
- 打开 `BugaoshanSwift.xcodeproj`，直接 Cmd+R 运行主 App
- SPM 依赖由 Xcode 自动解析

## 测试

```
BugaoshanSwiftTests/       # 单元测试（网络层用 StubURLProtocol 打桩，不发真实请求）
BugaoshanSwiftUITests/     # UI 测试
```

解析器、加密算法、认证状态机均有测试基准，修改实现前先读对应测试理解契约。

## 文档

| 文档 | 用途 |
|---|---|
| [`docs/refactoring-plan.md`](docs/refactoring-plan.md) | 重构总方案、模块分层 |
| [`docs/notes/data-model-map.md`](docs/notes/data-model-map.md) | 数据层逐字段对照（单一事实来源） |
| [`docs/notes/ui-map.md`](docs/notes/ui-map.md) | UI 结构对照 |
| [`docs/notes/auth-api-map.md`](docs/notes/auth-api-map.md) | 认证与 API 端点对照 |

## 相关仓库

- [Bugaoshan](https://github.com/ClapEcho233/Bugaoshan) — Flutter 多平台版（功能基准）

## 声明

本项目为非官方的校园助手应用，与四川大学无关，仅供学习交流使用。数据均来自学校官方系统，请自行遵守相关使用规范。
