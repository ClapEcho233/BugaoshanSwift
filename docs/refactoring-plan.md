# 不高山下 iOS 原生重构方案

> 目标：将 Flutter 多平台版 Bugaoshan（不高山下）重构为 iOS 原生应用，采用 Swift + SwiftUI + 液态玻璃（Liquid Glass）设计语言。
>
> 原项目：`/Users/clapecho233/Files/Work/Bugaoshan`（Flutter 3.44，301 个 Dart 文件，约 72,500 行，v2.5.2）
>
> 本文档日期：2026-09-19

---

## 1. 现状分析

### 1.1 现有应用概况

不高山下是四川大学校园助手 App，20+ 功能模块，按重要度分层：

| 层 | 模块 | 数据来源 |
|---|---|---|
| 本地核心 | 课表（多课表、导入、编辑、ICS 导出）、小组件、校历 | 本地 SQLite + 教务导入 |
| 学业 | 成绩、培养方案、计划完成度、考表、体测、空闲教室、班级/课程课表查询 | 教务 zhjw + 体测 pead |
| 校园生活 | 宿舍报修（智慧后勤）、电费/空调余额+趋势、校园网设备、Passpoint 无感认证、办事大厅（请假）、第二课堂 | zhhq / payapp / wfw / newservice / dekt |
| 通知 | 教务处/学工部/团委通知（WebView+JS 美化）、志愿四川 | jwc / xgb / tuanwei（WebView） |
| 系统 | 登录（统一身份认证）、设置（约 40 项）、关于/更新、开发者页 | id.scu.edu.cn + GitHub Releases |

### 1.2 架构现状（值得原样继承的部分）

- **状态管理**：原生 `ChangeNotifier`/`ValueNotifier` + `ListenableBuilder`，无第三方状态库 → 与 Swift `@Observable` 模式天然同构
- **DI**：GetIt 手动注册，显式三层依赖图（认证 L3 → 子系统 L2 → API L1 → Provider）→ 映射为手动构造的 `AppEnvironment`
- **认证**：三层架构，权威文档 `docs/architecture/authentication.md`，16 条不变量（single-flight、principal 绑定、登出代次、有限重试等）
- **页面模式**：登录门（未登录占位/自动登录中）→ loading → 错误重试 → 数据；"有缓存时刷新失败保留旧数据"约定
- **导航**：用户可自定义 dock（22 个可配置项，默认 课表/校园/我的 三 tab）

### 1.3 iOS 平台已有原生资产（Flutter 版内）

这些代码本来就是 Swift 写的，可直接移植参考：

| 资产 | 位置 | 说明 |
|---|---|---|
| WidgetKit 小组件 | `ios/CourseWidget/WidgetExtension.swift`（约 1200 行） | App Group SQLite 直读、4 种尺寸+锁屏、timeline 精确刷新策略、空态校历兜底 |
| EventKit 日历导入 | `ios/Runner/AppDelegate.swift` | ICS 导入系统日历、UID 去重映射、structuredLocation |
| App Group 偏好同步 | `ios/Runner/AppDelegate.swift` | widget 三项偏好 + `WidgetCenter.reloadAllTimelines()` |

### 1.4 关键技术依赖形态（决定移植策略）

| 依赖 | 形态 | Swift 移植难度 |
|---|---|---|
| SM2 加密（dart_sm） | 纯 Dart 实现，C1C2C3 模式加密密码 | **中**：自研 Swift 移植（BigInt + 椭圆曲线运算，仅加密无需签名） |
| 验证码 OCR（scu_ocr_lite） | 纯 Dart，`model.scuocr` 仅 1,776 字节（36 类字符质心模板），算法：去干扰线→颜色聚类→分割→6×8 缩放→加权最近邻 | **低**：模型文件直接复用，算法几百行 Swift |
| zhhq AES | AES-128-CBC + PKCS7，前端公开常量 | **低**：CommonCrypto 内置 |
| zhjw 教务 | HTML 爬取 + AJAX callback JSON 混合 | **中**：SwiftSoup + Regex，需 fixture 测试 |
| 通知 WebView | 4 个页面 + beautify JS 资产 | **低**：JS 资产直接复用，WKWebView 重写壳 |
| CookieClient | 内存 per-host cookie jar + 手动重定向（≤10 跳）+ 跨源敏感头剥离 | **中**：URLSession delegate 复刻语义 |

