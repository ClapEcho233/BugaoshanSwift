# Bugaoshan (不高山上) — UI / State Porting Reference

Source of truth for the Swift/SwiftUI rewrite. Generated from the Flutter codebase at
`/Users/clapecho233/Files/Work/Bugaoshan` (lib/**, ios/CourseWidget/WidgetExtension.swift).
All constant values are verbatim from code. Flutter file paths are relative to `lib/`.

App name: 不高山上 (Bugaoshan) — SCU (Sichuan University) campus assistant.
Stack in Flutter: Material 3 + GetIt DI + `ValueNotifier`/`ChangeNotifier` (no Riverpod/Bloc) + SharedPreferences + sqflite + flutter_inappwebview.

---

## 1. App Shell Flow

### 1.1 Startup sequence (`main.dart`, `app.dart`)

1. `main()` wraps everything in try/catch; on startup failure renders `_StartupErrorApp` ("Bugaoshan 启动失败" + stack trace + "Clear Shared Preferences" button).
2. `_initializeApp()`:
   - `WidgetsFlutterBinding.ensureInitialized()`, `DartPluginRegistrant.ensureInitialized()`
   - Desktop (win/linux/macos): `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`
   - `configureDependencies()` (GetIt) then `ensureBasicDependencies()` (DB, providers)
   - Fire-and-forget `UpdateService.cleanupOldPackages()`
   - Desktop only: `WindowStateService` restore window position/size
   - `SystemTheme.fallbackColor = Colors.blue; await SystemTheme.accentColor.load();` (system accent color)
3. `MyApp` (`app.dart`) post-frame: `BackgroundCacheService.precache()` (pre-decodes course-page background image).
4. Root gate inside `MaterialApp.home`:
   ```
   acceptedEulaVersion < currentEulaVersion  →  EulaGatePage
   else !firstLaunchWizardCompleted           →  WizardPage
   else                                        →  HomePage
   ```
   - `currentEulaVersion = 1` (`widgets/eula_content.dart`)
   - Debug builds default: `acceptedEulaVersion = 114515` (skip EULA), `firstLaunchWizardCompleted = kDebugMode` (skip wizard).
5. `MaterialApp` builder clamps text scale to `[1.0, 2.0]`, wraps in `MouseBackHandler` (desktop mouse back button → Navigator.pop) and `SessionExpiredListener`.
6. Theme: light+dark from same builder, `themeMode: ThemeMode.system` (follows OS; never overridden in-app).

### 1.2 EULA gate (`pages/wizard/eula_gate_page.dart`)

- `PopScope(canPop: false)` — cannot back out.
- Body: scrollable `EulaContent` (markdown from `assets/eula.md`) with an "agree" checkbox callback.
- Bottom row: `OutlinedButton` 不同意 → `ExitService.exitApp()` (kills app); `FilledButton` 同意 (enabled only when checked) → `acceptedEulaVersion.value = currentEulaVersion`.

### 1.3 First-run wizard (`pages/wizard/wizard_page.dart`)

`PageView` + bottom controls (page dots + skip/back/next), pages:

1. **WelcomePage** — app icon 96×96 (radius `AppShapes.largeIncreased`=20, shadow primary@0.20 blur 24 offset(0,8)), headline title + desc, `Spacer(flex:2)`.
2. **LoginPage** (`pages/wizard/login_page.dart`) — two `_StepCard`s (step number badge 40×40 radius 12 primaryContainer):
   - Step 1 "完成统一身份认证登录": `FilledButton.tonal` → opens `ScuLoginPage` via `popupOrNavigate`; shows ✓ + "完成" when `ScuAuthProvider.isLoggedIn`.
   - Step 2 "从教务系统导入课表": opens `ImportSchedulePage(mode: online)`; shows ✓ + "已导入" when `CourseProvider.hasSchedule`.
3. **FeaturesPage** — 3–4 feature cards (Course/Campus/Profile + Widget on Android), `WizardCard` style, ThirdCenter layout.
4. **WidgetPage** — Android only; embeds `AddWidgetContent(showDescription: false)`.

Bottom: dots (active 24×8 primary, inactive 8×8 outlineVariant, radius `AppShapes.xs`); buttons: Skip (hidden on first page), Back (fade), Next/开始使用 (FilledButton). Page animation: `cardSizeAnimationDuration` + `Curves.easeInOutQuart`. Max width 600 on wide screens.
Finish → `firstLaunchWizardCompleted.value = true`.

### 1.4 Home page / dock (`pages/home_page.dart`)

- `initState`: registers `WidgetsBindingObserver`; background update check (`UpdateProvider.checkForUpdate()` → sets `appConfig.hasUpdateNotification` badge on Profile tab icon); auto-login attempt (`ScuAuthProvider.autoLogin()`, or `AuthCoordinator.warmUpAll()` when already logged in).
- `didChangeAppLifecycleState.resumed` → `WidgetUpdateService.updateWidgetData()` (Android/iOS/macOS).
- Layout: `LayoutBuilder` — `maxWidth >= 600 && visibleIds.length >= 2` → `NavigationRail` (vertical, labels all) + VerticalDivider; else `NavigationBar` at bottom (height 64×textScale). Single visible item → no bar/rail.
- Body: `AuthScopedIndexedStack` (see §5.3) — lazily caches a page per visible dock id, animated slide+fade on tab change (horizontal axis on phone, vertical on rail), duration = `cardSizeAnimationDuration`, animation toggle = `enablePageTransitionAnimation`.
- Update badge: red `Badge` around Profile tab icon/selectedIcon when `hasUpdateNotification`.
- Index clamped to `visibleIds.length - 1`.

### 1.5 Dock items — full registry

From `utils/constants.dart` (ids) and `models/campus_item_config.dart` (icons/labels/pages).
**21 total** (3 default-visible + 18 optional). Default: `defaultVisibleDockIds = ['course', 'campus', 'profile']` (order matters — preview bar and dock render in list order).

| # | id | icon / selectedIcon | page widget | dock label key |
|---|----|--------------------|------------|----------------|
| 1 | `course` | `menu_book_outlined` / `menu_book` | `CoursePage` | dockLabelCourse |
| 2 | `campus` | `school_outlined` / `school` | `CampusPage` | dockLabelCampus |
| 3 | `profile` | `person_outlined` / `person` | `ProfilePage` | dockLabelProfile |
| 4 | `grades` | `bar_chart_outlined` / `bar_chart` | `GradesPage` | dockLabelGrades |
| 5 | `ccyl` | `event_outlined` / `event` | `CcylPage` | dockLabelCcyl |
| 6 | `plan_completion` | `assignment_turned_in_outlined` / `assignment_turned_in` | `PlanCompletionPage` | dockLabelPlanCompletion |
| 7 | `fitness_test` | `directions_run` / `directions_run` | `FitnessTestPage` | dockLabelFitnessTest |
| 8 | `exam_plan` | `assignment_outlined` / `assignment` | `ExamPlanPage` | dockLabelExamPlan |
| 9 | `train_program` | `history_edu_outlined` / `history_edu` | `TrainProgramPage` | dockLabelTrainProgram |
| 10 | `class_schedule_inquiry` | `calendar_view_week_outlined` / `calendar_view_week` | `ClassScheduleInquiryPage` | dockLabelClassScheduleInquiry |
| 11 | `course_curriculum` | `calendar_view_month_outlined` / `calendar_view_month` | `CourseCurriculumPage` | dockLabelCourseCurriculum |
| 12 | `classroom` | `meeting_room_outlined` / `meeting_room` | `ClassroomPage` | dockLabelClassroom |
| 13 | `network_device` | `router_outlined` / `router` | `NetworkDevicePage` | dockLabelNetworkDevice |
| 14 | `passpoint` | `wifi_password_outlined` / `wifi_password` | `PasspointPage` | dockLabelPasspoint |
| 15 | `balance_query` | `account_balance_wallet_outlined` / `account_balance_wallet` | `BalanceQueryPage` | dockLabelBalanceQuery |
| 16 | `repair` | `build_outlined` / `build` | `RepairPage` | dockLabelRepair |
| 17 | `academic_calendar` | `calendar_month_outlined` / `calendar_month` | `AcademicCalendarPage` | dockLabelAcademicCalendar |
| 18 | `zysc` | `event_outlined` / `event` | `ZyscPage` | dockLabelZysc |
| 19 | `leave` | `fact_check_outlined` / `fact_check` | `ServiceHallPage` | dockLabelLeave |
| 20 | `notice` | `campaign_outlined` / `campaign` | `NoticePage` | dockLabelNotice |
| 21 | `downloaded_attachments` | `folder_open` / `folder_open` | `NoticeDownloadedPage` | dockLabelDownloads |

Campus hub grouping (`campusSections`) — used by CampusPage and SetDockPage ordering context:
- **academicSection** (学业): grades, ccyl, plan_completion, fitness_test, exam_plan
- **utilitiesSection** (实用工具): train_program, class_schedule_inquiry, course_curriculum, classroom, network_device, passpoint, balance_query, repair, academic_calendar, zysc, leave
- **noticeSection** (通知): notice, downloaded_attachments

Campus-page accent colors per id (`pages/campus_page/item_accent.dart`):
```
grades 0xFF5B8DEF, ccyl 0xFF8B7CF6, plan_completion 0xFF3FA796, fitness_test 0xFFF27059,
exam_plan 0xFFE86A92, train_program 0xFF7C9A4E, class_schedule_inquiry 0xFF4FA3C4,
classroom 0xFF6C8CD5, network_device 0xFF5AB8A8, balance_query 0xFFE8A33D,
academic_calendar 0xFFD97757, zysc 0xFF9A7FD1, leave 0xFF6488C4, notice 0xFFE05D5D,
downloaded_attachments 0xFF8F9BA8, default 0xFF5B8DEF
```
Icon container tint: `accent.withValues(alpha: dark ? 0.24 : 0.14)`.

### 1.6 Dock customization (`pages/settings/set_dock_page.dart`)

- Top: live dock preview — container height `64 × textScale`, `surfaceContainerHighest`, radius 20, icons 24 + label `labelSmall`, evenly spaced.
- Visible items: `ReorderableListView` (no default drag handles) — each row is `StyledCard` + `ListTile` (leading icon primary) + `Switch` + 40px drag_handle. Drag proxy: translate -4×t + shadow (0.25α, blur 14×t, offset (0,5×t)).
- `profile` Switch is disabled (cannot remove profile from dock).
- Hidden items below a divider: same card, switch off.
- Bottom: reset to default `OutlinedButton.icon(refresh)` with confirm dialog.

### 1.7 Navigation patterns

- **No named routes.** Everything is `MaterialPageRoute` pushes or bottom sheets, mostly via `popupOrNavigate` (`widgets/route/router_utils.dart`):
  - Already inside a popup (`PopupContext.of`) → plain `Navigator.push`.
  - `landscape` → dialog of `width / 2` (`popupContent`).
  - `bigPortrait` (width>600 && height>600) → dialog `width*2/3`, `height*2/3`.
  - `smallPortrait` → full-screen push.
  - Dialogs embed a `Fragment` (nested `Navigator` with root "/") so pushes inside a popup navigate within the dialog.
- Global `navigatorKey` (`GlobalKey<NavigatorState>`); `logicRootContext` = its context. Dialogs (`showInfoDialog` etc.) always open on the root navigator (`useRootNavigator: false` relative to navigatorKey).
- Session expiry: `SessionExpiredListener` (wraps app below MaterialApp) — `ScuAuth.onSessionExpired` → SnackBar "登录已过期" with "前往登录" action → pushes `ScuLoginPage`; 5s cooldown, clears prior snackbars.

---

## 2. Page Catalog

### 2.1 Course feature area

| Page | Path | Purpose / structure |
|------|------|---------------------|
| **CoursePage** | `pages/course/main/course_page.dart` | Dock tab 1. Top bar + week PageView + background image + loading overlay. Full deep-dive §4. `demoMode:true` variant renders fixed week 1 for style preview (no controller, no listeners, no dialogs). |
| **ScheduleManagementPage** | `pages/course/management/schedule_management_page.dart` | ListView of all schedules; leading check_circle (current, primary) vs circle_outlined (grey); title = semesterName (fallback 默认课表), subtitle `共 N 周`; trailing: share (export sheet), edit (rename dialog with duplicate-name check), delete (confirm). Tap = switchSchedule + pop. AppBar: download (import sheet) + add (new schedule name dialog). Empty: ThirdCenter icon+text. |
| **CourseScheduleSetting** | `pages/course/settings/course_schedule_setting.dart` | "课表设置". Sections (SectionTitle + InfoCard): 学期配置 (start date picker — non-Sunday picks auto-adjust to Sunday with snackbar; set current week — CupertinoPicker bottom sheet 1..totalWeeks, recalculates start date from this week's Sunday; auto-fetch current week from zhjw (login-gated, spinner); total weeks picker 1..52). 时间 (→ TimeSlotSettingPage). 课程样式 (→ SetCourseStylePage). Empty schedule → `EmptySchedulePlaceholder`. |
| **TimeSlotSettingPage** | `pages/course/settings/time_slot_setting_page.dart` | Edits morning/afternoon/evening section counts, courseDuration (min), breakDuration (min), autoSyncTime, per-slot start/end times. Editing a slot cascades recomputation of following slots in the same period (start = prev end + break; end = start + duration). Auto-saves via `updateScheduleConfig`. |
| **CourseEditPage** | `pages/course/edit/course_edit_page.dart` | Add/edit/copy course form — see §4.6. |
| **ImportSchedulePage** | `pages/course/import/import_schedule_page.dart` | 3 import modes (share JSON paste / jwxt JSON paste / online fetch) — see §4.7. |
| **CourseDetailSheet** | `pages/course/widgets/course_detail_sheet.dart` | Bottom sheet on course tap — see §4.5. |
| special_day_sheet | `pages/course/widgets/special_day_sheet.dart` | Bottom sheet on header badge tap: type badge (holiday red / festival orange / solarTerm green) + name + date + total holiday days. |
| prompt_new_schedule | `pages/course/management/prompt_new_schedule.dart` | Dialog: input semester name → duplicate check → `addSchedule` cloning current config as template (or default config), start = this Monday, id = `millisecondsSinceEpoch.toString()`. |

### 2.2 Campus hub (`pages/campus_page/campus_page.dart`)

- Root of dock tab 2. CustomScrollView; top row = first section header + 44×44 pill (radius full) search badge (StyledCard). Tapping expands into a search field card (back arrow, TextField, clear button, AnimatedSize 250ms easeInOutCubic).
- Search filters all campus items by dockLabel/dockFullLabel/desc (case-insensitive); results render in current layout mode; empty → search_off icon + text.
- **List mode** (default): per section `CampusSectionHeader` + `CampusListCard` rows (accent-colored icon container, title=dockFullLabel, desc, chevron), 8px gaps. Final "其他" section: grid/list view switch card + "更多功能" card → GitHub feature-request URL.
- **Grid mode** (`campusGridView` setting): `SliverGrid` maxCrossAxisExtent 140, spacing 12, childAspectRatio 0.9, `CampusGridCard` (icon + dockLabel).
- Layout switch is an `AnimatedSwitcher` (300ms fade).
- Bottom scroll hint: 64px gradient fade + bouncing keyboard_arrow_down (auto-hides past 40px scroll).
- Items open via `popupOrNavigate(logicRootContext, item.page())`.

### 2.3 Academic area

- **GradesPage** (`campus/grades/`) — dock tab candidate. AppBar with embedded search TextField (filters all tabs); desktop-only refresh button; `TabBar` (indicatorSize label, weight 3) with 3 tabs: 方案成绩 (SchemeScoresTab: summary card GPA/credits + scheme selector + per-course ScoreCard list), 及格成绩 (PassingScoresTab: overall summary card + term headers + course rows), 自定义统计 (CustomStatsTab: term selector + custom summary + course selection). Body = `SwipePageView(tabController, keepPagesAlive: true)`. Login gate: `AutoLoginLoadingWidget` / `LoginRequiredWidget`.
- **CcylPage** (第二课堂, `campus/ccyl/`) — 3 gate states: not logged in → login widget; SCU logged in but CCYL unbound → bind prompt → `CcylBindPage`; bound → `IndexedStack` + bottom `NavigationBar` with 4 tabs: 查活动 (ActivitiesTab, search + list + `ActivityDetailPage`), 我的 (MyActivitiesTab), 已预约 (OrderedActivitiesTab), 学分 (CreditListPage; → `ActivityLibDetailPage`).
- **PlanCompletionPage** (培养方案完成度) — loads `PlanCompletionProvider.fetchPlanCompletion`; AppBar refresh button (spinner swap); multi-plan horizontal swipe (SwipePageView-like via provider.currentPlanIndex); tree of `PlanCompletionNode` rendered recursively (rootNodes = pId == '-1'), progress = earnedCredits/requiredCredits per node; snackbars for rate-limited / stale-cache errors.
- **FitnessTestPage** (体测) — TabBar 2 tabs 成绩/通知, `SwipePageView(keepPagesAlive: true)`. Scores tab: year selector (`selectYear`, persisted `fitness_test_selected_year`), score card with items; privacy toggle hides scores (`_privacyHidden`); notices tab: notice list.
- **ExamPlanPage** (考试安排) — AppBar: calendar export button (writes exam ICS) + refresh. States: loading spinner → notLoggedIn → RetryableErrorWidget → empty text → RefreshIndicator + ListView of exam cards (StyledCard: course, seat, room, date/time sections; countdown to next exam). Export via `CalendarExportUtils` action sheet.

### 2.4 Utilities area

- **TrainProgramPage** (培养方案, `campus/train_program/`) — filter card: college dropdown + grade dropdown + FilledButton 查询; program list below. `TrainProgramDetailPage` (part file): program header + course table; course rows → `fetchCourseDetail` detail view.
- **ClassScheduleInquiryPage** (班级课表查询) — filter card (`CardWithTitle` + tune icon): semester/grade/department/subject/class dropdowns (grade+department+subject cascade loads); paged class list (30/page, load-more); tap class → `ClassScheduleInquiryDetailPage` renders aggregated `CourseGrid(showAllWeeks: true, showHeaderDates: false)` (MinimalWeekdayHeader + merged same-slot courses + side-by-side tracks).
- **CourseCurriculumPage** (课程课表查询) — same shape as class inquiry but filters semester/department/category + courseName/courseCode/courseSeq text inputs; detail page also uses aggregated CourseGrid.
- **ClassroomPage** (空教室查询, 739 lines) — 3-step drill: campus chips/cards → building list (with date picker: -7d..+30d, "今天" button, period filter 1..12) → room list with live availability (1-minute clock Timer → recompute current period). `ClassroomDetailPage`: room info card (counts of free/inClass/exam/experiment/borrowed across 12 periods) + 12-period status grid.
- **NetworkDevicePage** (校园网设备) — user info card (from UserInfoProvider) + device list card (ip, mac, login time), per-device 下线 button (confirmation, spinner on row), refresh; refresh-failure banner keeps stale list. Privacy blur toggle on MAC/IP.
- **PasspointPage** (无感认证) — device list (StyledCards with InfoRow) + user info card; FAB.extended "添加设备" → bottom-sheet form (MAC input, expiry picker); cancel per device. Privacy toggle.
- **BalanceQueryPage** (电费/空调余额) — AppBar: settings sheet (auto-sample-on-login switch), room switcher PopupMenu (bindings with check + delete, "绑定新房间"). Body: no bindings → home icon empty state + 绑定按钮; else `BalanceList` → two `BalanceCard`s (照明/空调: balance, price, refresh-on-tap, cached 30min) + trend entry card. `BindRoomDialog`: campus → building → unit cascading dropdowns (from payapp API) + room number. `BalanceTrendPage`: range tabs (7/30/90天/自定义), trend chart card, raw records card.
- **RepairPage** (在线报修, zhhq) — TabBar 2 tabs 提交报修/我的工单, SwipePageView keepPagesAlive. Submit tab: address selector, repair project selector, description, image upload (multi), book date/time pickers, submit. My tickets tab: ticket list → `RepairDetailPage` (status timeline, withdraw + evaluate actions).
- **AcademicCalendarPage** (校历) — TabBar 2 tabs 官方校历 / 交互校历. Official: scrapes `https://jwc.scu.edu.cn/cdxl.htm` (latin1 decode, regex for info/1101/*.htm links, 8s timeout) → year entries → detail page fetches image URLs; interactive: bundled `assets/academic_calendar.json` rendered by `InteractiveCalendarView` (semester picker, month grid with events).
- **ZyscPage** (志愿四川) — pure `WebViewNoticePage` for `https://zysc.scyol.com/fzysc/#/pages/tabbar/index` with beautify JS asset `assets/js/volunteer_sichuan.js`, loading mask disabled.
- **ServiceHallPage** (办事大厅) — ListView of `kServiceAppCatalog` (4 items: 350 离校请假 fact_check_outlined [has fieldOrder override + fallback schema], 337 返校报备 home_work_outlined, 356 暑假离校 beach_access_outlined, 357 留校登记 apartment_outlined) + 我的申请 card → `MyApplicationsPage` (ServiceApplicationsProvider list). Each app → `ServiceFormPage`: generic server-plugin-driven dynamic form (ServiceFormController, field widgets in `service_field_widgets.dart`, region picker from `assets/region_data.json`, file upload, submit + captcha option).

### 2.5 Notice area

- **NoticePage** — hub with 3 StyledCard ListTiles: 校园通知 (campaign, jwc) → `CampusNoticePage`; 党委学工部 (flag, xgb) → `PartyNoticePage`; 团委 (volunteer_activism, tuanwei) → `TuanweiNoticePage`. Sub-pages are scraped/WebView notice lists (28-line wrappers) with detail → `WebViewNoticePage` or native detail; attachments listed via `AttachmentsSheet`, downloads land in per-source folders.
- **NoticeDownloadedPage** (已下载附件, 788 lines) — file manager over download dirs; 3 tabs (教务处通知 / 党委学工部通知 / third config), search by name, extension filter, sort (time/name/size), multi-select mode (select all/delete/share), open via `open_filex`, FAB share. Pre-computed file metadata to avoid sync IO in item builder.

### 2.6 Profile area (`pages/profile/`)

- **ProfilePage** — vertical scroll, ThirdCenter, spacing 12: `LoginStatusCard`, `AnimatedSize(UserInfoCard)`, `ProfileMenuCard`.
- **LoginStatusCard** — LoginStatus enum {autoLoggingIn, loggedIn, sessionExpired, notLoggedIn} derived from ScuAuthProvider; avatar-ish icon + status text + login/logout buttons (logout confirm dialog); privacy toggle for username.
- **UserInfoCard** — UserInfoProvider (SCU student info: name, college, major, class, id...); renders label/value rows; tap = retry; hides when no data.
- **ProfileMenuCard** — InfoCard of 5 IconTiles: 课表管理 (ScheduleManagementPage), 课表设置 (CourseScheduleSetting; disabled grey when no schedule), 软件设置 (SoftwareSettingPage), 使用手册 (LinkTile → https://bugaoshan-docs.scubro.dev/manual/), 关于 (BadgedTile with red dot when hasUpdate → AboutPage).

### 2.7 Settings area (`pages/settings/`)

- **SoftwareSettingPage** — 3 sections: 通用 (语言 SetLanguagePage, [Android] 应用图标 SetAppIconPage, 动画时长 SetDurationPage, 自定义底栏 SetDockPage, [Android] 添加小组件 AddWidgetPage); 样式 (主题颜色 SetThemeColorPage, 课程样式 SetCourseStylePage, 字体 SetFontPage); 危险 (清除所有数据 — confirm → logout + clearCredentials + appConfig.clearAll + courseProvider.clearAllData).
- **SetThemeColorPage** — SegmentedButton 3 modes (跟随系统 settings_suggest / 背景图片 wallpaper / 自定义 palette); hint card (secondaryContainer); `BlockPicker` (flutter_colorpicker); whole page wrapped in preview `Theme(colorScheme: fromSeed(pickerColor))` so controls preview the scheme; AppBar 确认 saves `themeColor` + `themeColorMode` then pops. Background-image mode extracts dominant color via `SetThemeColorProvider` (quantized 0xF8F8F8 histogram over ≤5000 samples, isolate).
- **SetCourseStylePage** — top half (clamped 200–400px) live preview = `CoursePage(demoMode: true)` keyed by background path; below: sliders/switches (values & defaults in §4.8); background image pick (copied to `documents/backgrounds/schedule_bg.ext`), crop editor push, remove, opacity slider 0.05–0.8 (15 divisions); reset-to-default TextButton.
- **SetDurationPage** — switch 启用页面切换动画 (dock switch animation) + slider 0–1000ms (20 divisions) for `cardSizeAnimationDuration` (drives ALL page transitions + dock switching + AnimatedSize durations).
- **SetLanguagePage** — radio list of `AppLocalizations.supportedLocales` (zh/en) + 跟随系统.
- **SetFontPage** — single switch: 使用 Google Fonts (NotoSansSc); default true.
- **SetAppIconPage** (Android) — dynamic icon switcher (`bugaoshan/dynamic_icon` MethodChannel; assets `icon.png` / `icon_old.png`).
- **AddWidgetPage** (Android) — widget preview cards per size (WidgetSize enum small/medium/large), pin-request flow (`pinWidget(size)` + `onWidgetPinned` event + 5s verify delay), battery-optimization card, hint card.
- **BackgroundCropEditorPage** — full-screen gesture crop of the background image (pan/zoom → `BackgroundCropParams` normalized focus/scale, shared render math with `BackgroundImageView`).
- **EulaStatusPage** — current accepted EULA version + link to content.

### 2.8 About / Dev area

- **AboutPage** (`pages/about/`) — centered header (app icon 100, name, version from AppInfoProvider), update tile (check → `showUpdateDialog` → `showDownloadProgressDialog`), 更新日志 (ReleaseNotesPage), 团队 (TeamPage), links (official site https://bugaoshan.scubro.dev/, repo, user manual), EULA status, dev entry (DevPage).
- **DevPage** (`pages/dev/`) — ListView: EnvironmentInfoTile (version/commit/env), WizardResetTile (reset first-launch wizard), AuthLogTile (→ AuthLogViewerPage with filter bar), UiTile (→ UI playground page), ChangelogTile, `forceCaptchaForDownload` switch, and (if in-app update supported) update section: `usePreviewUpdateSource` switch + stable/preview `UpdateCard`s + check button (`getAllLatestReleases`).
- Update dialogs (`widgets/dialog/`): `update_dialog.dart` (version + release notes + 开始更新), `download_progress_dialog.dart` (progress bar, cancel via CancelToken, status labels 下载中/校验中/安装中).

### 2.9 Auth pages (`pages/auth/`)

- **ScuLoginPage** (393 lines) — header image (`scu_header_light/dark.webp`), username/password/captcha `TextFormField`s (captcha row: base64 image + reload + OCR auto-fill via `OcrService`), obscure toggle, 记住密码 + 自动登录 checkboxes (secure storage), disclaimer (本软件非官方…), login button (loading state), 忘记密码 → `ScuResetPasswordPage` (738 lines, multi-step reset flow with captcha/SMS). Pops `true` on success.
- Login page parts: `scu_login_input_field.dart`, `scu_login_button.dart`, `scu_login_checkbox.dart`, `scu_login_disclaimer.dart`, `scu_login_header_image.dart`, `scu_login_captcha_row.dart`.

### 2.10 Wizard/dev sub-pages

- AuthLogViewerPage (auth log list + severity filter), UI playground (`dev/ui/`), ChangelogVersionPage (`dev/changelog/`).

---

## 3. Provider Catalog

Common conventions:
- All are GetIt singletons (`getIt<XProvider>()`), UI subscribes with `ListenableBuilder(Listenable.merge([...]))`.
- Load-state enum per provider: `{idle, loading, loaded, error}` + `LoadErrorType?` error (`widgets/common/retryable_error_widget.dart`: sessionExpired, loadFailed, networkError, campusNetworkRequiredAtNight, campusNetworkRequired, rateLimited, ccylActivityLoadFailed, ccylBindFailed, notLoggedIn).
- `campusNetworkErrorType(default)`: between 23:00–06:00 returns campusNetworkRequiredAtNight (zhjw closed off-campus at night).
- Generation counters (`_generation`) guard stale async writes; `UnauthenticatedException` → sessionExpired.
- Pattern: `ensureX()` (load if absent) vs `refresh()` (force).

### AppConfigProvider (`providers/app_config_provider.dart`) — settings store
- Constructor takes `SharedPreferences`; `init()` loads + attaches per-key save listeners (every change persists immediately).
- All state is `ValueNotifier`. Keys & defaults (prefs key → default):
  - `locale` (language tag; null = system)
  - `cardSizeAnimationDuration` (int ms) → 200
  - `themeColor` (int ARGB) → Colors.blueAccent
  - `colorOpacity` → 0.85
  - `courseCardFontSize` → loaded default **14.0** (field initial 13.0)
  - `showCourseGrid` → true
  - `courseRowHeight` → 72.0
  - `backgroundImageOpacity` → 0.3
  - `backgroundImagePath` (String? path)
  - `backgroundImageCrop` (encoded BackgroundCropParams?)
  - `firstLaunchWizardCompleted` → false (debug: true)
  - `hasUpdateNotification` → false
  - `visibleDockIds` (string list) → [course, campus, profile]
  - `acceptedEulaVersion` → 0 (debug: 114515)
  - `themeColorMode` (index of ThemeColorMode {system, backgroundImage, custom}) → system
  - `widget_show_tomorrow` → false; `widget_color_style` (WidgetColorStyle{colorful=0,monochrome=1}) → colorful; `widget_density` (WidgetDensity{standard=0,compact=1}) → standard
  - `usePreviewUpdateSource` → false; `useGoogleFonts` → true
  - `showTeacherName`/`showLocation`/`showCourseWeeks` → true; `showWeekend` → false; `showNonCurrentWeekCourses` → true
  - `campusGridView` → false; `autoSampleBalanceOnLogin` → false; `forceCaptchaForDownload` → false; `enablePageTransitionAnimation` → true
- Global `appCurve = Curves.easeOutQuart`.
- `resetDockToDefault()`; `clearAll()` wipes prefs and reloads defaults.

### CourseProvider (`providers/course_provider.dart`) — local DB (no auth)
- Fields: `courses: ValueNotifier<List<Course>>`, `scheduleConfig: ValueNotifier<ScheduleConfig?>`, `allSchedules: ValueNotifier<List<ScheduleConfig>>`, `isLoading: ValueNotifier<bool>`; `onCoursesChanged` VoidCallback hook (set by WidgetUpdateService → refresh home-screen widget after every mutation).
- Methods: `_loadData` (initial), `switchSchedule(id)`, `addSchedule` (adds + auto-switches), `deleteSchedule`, `addCourse/updateCourse/deleteCourse` (each re-reads `db.getCourses()` + fires onCoursesChanged), `updateScheduleConfig`, `replaceScheduleCourses` (delete+insert), `hasConflict(course, excludeId)` (async DB check), `isScheduleNameTaken/findScheduleIdByName`, `getCoursesForWeek`, `clearAllData`.
- No caching layer beyond memory; DB is source of truth.

### GradesProvider (`providers/grades_provider.dart`)
- Per-identity cache in SharedPreferences keyed `grades_scheme_scores_<user>` / `grades_passing_scores_<user>`; `setUserIdentity` (only confirmed SCU principal) restores cache and bumps identity generation.
- Two independent resources: 方案成绩 (schemes: List<SchemeScoreSummary>, selectedSchemeName, schemeState/schemeError; `schemeScores` getter falls back to default scheme) and 及格成绩 (passingScores/passingState/passingError).
- On error with existing data: stays `loaded` + sets error (stale-cache banner); no data → `error` state.

### BalanceQueryProvider (+ `balance_query_state.dart`) — 573 lines
- Room-scoped (NOT account-scoped): bindings persisted (`balance_query_binding`, `balance_query_current_room`), history in DB table `balance_records` keyed `roomKey = schoolCode_regCode_unitCode_roomNo`.
- Resource cache pattern `_ResourceEntry<T>` {value, updatedAt, isLoading, error, inFlight}; balances cached **30 min** (`_balanceCacheDuration`), campus/building/unit lists cached for session. Balance type constants: electric=1, AC=2.
- `balanceStateFor(type)` returns `BalanceResourceState<RoomInfo>`; stale entry → hides value (loading/error only).
- Auto-sample: PayAppAuth ready edge + `autoSampleBalanceOnLogin` + no Beijing-today record → silent force load (records history only on success; retention 365 days).
- Trend: `trendStateFor({type, since, until})` / `ensureTrend` → DB records + `BalanceTrendCalculator`.
- Ops: addBinding/removeBinding (deletes DB history for room)/switchBinding (verificationRoom then reload); queryElectricInfo/queryAcInfo = forced refresh.

### CcylProvider
- Thin wrapper over `CcylAuth` (token, isLoggedIn, currentUser) + `CcylApiService` accessor `service`; loginWithOAuthCode/logout/reLogin; notifies on auth change. UI fetches activities/credits directly via `service`.

### ClassroomProvider
- Index (campuses+buildings) loaded once; availability queries cached by (campusNumber, buildingNumber, searchDate) in `_ClassroomQueryResource` map, **max 30 entries** (evict oldest insertion-order, keep current). Epoch bump invalidates.

### CourseCurriculumProvider / ClassScheduleInquiryProvider (twins)
- pageSize **30**; paged list with local page variable committed only on success; filter-change detection compares all filter strings; index (semesters/departments[/categories|grades]) auto-selects first semester then `search()`.
- Detail schedules cached per class/course key (planCode+classCode / planCode+courseCode+courseSeq), **LRU max 50** with per-key generation guards; `detailStateFor` performs LRU touch.

### ExamPlanProvider
- Simple single resource; `UnauthenticatedException` maps to **notLoggedIn** (unique — page shows LoginRequiredWidget instead of sessionExpired).

### FitnessTestProvider
- Notices + score(year) resources; selectedYear persisted (`fitness_test_selected_year`, default current year); epoch+generation+inFlight-year guards; `ensureNotices/ensureScore` reuse in-flight future; `selectYear` clears and force-reloads.

### NetworkDeviceProvider / PasspointProvider (auth-gated twins)
- Listen to subsystem auth (WfwAuth / NewServiceAuth) AND ScuAuth; `_canLoad = scuAuth.isReady && subAuth.isReady`; on became-ready → ensureLoaded, on not-ready → clear(). Requests coalesce via `_loadFuture`.
- Ops with separate operation generation: `forceOffline(device)` / `addDevice(mac, expire)` / `cancelDevice(device)`; op errors kept separate from list errors; server message strings surfaced (`addErrorMessage`/`cancelErrorMessage`).

### PlanCompletionProvider
- Whole plan tree cached in prefs `plan_completion_nodes` (new format: [{id,name,nodes:[…]}]; old format = bare node array wrapped as single plan). `selectPlan(index)`; error keeps stale data as loaded; RateLimitedException → rateLimited error.

### ServiceApplicationsProvider
- One-shot "我的申请" list (`fetchMyApplications`), standard ensure/refresh/clear.

### TrainProgramProvider
- Five resources: colleges+grades (fetched together), programs (search), program detail, course detail; per-resource state+error; generation guards on details; `_safeNotify` (post-frame notify).

### UpdateProvider
- ValueNotifiers: isChecking, lastCheckResult, stableResult, previewResult (initial), isDownloading; `progressState: UpdateProgressState` (ChangeNotifier with setStatus/setProgress/percent).
- All async ops reentry-protected by in-flight future caching. `downloadAndInstall` wires progress → notification channel (`bugaoshan/download_cancel` EventChannel for cancel), requests notification permission, shows download notification, cancels on completion, error notification on failure. `supportsInAppUpdate` platform-gated (F-Droid installs excluded via installer-store list in AppInfoProvider).

### ZhhqRepairProvider (repair, 453 lines)
- Gated on zhhq tokenKey only (`isReadyForRequest`); auth-failed → error state (retryAuth re-runs `ensureAuthenticated`); SCU logout (state unknown) → clear.
- Addresses loaded alone (fast); tickets loaded lazily (`loadTickets`, single-flight; **force waits** for in-flight then re-fetches — server write lag workaround: withdraw/evaluate set `_ticketsLoaded = false`, refresh happens on return-to-list).
- Submit ops: addAddress/submitTicket (payload map) with `_isSubmitting` + `submitError`; uploads via `uploadImage(File)`; booking dates/times + area tree + projects + acceptDept all degrade to empty on failure.

### AppInfoProvider
- packageInfo (version, buildNumber, signature, installerStore); `GIT_TAG`/`GIT_COMMIT`/`GIT_COMMIT_DATE` from `String.fromEnvironment` (compile-time); `isFdroidInstall` checks installer ∈ {org.fdroid.fdroid, org.fdroid.basic, com.looker.droidify, com.machiav3lli.fdroid}; `getVersionInfo()` assembles 4-section VersionInfo text.

### ExportScheduleProvider
- Stateless helper over CourseProvider (or override config/courses for non-active schedule): `copyToClipBoard()` → JSON {config, courses}; `buildCalendarPayload(teacherLabel)` → ICS payload via IcsService.

### SetThemeColorProvider
- `previewSystemColor()` / `previewBackgroundImageColor()` / `extractColorFromBackgroundImage()` — dominant color via quantized histogram (mask 0xF8F8F8, alpha>128, ≤5000 sample stride) computed in isolate; keeps `_extractedColor` + `_lastExtractResult`.

### Auth providers (context only): ScuAuthProvider (ChangeNotifier: isLoggedIn, isAutoLoggingIn, isExpired, accessToken, autoLogin, fetchCaptcha, saved credentials via SecureStorage) and UserInfoProvider (SCU student profile fetch + retry). Not detailed here (out of scope) but every campus page gates on them.

### DatabaseService (`services/database_service.dart`)
- SQLite `bugaoshan.db` (app documents dir). Tables:
  - `metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)` — `currentScheduleId`
  - `schedules(id TEXT PRIMARY KEY, config_json TEXT NOT NULL)`
  - `courses(id TEXT PK, schedule_id TEXT, name, teacher, location, campus TEXT NOT NULL DEFAULT '', start_week, end_week, day_of_week, start_section, end_section, color_value INTEGER, week_type INTEGER, FK schedule_id ON DELETE CASCADE)` (v2 = campus column)
  - `balance_records(...)` (v2)
- This file/db is shared with the iOS widget extension (§7).

---

## 4. Course Page Deep-Dive (most important screen)

### 4.1 Composition (`course_page.dart`)

```
Column
├── CoursePageTopBar            (hidden in demoMode / no controller)
└── Expanded → Stack
    ├── Positioned.fill → BackgroundImageView (path, crop, overlayOpacity)   // if bg set
    ├── CourseSwipePageView (week pages) OR NoScheduleView
    └── ValueListenableBuilder<bool> isLoading → centered CircularProgressIndicator
```

- Controller lifecycle: `CoursePageController` created only when `hasSchedule && scheduleConfig != null`; listens for empty↔non-empty flips both ways (no→有 creates controller; 有→无 disposes, back to NoScheduleView).
- Lifecycle observer: on `resumed` → `controller.refreshToday()` (recompute vacation page availability + repaint for cross-midnight today-highlight; **never auto-jumps week**).
- Post-frame on create: `_checkAndPromptNextSemester()` — bundled academic calendar → next semester after current end; if registration date passed and a matching local schedule exists → AlertDialog 切换学期 (取消 / 切换课表) → `switchSchedule(matchId)`.

### 4.2 Top bar (`course_page_top_bar.dart`)

- Padding h16 v2. Left cluster (tap = 回到当前周):
  - Line 1: `yyyy/m/d` bold `titleSmall`.
  - Line 2: `chevron_left`(16) — AnimatedSize week label `第 N 周` / `放假中` (`bodySmall` w500 onSurfaceVariant) — `chevron_right`(16); then a badge:
    - `_WeekBadge`: `本周` (primaryContainer/onPrimaryContainer) when visibleWeek == actualWeek, else `当前第 N 周` (secondaryContainer/onSecondaryContainer); fontSize 9, w600, padding h5 v1, radius full.
    - `_NotStartedBadge` 未开学 (surfaceContainerHighest) when today < semesterStart.
    - `_VacationBadge` 放假中 (tertiaryContainer) when today is between semesters.
- Right cluster: if `schedules.length > 1` → `PopupMenuButton` (icon swap_horiz 20, padding 6 → 32×32): schedule rows (check icon 20 + name) + divider + 管理课表 (sentinel `'__management__'`). Then IconButtons: download_rounded (20, 导入), share_rounded (20, 导出), add_circle_rounded (24, 添加课程); all `BoxConstraints(minWidth:32, minHeight:32)`.
- Chevrons disabled (disabledColor) at first/last page.

### 4.3 Week swiping & controller (`course_page_controller.dart`)

- Source of truth: `int _pageIndex` (settled page); `PageController` is executor only. `onPageChanged → onPageSettled` is the feedback channel (clamped, silent when equal).
- `pageCount = showVacationPage ? totalWeeks + 1 : totalWeeks`; `visibleWeek = clamp(_pageIndex, 0, totalWeeks-1) + 1`; `isViewingVacation = showVacationPage && _pageIndex >= totalWeeks`.
- `_computeShowVacationPage()`: today > semesterEndDate AND a different schedule starts after current end AND today < that start.
- `goToToday()`: no-op if notStarted or onVacation; else refresh availability + animate to `_indexForToday()`.
- `_moveTo`: clamp → update index → if PageView mounted: `animateToPage(duration: cardSizeAnimationDuration, curve: AppCurves.quick /*easeOutQuart*/)` or `jumpToPage` with `_suppressOnPageSettled`; if not mounted: swap in a new `PageController(initialPage: target)`.
- Schedule/config change: recompute vacation page, invalidate cached next-semester (generation-guarded lazy load), jump (no anim) to today's page, post-frame resync.
- `ensureCalendarNextSemester()`: lazy `AcademicCalendarService.loadBundledCalendar()` → `findNextSemester(semesterEndDate)`; exposed via `calendarNextSemester`/`calendarNextSemesterLoading` ValueNotifiers; `hasCalendarNextSemesterSchedule` for CTA enablement.
- Swipe container = `SwipePageView` (§5.4): NeverScrollable PageView + outer pan GestureDetector; direction lock after 8px (horizontal when dx > dy×1.5); page flip on |velocity| > 100 px/s or |drag| > 50px.

### 4.4 Grid layout (`pages/course/widgets/`)

**CourseGrid** parameters:
- `_sectionWidth = 35` (left time column, fixed)
- `dayCount = showWeekend ? 7 : 5` (setting default false). Weekend on → column order is **Sun, Mon..Sat** (`day = dayIndex == 0 ? 7 : dayIndex`).
- Vertical scroll (singleChildScrollView) wrapping `Row[ GridSectionColumn(35px), Expanded(Row of GridDayColumn…, each Expanded) ]`.
- Header (40 × textScale): full `GridHeaderRow` (weekday + date M/d, today highlighted primaryContainer@180 + primary text bold; holiday/festival/solarTerm badges: bg color@30, label fontSize 9 bold white, radius 8) or `MinimalWeekdayHeader` (weekday names only) when `showAllWeeks || !showHeaderDates`.
- Grid lines per section row: boundary rows (end of morning = morningSections; end of afternoon = morning+afternoon) → `primary.withAlpha(150)`, width 1.5; normal → outlineVariant 0.5; right border outlineVariant 0.5. Header bg `surfaceContainerHighest` unless background image set.
- **GridSectionColumn**: per section: number (13 bold), start time (11, onSurfaceVariant), end time shown only when `rowHeight >= 60`; FittedBox scale-down.
- **GridDayColumn**: `SizedBox(height: rowHeight * sections)` + Stack of Positioned cards:
  - card top = `(startSection-1) * rowHeight + 1`, height = `(endSection-startSection+1) * rowHeight - 2`, left/right inset 1.
  - `showAllWeeks` mode: `assignCourseTracks()` splits column width into parallel tracks for overlapping courses (`TrackInfo{track, totalTracks}` per connected overlap component; width = columnWidth/totalTracks − 2).
  - Empty-cell tap targets (translucent GestureDetectors per unoccupied section): first tap selects (primary@100 fill, primary@150 border radius 8, add icon 32 onPrimaryContainer), second tap on same cell → add-course prefilled.
- **Course visibility logic** (`grid_logic.dart`):
  - `selectVisibleCoursesForDay(courses, week, showNonCurrentWeekCourses)`: in-range + sorted by `compareCoursesForLayout` (startSection asc → duration desc → startWeek asc). If showNonCurrentWeekCourses, append future courses (week < startWeek) that don't section-overlap any visible one.
  - `mergeSameSlotCourses`: same name+day+section-range+location → one card (teachers deduped joined by 、; locations joined by ' · '; weeks min/max; weekType falls back to every if mixed).
- **CourseCard**: bg `course.color.withValues(alpha: colorOpacity)` when active in display week (weekType parity respected); inactive → greyscale(luma 0.299/0.587/0.114) @0.12 alpha + 0.5 border textColor@50; effective bg = alphaBlend over scaffold bg; text color = luminance > 0.45 ? black87 : white. Padding 4, radius `AppShapes.small` (8). Title bold `fontSize = courseCardFontSize` (height 1.1, maxLines 6; inactive prefix "非本周 "). Detail lines (smallFontSize = clamp(fontSize×0.85, 8, 16)): location (render max 4 lines), teacher (max 2), `N-M 周` (max 4) — gated by the three show* settings; line budget by card height: `<56 → 0, <100 → 3, else 5` (each detail consumes its preferredMaxLines=1 from budget). Inner content in a never-scrollable SingleChildScrollView (clips overflow without scrollbar).

### 4.5 Course detail sheet (`course_detail_sheet.dart`)

Bottom sheet (radius top 28) with:
- Header: course name `titleLarge` bold + actions (only when provider passed): delete (error color, confirm dialog → deleteCourse → pop), copy (opens `CourseEditPage.createCopy` with "(副本)" suffix), edit (opens `CourseEditPage(course:)`). All 22px icons, shrinkWrap tap targets; sheet pops then navigates on root context.
- Divider; info list (`_InfoItem`: icon 24 colored + 16 gap + bodyLarge text, vertical padding 12):
  - calendar_today_outlined (teal): `N-M 周` + 单周/双周 suffix
  - access_time_outlined (orange): `第 a-b 节   HH:mm - HH:mm` (time from config.timeSlots)
  - person_outline (blue): teacher (if non-empty)
  - location_on_outlined (redAccent): location (if non-empty)

### 4.6 Course edit page (`course_edit_page.dart`)

Scaffold AppBar: 添加课程 / 编辑课程 / 创建课程副本 + 保存 TextButton. Body: form in SingleChildScrollView(padding 16, spacing 16):
1. 课程名称 TextFormField (required validator) — OutlineInputBorder
2. 教师 TextFormField
3. 上课地点 TextFormField
4. 课程颜色: 12 preset 36×36 circles (see below) + custom (+ circle → BlockPicker dialog); selected = 3px onSurface border
5. Divider; 上课周次: `N-M 周` title + two 80px dropdowns (start 1..totalWeeks; end startWeek..totalWeeks; end auto-raises)
6. 单双周: ChoiceChips 每周/单周/双周 (WeekType every/odd/even)
7. Divider; 星期: 7 ChoiceChips ordered 日一二三四五六 (day 7 = Sunday first chip)
8. Divider; 节次: two 80px dropdowns (start 1..sectionsPerDay; end start..sectionsPerDay)
9. 编辑模式 only: red delete TextButton.icon (confirm)

Preset colors (verbatim):
```
0xFFEF5350 Red, 0xFFEC407A Pink, 0xFFAB47BC Purple, 0xFF7E57C2 Deep Purple,
0x FF5C6BC0 Indigo, 0xFF42A5F5 Blue, 0xFF26C6DA Cyan, 0xFF26A69A Teal,
0xFF66BB6A Green, 0xFF9CCC65 Light Green, 0xFFFFA726 Orange, 0xFF8D6E63 Brown
```
Save: validate → cross-period check (course must fit entirely in morning ≤morningEnd, afternoon, or evening > afternoonEnd — else 跨时段 error dialog) → `hasConflict` (exclude self in edit mode; copy mode conflicts with source by design) → add/update → pop root. `campus` field preserved from original (never edited here).
Prefill: `prefillDayOfWeek`/`prefillSection` used by empty-cell tap (endSection = prefill+1).

### 4.7 Import flow (`import_schedule_page.dart`)

`ImportMode { share, jwxt, online }`. Entry: bottom sheet with 3 ListTiles (share / school / cloud_download icons) — from top bar, ScheduleManagement, and wizard.

- **share / jwxt**: full-screen multiline TextField (paste JSON) + AppBar 保存. share parses `{config:…, courses:[…]}`; jwxt parses via `jwxt_parser.parseJwxtData` after a name dialog (default `导入的课表 M月d日`). Then: new id (ms timestamp) → validate → `applyCampusTimeSlotsForCourses` (auto campus time preset, 4-5-3 only) → name-conflict resolution dialog (取消 / 添加后缀 / 更新已有课表 → replaceScheduleCourses + refresh preset timeSlots) → addSchedule + addCourse loop (regenerate empty/dup ids) → success snackbar + pop.
- **online**: centered column (cloud icon 64, hint, progress). Steps: login check → `fetchSemesters()` (find `（当前）` label → remember clean name) → semester dialog (dropdown + 导入全部 / 确定) → batch conflict pre-check (统一后缀 / 全部更新 dialog) → per semester: fetch jwxt schedule, parse (auto-enables showWeekend if weekend courses), name/customize, conflict handling, add; progress `N/M` LinearProgressIndicator → switch to 教务处-marked current semester → silently match each import against bundled academic calendar (set semesterStartDate + totalWeeks) → success snackbar + pop. Errors: ScuException message dialog; generic → 导入失败.

### 4.8 No-schedule / vacation views & style defaults

- **NoScheduleView**: ThirdCenter, maxWidth 360; 96×96 primaryContainer circle + calendar_month icon 48; 暂无课表 titleLarge w600 + hint bodyMedium; full-width buttons: FilledButton.icon(download, 导入课表), OutlinedButton.icon(list_alt, 课表管理), OutlinedButton.icon(add, 新建课表).
- **VacationView** (extra page after last week when between semesters): ThirdCenter, maxWidth 360; `放假中` title; 20×20 spinner while calendar loads; then days-until text (距离放假 N 天 / 距离下学期开课 N 天; on vacation with no next semester → 尽情享受假期); next-semester card (surfaceContainerLow, radius 12, padding 16): 下学期 label, semester name, 报到 M/d–M/d, FilledButton.tonal 查看下学期课表 (disabled when no local matching schedule; tap → switchSchedule or snackbar 没有下学期课表).
- Style slider ranges (SetCourseStylePage): 颜色不透明度 0.3–1.0 (14 div, default 0.85); 字体大小 8–20 (12 div, default 14); 显示网格线 switch (default on); 行高 48–120 (18 div, default 72); background opacity 0.05–0.8 (15 div, default 0.3).

### 4.9 Schedule config model (`models/schedule_config.dart`) — verbatim defaults

- Defaults: totalWeeks 20 (`kDefaultTotalWeeks`), morning 4 / afternoon 5 / evening 3 (sectionsPerDay = 12), courseDuration 45, breakDuration 10, autoSyncTime true, semesterName '', id 'default'.
- `semesterEndDate = start + totalWeeks*7 - 1 days`. `getCurrentWeek()`: today<start → 1 else floor(days/7)+1 (unclamped). `dateForCourseDay(week, day)`: supports Sunday-start semesters (Sunday belongs to week 1).
- **江安 preset** (4-5-3): morning 08:15–09:00, 09:10–09:55, 10:15–11:00, 11:10–11:55; afternoon 13:50–14:35, 14:45–15:30, 15:40–16:25, 16:45–17:30, 17:40–18:25; evening 19:20–20:05, 20:15–21:00, 21:10–21:55.
- **望江/华西 preset**: 08:00–08:45, 08:55–09:40, 10:00–10:45, 10:55–11:40; 14:00–14:45, 14:55–15:40, 15:50–16:35, 16:55–17:40, 17:50–18:35; 19:30–20:15, 20:25–21:10, 21:20–22:05.
- Campus detection: keywords 江安 / 望江 / 华西 (campus field first, then location substring); `dominantCampusOfCourses` counts per unique course name, strict majority only; presets applied only to 4-5-3 configs; `isPresetTimeSlots` detects untouched time tables.
- Generic fallback generator: morning from 08:00, afternoon from 14:00, evening from 19:00; each slot = courseDuration + breakDuration.

### 4.10 Course model (`models/course.dart`)

- Fields: id (default `microsecondsSinceEpoch_counter`), name, teacher, location, campus '', startWeek, endWeek, dayOfWeek (1=Mon…7=Sun), startSection, endSection, colorValue (ARGB int), weekType (every=0/odd=1/even=2).
- `isActiveInWeek`: in range AND parity check (odd type skips even weeks). `conflictsWith`: same dayOfWeek + section overlap + week-range overlap with parity-aware shared-week check. `duplicate(nameSuffix)` = copyWith new id.
- JSON keys: id, name, teacher, location, campus, startWeek, endWeek, dayOfWeek, startSection, endSection, colorValue, weekType (int).

---

## 5. Common Widget Patterns

### 5.1 Card / Tile hierarchy (`widgets/common/`)

- **StyledCard** — the base shell: bg `surfaceContainerLow` (overridable), radius `largeIncreased` (20), border dividerColor@0.10 (1px), shadow black@0.10 blur 4 offset(0,2), antiAlias clip, optional InkWell. Padding/margin opt-in.
- **CardWithTitle** (styled_card.dart) — StyledCard + padded(20,10,20,20) column: bold ×1.3-scaled title (+optional red `*` required mark) + icon row + child. Used by filter bars & dynamic forms.
- **InfoCard** — StyledCard + column of children with 1px dividers between (indent 56 to clear leading icons; 0 for full-width).
- **Tile family** (styled_tile.dart):
  - `BaseTile`: padding h20 v16 + InkWell radius 20.
  - `TileIcon`: 36×36 container, color@0.10, radius 12, icon 20.
  - `IconTile`: TileIcon + 14 gap + label bodyLarge + optional value + trailing + auto-chevron (chevron_right 20, onSurfaceVariant@0.4) when tappable.
  - `BadgedTile`: IconTile + 8×8 red dot before chevron (update badges).
  - `LinkTile`: IconTile + open_in_new 18 trailing.
  - `StackedTile`: label over value subtitle.
- **SectionTitle** — titleMedium primary, padding (12,0,10,8).
- **InfoRow** — fixed-width label (80) + value bodyMedium w500 + optional trailing; v4 padding.
- **IconInfoRow / StatItem / StatusChip** — detail-sheet row variants; StatItem = value titleMedium bold (error/highlight color) over label small; StatusChip = 4-radius chip h8 v2.
- **ThirdCenter** — `Align(alignment: Alignment(x, -1.3/3))` (visual center at upper third).
- **ButtonWithMaxWidth** — full-width ElevatedButton with trailing icon.

### 5.2 Loading / error / login gating

- `AutoLoginLoadingWidget` — spinner + 正在自动登录 (shown while `authProvider.isAutoLoggingIn`).
- `LoginRequiredWidget` — login icon 48 + 登录后可用 + ElevatedButton 前往登录 (pushes ScuLoginPage on ROOT navigator).
- `RetryableErrorWidget` — cloud_off 48 + message (max 4 lines) + FilledButton.tonal 重试; two ctors (enum / raw string).
- Standard page skeleton (all campus pages): `ListenableBuilder(merge([provider, auth]))` → !isLoggedIn ? (autoLoggingIn ? AutoLoginLoadingWidget : LoginRequiredWidget) : state machine (idle/loading-no-data → spinner; error-no-data → RetryableError; error-with-data → error banner above stale list; loaded → content, usually RefreshIndicator + list).
- Dialog helpers (`widgets/dialog/dialog.dart`): `showInfoDialog` (single confirm), `showYesNoDialog` (confirm/cancel — NOTE order: confirm first), `showLoadingDialog` (CancelableOperation, min 100ms), `showLoadingDialogWithErrorString` (morphs into error display).

### 5.3 AuthScopedIndexedStack (`widgets/common/auth_scoped_indexed_stack.dart`)

- Lazy per-id page cache; on auth boundary (isLoggedIn flip) bumps generation key (`auth-<gen>-<id>`) and clears cache — previous account's page State destroyed.
- Tab switch animation: fade (fastOutSlowIn curve) + slide (direction-aware: in from right/bottom when moving right, mirrored otherwise; axis horizontal for bottom bar, vertical for rail); duration + on/off from settings; `_previousIndex` kept until animation completes; auth change mid-animation snaps to end.

### 5.4 SwipePageView (`widgets/common/swipe_page_view.dart`) — 244 lines

- The app-wide horizontal pager (course weeks, grades/fitness/repair/academic tabs). PageView with `NeverScrollableScrollPhysics`; outer pan detector drives `PageController.jumpTo` for 1:1 finger tracking.
- Direction lock: after 8px movement, horizontal iff `dx > dy * 1.5` (vertical falls through to inner scrollables). Release: |velocity|>100 → flip; else |delta|>50 → flip; else snap back. Animate with `AppCurves.quick`, duration default 300ms.
- Optional two-way TabController sync (tap tab → animate; swipe → set tabController.index without animation; `_tapAnimTargetPage` prevents loops). `keepPagesAlive` wraps pages in AutomaticKeepAlive (forms/tab state).

### 5.5 BackgroundImageView (`widgets/common/background_image_view.dart`)

- Course-page background: resolves image size via ImageStream (shared cache), 300ms AnimatedOpacity fade-in; crop==null/isCover → `BoxFit.cover`; else `BackgroundCropParams.resolveLayout` positions a scaled image inside ClipRect. White overlay `color: Colors.white.withAlpha(opacity*255)` + `BlendMode.modulate` (fades the image toward background).

### 5.6 WebView pages (`widgets/webview/`)

- `WebViewNoticePage` — flutter_inappwebview wrapper: JS beautify script injected from asset, `AttachmentsChannel` / `DOMReady` / `DownloadAttachment` / `OpenImage` JS handlers, loading mask (skinnable off), error HTML template, back/forward AppBar controls, attachments FAB → `AttachmentsSheet` (download with optional captcha when `forceCaptchaForDownload`).
- Used by zysc, tuanwei/party notices; jwc notices render natively (scraped) with the same attachments sheet.
- `WebViewUnsupportedPage` for platforms without webview.

### 5.7 MouseBackHandler / PopupContext

- Desktop mouse button 4/5 → Navigator back/forward. `PopupContext` inherited widget marks widget trees inside `popupContent` dialogs so `popupOrNavigate` pushes instead of stacking dialogs.

---

## 6. Theme System

### 6.1 Shape tokens (`theme_shape.dart`) — verbatim

| Token | dp | Usage |
|---|---|---|
| `AppShapes.xs` | 4 | small badges, status chips |
| `AppShapes.small` | 8 | chips, course cards |
| `AppShapes.medium` | 12 | icon containers, mid elements |
| `AppShapes.large` | 16 | secondary cards, ListTile, inputs |
| `AppShapes.largeIncreased` | 20 | primary cards (MD3 Expressive) |
| `AppShapes.extraLarge` | 28 | dialogs, bottom sheets |
| `AppShapes.full` | 999 | pills/circles |

`AppCurves.quick = Curves.easeOutQuart` (also global `appCurve` in AppConfigProvider).

### 6.2 Theme build (`theme.dart`)

- `buildTheme({brightness, seedColor, useGoogleFonts, textScale, pageTransitionDuration})`:
  - `ColorScheme.fromSeed(seedColor, brightness)` — **seed-driven MD3**; no manual palette.
  - Page transitions per platform, all with equal forward/reverse duration (default 300ms, overridden by `cardSizeAnimationDuration`): Android `PredictiveBackPageTransitionsBuilder`, iOS `CupertinoPageTransitionsBuilder`, desktop `FadeForwardsPageTransitionsBuilder`.
  - `AppBarTheme`: toolbarHeight `48 × textScale`, centerTitle **false**, scrolledUnderElevation 0.
  - `NavigationBarThemeData`: height `64 × textScale`.
  - Component shapes: Card radius 20; Dialog + BottomSheet top radius 28; Chip + all button types `StadiumBorder`; ListTile radius 16.
  - Optional text theme: `GoogleFonts.notoSansScTextTheme`.
- Seed resolution: `themeColorMode == system` → `SystemTheme.accentColor.accent` (OS accent); `backgroundImage` → extracted dominant color (persisted into `themeColor`); `custom` → `themeColor` value.
- `themeMode: ThemeMode.system` always; dark theme = same builder with `Brightness.dark`.
- Font size accessibility: app-level clamp of textScaler to 1.0–2.0; toolbar/navbar heights scale with it.

### 6.3 Notable color usage conventions

- Disabled/greyed: `onSurfaceVariant.withValues(alpha: 0.4)`.
- Section headers / emphasis text: `colorScheme.primary`.
- Card surfaces: `surfaceContainerLow` (StyledCard), `surfaceContainerHighest` (grid header, dock preview).
- Course grid boundary lines: `primary.withAlpha(150)` 1.5px; normal: `outlineVariant` 0.5px.

---

## 7. iOS Widget Extension (`ios/CourseWidget/WidgetExtension.swift`, 1207 lines)

Existing SwiftUI/WidgetKit code to adapt. Key facts verbatim:

### 7.1 Data plumbing

- **App Group**: `group.io.github.thebrotherhoodofscu.bugaoshan`
- **DB path**: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:).appendingPathComponent("bugaoshan.db")` — the app must copy/write its SQLite DB there (Flutter side does this via MethodChannel `updateWidget`).
- Open read-only first, fall back to read-write.
- **Queries** (SQLite3 C API):
  - `SELECT value FROM metadata WHERE key = ?` with `'currentScheduleId'` (fallback `"default"`).
  - `SELECT config_json FROM schedules WHERE id = ?` → parse JSON (`semesterStartDate` "yyyy-MM-dd" local, `totalWeeks`, `timeSlots[{startTime{hour,minute},endTime{…}}]`); if id missing → `SELECT id, config_json FROM schedules LIMIT 1`.
  - `SELECT name, teacher, location, start_week, end_week, start_section, end_section, color_value, week_type FROM courses WHERE schedule_id = ? AND day_of_week = ?` (dayOfWeek: `(weekday + 5) % 7 + 1` = Mon1..Sun7), filtered in-memory by `isCourseActive` (week range + parity: weekType 0 every / 1 odd / 2 even), sorted by startSection.
  - Vacation: mirrors app logic — `isOnVacation` (today > semesterEnd(=start+totalWeeks*7-1) and < earliest next-schedule start); fallback `isOnBundledAcademicCalendarVacation` reads bundled `academic_calendar.json` (`semesters[{s,w}]`) when no schedule data.
