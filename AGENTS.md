# AGENTS.md

面向 coding agent 的项目指南。生成基于对仓库的实际考察（提交历史、工程配置、docs/）。

## 项目概述

**不高山上（Bugaoshan）** — 四川大学校园助手 iOS App。本仓库是 `/Users/clapecho233/Files/Work/Bugaoshan`（Flutter 版，301 个 Dart 文件）的 **iOS 原生重构 + 改进**，Swift + SwiftUI，液态玻璃设计语言。

- Bundle ID：`io.github.ClapEcho233.BugaoshanSwift`（与官方 Flutter 版不互通，无数据迁移）
- 部署目标：iOS 27.0
- 语言约定：**代码标识符英文，注释/文档/提交信息中文**

## 构建与测试

Xcode 27.0，模拟器测试（首选 iPhone 18 Pro）。**构建/测试/运行一律使用 xcode MCP 工具（`mcp__xcode` 命名空间），禁止使用 `xcodebuild` CLI**：

- 编译：`xcode_BuildProject`（失败时用 `xcode_GetBuildLog` 取日志）
- 单元测试（改代码后必须跑，至少跑受影响模块的测试）：`xcode_RunAllTests`
- 仅跑单个测试类（更快）：`xcode_RunSomeTests`（如 `BugaoshanSwiftTests/ParserTests`；可用 `xcode_GetTestList` 查全部用例）
- 查单文件编译诊断：`xcode_XcodeRefreshCodeIssuesInFile`
- 运行目标管理：`xcode_XcodeListRunDestinations` / `xcode_XcodeSwitchRunDestination`；运行与停止 App：`xcode_RunProject` / `xcode_StopProject`
- 模拟器 UI 交互（tap/swipe/输入）：`xcode_DeviceInteraction*` 系列

前提：Xcode 需已打开本项目；未打开时先 `xcode_XcodeOpenWorkspace` 打开 `BugaoshanSwift.xcodeproj`。

Targets：`BugaoshanSwift`（主 App）、`CourseWidgetExtension`（WidgetKit 小组件）、`BugaoshanSwiftTests`、`BugaoshanSwiftUITests`。

SPM 依赖：SwiftSoup（HTML 解析）、BigInt（SM2 大数运算）、GRDB（SQLite）。

## 架构

### 依赖注入与启动

- `App/` — `BugaoshanSwiftApp`（入口 + 启动错误降级页）、`AppEnvironment`（**手动 DI 容器**，无第三方注入库）、`AppConfig`、`RootView`、`MainTabView`
- 构造顺序固定：SharedPreferences → ScuAuth → 子系统认证 → AuthCoordinator → API 服务 → Provider（对应 Dart 版 injector.dart 的依赖图，**不要改变初始化顺序**）
- 状态管理：原生 `ObservableObject` / `@StateObject` / `@EnvironmentObject`，不用第三方状态库

### 三层认证（核心，改动需格外谨慎）

```
L3  ScuAuth（id.scu.edu.cn 统一身份认证，SM2 加密 + 验证码 OCR）
L2  子系统认证：SsoRelayAuth(zhjw/payapp/fitness/service/newservice)、WfwAuth、CcylAuth、ZhhqAuth
L1  各 API 服务（ZhjwApiService、WfwApiService 等）
```

- 权威规范：Flutter 版 `docs/architecture/authentication.md` 的 16 条不变量（single-flight、principal 绑定、登出代次、有限重试等）必须完整保留
- `Core/Auth/AuthCoordinator.swift` 是协调中枢；`AuthLogger` 记录认证事件
- 测试基准：`SubsystemAuthTests`、`ScuAuthTests`、`CookieClientTests` 等，改动认证代码后必跑

### 目录结构

```
BugaoshanSwift/
├── App/                  # 入口、DI 容器、根视图、主题
├── Core/
│   ├── Auth/             # 三层认证（ScuAuth、各子系统、AuthCoordinator）
│   ├── Crypto/           # SM2/SM3（自研移植）、ZhhqCrypto（AES-128-CBC）
│   ├── Networking/       # CookieClient（per-host cookie jar + 手动重定向≤10跳）、HTTPTransport
│   ├── OCR/              # ScuOcrLite（验证码识别，质心模板，复用 model.scuocr）
│   ├── Models/           # Course、AcademicCalendar、ScheduleConfig
│   ├── Storage/          # GRDB DatabaseService（schema 与 Flutter 版一致）
│   └── Utilities/        # JwxtParser、WeekParser、IcsBuilder、CalendarLocationMapper 等
├── Features/             # 按功能组织页面
│   ├── Course/           # 课表（核心功能：多课表、导入、编辑、ICS 导出）
│   ├── Campus/           # 校园生活（余额、报修、Passpoint、办事大厅、二课、校历、下载）
│   ├── Academic/         # 学业（成绩、培养方案、考表、体测）
│   ├── AuthUI/           # 登录/重置密码页
│   ├── Profile/          # 我的、设置
│   └── WebViewKit/       # 通知 WebView 壳（beautify JS 资产直接复用）
├── Resources/            # academic_calendar.json、model.scuocr、JS/、eula.md
└── Assets.xcassets
CourseWidget/             # WidgetKit 小组件：App Group 直读 SQLite，4 尺寸+锁屏
```

### 关键移植约束

- **SQLite schema 与 Flutter 版逐字段一致**（见 `docs/notes/data-model-map.md`）——小组件直读该库，改 schema 必须同步 Widget 与迁移逻辑
- **CookieClient 语义复刻 Dart 版**：内存 per-host cookie jar、手动重定向（≤10 跳）、跨源敏感头剥离；有 `StubURLProtocol` 单测基准
- 网络解析（zhjw 教务 HTML+AJAX JSON 混合）需 fixture 测试；周次/节次解析规则以 `docs/notes/data-model-map.md` 第 3 节为单一事实来源
- 页面模式约定：登录门（未登录占位/自动登录中）→ loading → 错误重试 → 数据；**有缓存时刷新失败保留旧数据**

## 测试约定

- 单测在 `BugaoshanSwiftTests/`，网络层测试用 `StubURLProtocol.swift` 打桩，**不发真实请求**
- 解析器（Parser、WeekParser、JwxtParser、CalendarLocationMapper）、加密（SM2）、认证状态机都有既有测试基准，修改实现前先读对应测试理解契约
- `docs/notes/data-model-map.md` 第 10 节有测试覆盖清单

## 权威参考文档

| 文档 | 用途 |
|---|---|
| `docs/refactoring-plan.md` | 重构总方案、模块分层、范围外功能（先读） |
| `docs/notes/data-model-map.md` | 数据层逐字段对照（模型/SQL/解析规则，单一事实来源） |
| `docs/notes/ui-map.md` | UI 结构对照 |
| `docs/notes/auth-api-map.md` | 认证与 API 端点对照 |

涉及数据格式、解析规则、认证流程的改动，**先查上述文档再动手**；文档与 Flutter 版源码冲突时以文档为准。

## 其他

- `scripts/generate_app_icon.swift` — 程序化生成 App 图标：`swift scripts/generate_app_icon.swift`（改图标后需重跑）
- App 图标/品牌：米色底 + 锦红双山（大山描线、小山实心）
- 检查更新走 GitHub Releases/TestFlight 链接，不做应用内自更新
- 范围外（不做）：桌面平台、Android 专属功能、F-Droid 类打包