---

## 2. 目标与范围

### 2.1 目标

1. **功能对等**：iOS 版覆盖 Flutter 版全部 iOS 适用功能，认证架构不变量完整保留
2. **原生体验**：SwiftUI + 液态玻璃设计，充分利用 iOS 26+ 系统能力（WidgetKit、EventKit、App Intents 可后置）
3. **数据兼容**：SQLite schema 与 Flutter 版一致（小组件代码、未来数据迁移都受益）
4. **可测试**：认证状态机、解析器、加密全部有单元测试基准

### 2.2 范围外（明确不做 / 降级）

| 功能 | 处理 |
|---|---|
| 桌面平台（窗口管理、鼠标返回键、自更新脚本） | 不做 |
| Android 动态图标、电池优化引导 | 不做（iOS 可后置做 alternate icons，非首期） |
| 应用内下载自更新 | 降级：检查更新 → 展示 GitHub Release/TestFlight 链接 |
| Google Fonts 运行时拉取 | 改为打包 Noto Sans SC 子集（离线可用、审核安全） |
| F-Droid/Flatpak/AUR 打包 | 不做 |

### 2.3 待定决策（建议）

| 决策 | 建议 |
|---|---|
| 部署目标 | 当前工程为 iOS 27.0。液态玻璃 API 自 iOS 26 起可用；若想覆盖 2025 秋设备建议降至 **26.0**，若接受仅最新系统则维持 27.0 |
| 数据迁移 | 新 bundle id（io.github.ClapEcho233.BugaoshanSwift）与官方 Flutter 版 App Group 不互通；利用现有"课表导出分享"功能做一次性迁移即可 |
| 开源合规 | 原项目 AGPL-3.0，衍生 iOS 版须继续 AGPL-3.0 开源；scu_ocr_lite（Apache-2.0/MIT 待核）与 dart_sm 的许可证需在 README 致谢清单中注明 |

---

## 3. 技术选型与架构映射

| Flutter 侧 | Swift 侧 | 说明 |
|---|---|---|
| Material 3 / MD3 Expressive | SwiftUI + 液态玻璃（iOS 26+ API） | 见 §4 设计系统 |
| `ChangeNotifier`/`ValueNotifier` | `@Observable` / `@Observable` class + `@Environment` | 观察粒度一致，无需第三方 |
| GetIt 手动注册 | `AppEnvironment` 手动构造（`@MainActor` 容器） | 保持显式依赖图与初始化顺序 |
| `Future`/`Completer`/isolate | `async/await`、`Task`、`actor` | single-flight 用 actor 内缓存 Task 实现 |
| `package:http` + `CookieClient` | `URLSession` + `CookieJar`（actor）+ 手动重定向 delegate | 复刻：per-host cookie、≤10 跳、跨源剥敏感头、15s 超时、传输错误重试一次 |
| HTML 正则解析 | SwiftSoup + Swift Regex | zhjw 各页面 fixture 快照测试 |
| `json_annotation` | `Codable` | 模型字段名对齐原实现 |
| sqflite | **GRDB.swift** | 同 schema：`metadata` / `schedules` / `courses` / `balance_records`（v2 含 campus 列）；DB 放 App Group 容器 |
| SharedPreferences | `UserDefaults`（标准 + App Group 两套） | 键名与原版一致 |
| FlutterSecureStorage | Keychain（`AfterFirstUnlockThisDeviceOnly`） | token/凭据/会话，键名与原版一致 |
| dart_sm（SM2） | 纯 Swift 移植 `SM2.swift` | C1C2C3、公钥补 `04` 前缀、base64 输出；用 Dart 版生成测试向量对拍 |
| encrypt（AES-CBC） | CommonCrypto `CCCrypt` | zhhq Token 头与响应解密，常量照搬 |
| crypto（SHA-256） | CryptoKit | token 指纹绑定 |
| scu_ocr_lite | 纯 Swift 移植 `ScuOcrLite.swift` | 复用 `model.scuocr` 二进制；Core Graphics 解码图片 |
| flutter_inappwebview | WKWebView + `WKUserScript` + `WKScriptMessageHandler` | **beautify JS 资产原样复用**；handler 命名保持 `AttachmentsChannel` 等契约 |
| fl_chart | Swift Charts | 电费趋势、成绩统计 |
| 自研 ICS + AppDelegate EventKit 桥 | EventKit 直连（EKEventEditResponse 或静默写入） | 参考现有 AppDelegate.swift 的 UID 去重实现移植 |
| WidgetKit（已有 Swift） | 直接移植 | App Group id 改为新值，SQL/时间线逻辑保留 |
| ARB ×967 ×2 语言 | String Catalog（`.xcstrings`） | 写脚本 ARB→xcstrings 一次性迁移 |
| `SystemTheme.accentColor` | iOS 无系统级强调色，`system` 模式退化为默认品牌色 | 保留 custom / backgroundImage 取色两模式 |