- **Status computation**: per course vs `currentTimeMinutes`: `completed` (≥ end), `inProgress` (start ≤ now < end), `upcoming`; timeText `"HH:mm-HH:mm"` from time slots (fallback `第x节` / `第x-y节`).
- **Tomorrow fallback**: if no unfinished courses today AND `widget_show_tomorrow` (UserDefaults in app group) → show tomorrow's courses all `upcoming`, or "明天没课".
- **Appearance prefs** (UserDefaults suiteName = app group): `widget_show_tomorrow` (Bool), `widget_color_style` (0 colorful / 1 monochrome), `widget_density` (0 standard / 1 compact). App syncs via MethodChannel (`syncWidgetShowTomorrow`, `syncWidgetAppearance`).

### 7.2 Timeline strategy

- Single entry + `policy: .after(nextUpdate)`:
  - next course start/end boundary time (`computeNextTransitionMillis`, ≥60s away), else
  - **15 minutes** default, else
  - midnight next day when no courses, else
  - +1 hour when no data at all.
- Placeholder (gallery preview): two fake courses (高等数学/张教授/综A… in-progress 0xFF4CAF50; 大学物理/李教授 0xFF2196F3 upcoming). Empty entry distinguishes 放假中 (bundled calendar) vs 未同步课表 (weekText "").