### 3.1 认证层移植设计（最关键）

完整保留三层架构与 `docs/architecture/authentication.md` 的全部不变量：

```swift
// L3 根认证 —— actor 隔离可变状态
actor ScuAuth {
    private(set) var state: AuthState = .unknown
    private var token: String?          // Keychain 持久化
    private var principalBinding: ...   // SHA-256 指纹绑定
    private var authEpoch: UInt64       // 登出代次，防旧任务写回
    private var bindSessionTask: Task<CookieClient, Error>?   // single-flight
    private var refreshTask: Task<Bool, Error>?               // single-flight

    func getClient() async throws -> CookieClient   // TTL 1h → 刷新 → 自动登录
    func login(username:password:captchaCode:captchaText) async throws
    func autoLogin() async throws                    // 凭据 + OCR，UI 层最多重试 5 次
    func logout() async
}

// L2 子系统认证 —— 协议照搬
protocol SubsystemAuth: Sendable {
    var moduleId: String { get }
    var dependencies: [any SubsystemAuth] { get }
    func ensureAuthenticated() async throws
    func invalidate() async
}
// 8 个实现：ZhjwAuth / WfwAuth / PayAppAuth(依赖Wfw) / FitnessAuth
//          / CcylAuth(OAuth+principal绑定) / ZhhqAuth(tokenKey持久化) / ServiceAuth / NewServiceAuth
// SsoRelayAuth 作为 fitness/payapp/service/newservice 的公共基类（改为默认实现）

// L2 调度
actor AuthCoordinator {
    func warmUpAll() async    // 拓扑并发预热，失败隔离，single-flight
    func invalidateAll() async
}

// L1 API Service —— 无状态 struct，统一模板
func retryOnUnauthenticated<T>(_ op: () async throws -> T) async throws -> T
// UnauthenticatedException → invalidate → 重新 getClient → 重放一次
```

要点：
- **CookieClient 复刻**：`URLSession` 配置 `.delegate` 拦截 `willPerformHTTPRedirection`，每次手动发起下一跳；cookie 按 host 存于 actor 字典；`Authorization` 仅同源或白名单转发；对象身份（class 实例）作为根 client 变化检测信号，子系统据此清缓存
- **异常体系**：`enum SCUError: Error`（unauthenticated / service / rateLimited / login / forgotPassword），CCYL 独立 `CcylAuthExpiredError` 只在明确过期码时重放
- **全局过期提示**：`ScuAuth.onSessionExpired` 回调 → 根视图 `.onChange` 弹提示 + 5s 冷却

### 3.2 目标工程结构

```
BugaoshanSwift/
├── App/
│   ├── BugaoshanApp.swift          # 入口：AppEnvironment 构造、启动错误降级页
│   ├── AppEnvironment.swift        # 手动 DI 容器（对应 injector.dart）
│   └── RootView.swift              # EULA 门 → 首启向导 → MainTabView
├── Core/
│   ├── Networking/                 # HTTPClient、CookieJar、RedirectFollower、retryOnUnauthenticated
│   ├── Auth/                       # ScuAuth、SubsystemAuth、AuthCoordinator、8 个子系统、SCUError
│   ├── Storage/                    # DatabaseService(GRDB)、KeychainStore、DefaultsStore、StorageKeys
│   ├── Crypto/                     # SM2.swift、ZhhqCrypto.swift
│   ├── OCR/                        # ScuOcrLite.swift + model.scuocr 资源
│   ├── Models/                     # Course、ScheduleConfig、AcademicCalendar、SchemeScore、Repair、BalanceRecord...
│   └── Utilities/                  # WeekParser、ClassWeekParser、BeijingTime、IcsBuilder、UpdateChecker
├── Features/
│   ├── Course/                     # 主网格、编辑、导入(jwxt_parser)、管理、课表设置、放假页
│   ├── Academic/                   # 成绩、培养方案、计划完成度、考表、体测、空闲教室、班级/课程课表、校历
│   ├── Campus/                     # 报修、电费+趋势、校园网设备、Passpoint、办事大厅、通知入口、志愿四川
│   ├── AuthUI/                    # 登录页、忘记密码三步流程
│   ├── Profile/                    # 我的、设置、关于、开发者
│   └── WebViewKit/                 # 通用 WKWebView 通知页（JS 资产注入、附件下载、验证码对话框）
├── Resources/
│   ├── Assets.xcassets
│   ├── Fonts/                      # Noto Sans SC 子集
│   ├── JS/                         # 4 份 beautify JS + dom_ready.js（原样复制）
│   ├── academic_calendar.json
│   └── Localizable.xcstrings       # ARB 迁移生成
├── CourseWidget/                   # WidgetKit 扩展（移植）
└── Tests/                          # 单元测试 + HTML fixtures
```

---

## 4. 液态玻璃设计系统

### 4.1 总原则

- **结构优先**：玻璃效果用于"悬浮于内容之上的功能性层"（tab bar、工具栏、课程卡片、悬浮按钮），内容本身保持清晰
- **容器化**：同一区域的多个玻璃元素用 `GlassEffectContainer` 包裹，获得正确的融合/分离渲染
- **自动降级**：`glassEffect` 在"减弱透明度"辅助功能下自动退化为普通材质，无需手动处理
- **动态字体与深浅色**：全部走系统 `@Environment(\.colorScheme)` 与 Dynamic Type；深色下玻璃自动加深

### 4.2 核心界面映射

| 原界面 | 液态玻璃重设计 |
|---|---|
| 底部 dock（NavigationBar） | 原生 `TabView` 自动获得液态玻璃 tab bar；加 `tabBarMinimizeBehavior(.onScrollDown)` 滚动收起；自定义 dock 项仍由 `visibleDockIds` 驱动 tab 内容 |
| 课表周网格 | **招牌场景**：背景图全屏铺底（`backgroundExtensionEffect()` 延伸出安全区）→ 整周课程卡片包在 `GlassEffectContainer` 中，每张卡片 `.glassEffect(.regular.tint(courseColor).interactive(), in: .rect(cornerRadius: 16))`；点击弹详情 sheet；节次列/日期表头用半透明玻璃。翻周用 `TabView(.page)` 跟手滑动 |
| 顶栏（周数/翻周/切课表菜单） | toolbar 内 `glassEffect` 胶囊控件 + `ToolbarSpacer`，或自定义悬浮胶囊；"回本周"按钮 `.buttonStyle(.glass)` |
| 校园功能聚合页 | 搜索栏 `.searchable`；功能卡片 `grid` 布局，小图标玻璃卡片（`GlassEffectContainer` 分组）；节标题普通文本 |
| 成绩统计 | 统计块用玻璃小卡片行；图表区域普通卡片 + 玻璃图例；Tab 切换用 `segmented`（自动液态玻璃化） |
| 登录页 | 头图 hero + 表单玻璃卡片悬浮；登录按钮 `.buttonStyle(.glassProminent)`；验证码行内点击刷新 |
| 报修/表单页 | `Form`（自动液态玻璃分组样式）；提交按钮 glassProminent；图片选择网格玻璃边框 |
| 详情/时间线（工单） | 玻璃节点 + `backgroundExtensionEffect` 长内容 |
| 电费趋势图表 | Swift Charts 普通卡片（图表内容不用玻璃，保证可读性）+ 玻璃统计块 |
| 通知 WebView | WKWebView 内容 + 液态玻璃工具栏/进度条 + 悬浮附件按钮（`glassEffect` 圆形） |
| 全局弹层 | sheet 默认已液态玻璃化；确认弹窗用 `.alert` 系统样式 |

### 4.3 颜色与形状令牌