### 7.3 Views & sizes

- Families: `.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular` (lock screen). Kind `"CourseWidget"`, StaticConfiguration, `containerBackground(Color(.systemBackground), for: .widget)` (system Clear/Tinted apply Liquid Glass).
- **DesktopWidgetView**: header row — large: app name headline + date/week subheadline; small/medium: date+week footnote. Course list: completed filtered out (kept only on systemLarge); max courses: small **2**, medium 2 (compact 3), large 6 (compact 7); footer "还有 N 门课" caption. Empty states: 放假中尽情享受 / 同步课表后显示 / 今天没课 / 明天没课 / 已上完今天的课.
- **CourseCard**: name (footnote compact / subheadline; bold when inProgress; orange when tomorrow+colorful), time·location line; 3px (compact) / 4px color bar overlay on leading edge (`widgetAccentable`); completed @0.45 opacity (fullColor) / 0.6. Course colors only in `.fullColor` rendering mode AND colorful style; else primary@0.72 (monochrome/tinted friendly). ARGB parse with invalid-color fallback (orange tomorrow / blue).
- **LockScreenRectangularView**: next pending course — book icon + name (headline, widgetAccentable) + "第x节 · 地点" caption; empty: sparkles + 没课/放假/未同步 + subtitle.
- Spacings: outer 8 (small/compact) else 12; course 5/8 (small) or 6/10; manual widgetPadding 0 (small) / 2 — iOS 17 system margins.
- Widget localization via `Localizable.xcstrings` keys `widget.*` (weekFormat, onVacation, tomorrow, noClassesToday, noClassesTomorrow, allClassesFinished, enjoyVacation, syncSchedule, moreClassesFormat, sectionSingleFormat, sectionRangeFormat, preview*, appName, configurationName/Description).