- 颜色：`ColorScheme` 基础上叠加三种模式——`system`（iOS 退化为默认蓝）、`custom`（用户选色，色板用系统色板 UI）、`backgroundImage`（CGImage 采样主色，在后台 actor 计算）；课程颜色保持 ARGB 持久化
- 形状：原 MD3 角标（4/8/12/16/20/28/999）映射为 SwiftUI 常量；**同心圆角**用 `.containerShape(.rect(cornerRadius:))` 与外层容器保持连续
- 玻璃染色：课表卡片用课程色 `.tint()`；功能性按钮用主题色；避免大面积彩色玻璃

### 4.4 性能注意

- `GlassEffectContainer` 内元素数量保持克制；课表一屏课程卡（通常 ≤ 30 张）一组即可
- 滚动密集列表（成绩、工单、通知列表）行内**不用**逐行玻璃，用普通背景 + 选中态玻璃
- 小组件：iOS 26+ 桌面小组件自动获得液态玻璃背景，保留 `containerBackground` 与 `.widgetAccentable()`

---

## 5. 分阶段实施路线图

### Phase 0 — 技术验证（POC，先证明再铺开）

| 任务 | 验收标准 |
|---|---|
| `SM2.swift` 移植 | 用 Dart 版对固定输入生成密文测试向量（含同一临时公钥），Swift 输出可解回原文；`04||C1C2C3` base64 格式逐字节一致 |
| `ScuOcrLite.swift` 移植 | 同一批验证码图片，Swift 与 Dart 识别结果一致率 ≥ 99% |
| CookieClient 复刻 | 真机完成：登录 → `session/save` → zhjw JWT SSO 重定向链 → 拉到课表 JSON |
| Widget 编译移植 | 新 App Group 下 WidgetKit 小组件渲染课表 |
| ATS 豁免 | `zhjw.scu.edu.cn` 为 **HTTP 站点**，Info.plist 配置 `NSAppTransportSecurity` 例外并验证可连 |

### Phase 1 — 基础框架

- 网络层（CookieJar/重定向/超时/重试模板）+ 异常体系
- 存储层：GRDB schema v2 + KeychainStore + DefaultsStore（键名对齐）
- `AppEnvironment` 手动 DI + 启动序列（含启动失败降级页）
- 认证栈全套：ScuAuth + AuthCoordinator + 8 子系统（每个都过单元测试）
- 登录页（验证码 OCR 预填、记住密码/自动登录、错误本地化）+ 忘记密码三步流程
- App Shell：EULA 门 → 首启向导 → MainTabView（自定义 dock）+ 全局会话过期提示
- 主题系统（三模式取色）+ String Catalog 骨架（先迁移高频 ~100 条）

**验收**：真机可登录、自动登录、子系统预热成功、登出干净；认证层单元测试全绿。

### Phase 2 — 课表核心（本地功能，离线可用）

- 周视图网格（液态玻璃卡片、背景图、放假页、空状态）
- 课程编辑、多课表管理、课表设置（时间槽、两套校区预置）
- 教务导入（jwxt_parser + 课表名冲突三选）+ 分享文件导入（原 App 导出物，兼做数据迁移）
- ICS 导出 + EventKit 日历导入（UID 去重）+ 剪贴板复制
- 小组件（4 尺寸 + 锁屏 + 偏好设置页）
- 校历页（交互式校历 + 官方图）

**验收**：从 Flutter 版导出课表 → 新 App 导入成功；小组件显示正确；与 Flutter 版行为对齐。

### Phase 3 — 学业模块

成绩（3 Tab + 搜索 + 自定义统计）、培养方案、计划完成度（600ms 限流间隔）、考表（+ICS 导出）、体测、空闲教室（三级下钻 + 当前节高亮）、班级/课程课表查询（复用课表网格聚合模式）、按 principal 的缓存策略。

### Phase 4 — 校园生活

报修（地址/项目级联、3 图上传、工单时间线、撤回/评价）、电费余额 + 趋势图（Swift Charts、按房间共享历史）、校园网设备（下线）、Passpoint、办事大厅动态表单（服务端 schema 驱动 + 350 fallback）、通知三源 WebView（JS 资产复用、附件下载管理、验证码对话框）、志愿四川。

### Phase 5 — 系统与打磨

设置全量（语言/主题色/课程样式/字体/dock 自定义/危险区清数据）、关于/发布说明/团队、更新检查（GitHub API + 语义化版本比较，跳转链接）、开发者页（认证日志查看器）、l10n 全量 967 条迁移、无障碍（VoiceOver 标签、动态字体全页面核查）、深浅色走查。

### 里程碑与工作量估算（单人，AI 辅助开发）

| 阶段 | 估时 |
|---|---|
| Phase 0 | 3–5 天 |
| Phase 1 | 1.5–2.5 周 |
| Phase 2 | 2–3 周 |
| Phase 3 | 2–3 周 |
| Phase 4 | 2.5–3.5 周 |
| Phase 5 | 1–2 周 |
| **合计** | **约 9–14 周** |

---

## 6. 风险清单

| 风险 | 等级 | 应对 |
|---|---|---|
| SM2 移植错误（C1C2C3 拼接、随机数 k） | 高 | Phase 0 对拍测试向量；固定 RNG 注入做确定性测试；dart_sm 源码为权威参考 |
| zhjw HTTP-only 被 ATS 拦截 | 中 | 已知问题，Info.plist 域级豁免；仅豁免 `zhjw.scu.edu.cn` |
| 教务 HTML/接口变化导致解析失效 | 中 | 全部解析集中 `ZhjwParser` + `Tests/Fixtures/*.html` 快照测试；解析失败降级为可读错误 |
| 液态玻璃在低端机课表网格掉帧 | 中 | Instruments GPU 走查；必要时课程卡片退化为 `.ultraThinMaterial`，仅顶栏/悬浮件保玻璃 |
| 动态表单（办事大厅）服务端 schema 兼容 | 中 | 先对照 350 fallback schema 实现，其余插件类型渐进支持 |
| OCR/SM2 许可证 | 低 | scu_ocr_lite（README 写 MIT、LICENSE 为 Apache-2.0，使用前核实）；dart_sm 核实后在致谢清单注明 |
| AGPL-3.0 合规 | 低 | 衍生项目同协议开源，README 注明上游 |
| iOS 27-only 覆盖面 | 低 | 见 §2.3，建议评估降至 26.0 |

---

## 7. 测试策略

1. **单元测试**（优先级最高，直接对齐原 `test/` 81 个文件覆盖点）：
   - 认证：401/403 与 `invalid_token`、根刷新 single-flight、登出代次、CCYL principal 不跨账号、WFW 根 client 变化重预热、重试上限
   - 加密：SM2/AES 向量、token 指纹
   - 解析：周次文本/位串解析、jwxt_parser（fixture JSON）、zhjw HTML 各页面（fixture HTML）、`looksLikeLoginPage` 强特征（含 issue #282 回归：不匹配 `loginStatus`）
   - 业务：课程冲突检测、当前周计算（周日起点语义）、ICS 生成、语义化版本比较、余额北京时间处理
2. **HTML fixtures**：从真实教务页面保存样本入库，解析器变更即回归
3. **UI 测试**：登录流程、课表增删改、导入向导关键路径
4. **对拍测试**（Phase 0 专项）：OCR 与 SM2 与 Dart 版输出一致性

---

## 8. 迁移细节备忘

- **键名兼容**：UserDefaults/Keychain/DB 表结构键名与 Flutter 版保持一致（`scu_access_token`、`scu_principal_binding_v1`、`zhhq_token_key`、`ccyl_session_v2` 等），便于代码对照与未来官方合并
- **JS 资产**：`assets/js/*.js` 原样复制进 bundle；`dom_ready.js` 的 `flutter_inappwebview.callHandler('DOMReady')` 调用需改为 `window.webkit.messageHandlers.DOMReady.postMessage(null)`（唯一需要改动的桥接点，其余 beautify 逻辑不动）
- **小组件**：`WidgetExtension.swift` 移植时替换 App Group id 为 `group.io.github.ClapEcho233.BugaoshanSwift`，SQLite 查询与时间线策略保留；外观枚举 index 对齐保持
- **课表数据迁移**：Flutter 版"导出课表→分享文件"，新 App 的"分享导入"解析同一格式，作为用户迁移路径
- **User-Agent**：保持原 `kDefaultUserAgent`（桌面 Chrome UA）策略，部分子站对 UA 敏感