### 7.4 App-side widget service (`services/widget_update_service.dart`)

- MethodChannel-driven; debounced (normal) or immediate (`force`) `updateWidget` native call; re-run coalescing (`_needsRunAgain`); `pinWidget(size)` (small/medium/large) + `onWidgetPinned` stream (AddWidgetPage verify flow); battery optimization helpers (Android); appearance sync (iOS only).
- Trigger points: `HomePage` app resume, `CourseProvider.onCoursesChanged` (every course mutation), settings syncs.

---

## 8. Localization

- `lib/l10n/app_localizations_zh.dart` — **3064 lines, 915 getters** (+ parameterized methods). Largest key families: `ccyl*` (63), `repair*` (51), `train*` (35), `balance*` (31), `leave*` (26), `fitness*` (25), `dock*` (25), `course*` (24), `reset*` (23), `passpoint*` (22), `wizard*` (20), `campus*` (18), `export*` (17), `widget*` (16), `import*` (16).
- Locales: `zh` + `en`; language override stored as BCP-47 tag; null = follow system.
- App title key: `bugaoshan` → 不高山上.

## 9. Misc porting notes

- HTTP timeout constant `kHttpTimeout = 15s`; default UA: Chrome 131 Edge 131 desktop Windows string (`utils/constants.dart`).
- Method/Event channels: `bugaoshan/update`, `bugaoshan/dynamic_icon`, `bugaoshan/download_cancel`.
- Links: repo https://github.com/The-Brotherhood-of-SCU/Bugaoshan, site https://bugaoshan.scubro.dev/, manual https://bugaoshan-docs.scubro.dev/manual/.
- Assets: `academic_calendar.json` (bundled calendar, semesters {s,w,…}), `region_data.json` (service-hall region tree), `eula.md`, `scu.webp` + `scu_header_{light,dark}.webp`, `icon.png`/`icon_old.png`, `js/` beautify scripts, `webview_error.html`.
- Holiday util (`utils/holiday_utils.dart`): `tyme` package — legal holidays (State Council data since 2001), solar terms (寿星天文算法), fixed fallback {1/1 元旦, 5/1 劳动节, 10/1 国庆节}; types ordinary/festival/holiday/solarTerm; per-year total-days cache.
- `AuthCoordinator.warmUpAll()` eagerly establishes subsystem SSO sessions (wfw/zhhq/payapp/newservice/ccyl) after SCU login.
