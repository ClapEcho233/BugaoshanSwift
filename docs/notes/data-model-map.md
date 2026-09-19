# Bugaoshan 数据层移植参考（Flutter → Swift/SwiftUI）

> 单一事实来源：本文档逐字段、逐条 SQL、逐条解析规则地记录 Flutter 版
> （`/Users/clapecho233/Files/Work/Bugaoshan`）的数据层，供 iOS 原生重构对照。
> 所有常量、SQL、字段名均为原文引用，未做任何"顺手修正"。

对应源码（均为绝对路径）：
- 模型：`lib/models/*.dart`
- 数据库：`lib/services/database_service.dart`
- ICS：`lib/services/ics_service.dart` + `lib/utils/calendar_event_*.dart` + `lib/utils/calendar_location_mapper.dart`
- 周次解析：`lib/utils/week_parser.dart`、`lib/utils/class_week_parser.dart`
- 北京时间：`lib/utils/beijing_time.dart`
- 节假日：`lib/utils/holiday_utils.dart`
- 导出：`lib/utils/export_schedule_utils.dart`、`lib/utils/calendar_export_utils.dart`、`lib/providers/export_schedule_provider.dart`
- 教务导入：`lib/pages/course/import/jwxt_parser.dart`、`lib/pages/course/import/import_schedule_page.dart`
- 原生桥：`ios/Runner/AppDelegate.swift`、`lib/services/widget_update_service.dart`
- 资产：`assets/`

---

## 目录

1. [数据模型](#1-数据模型)
2. [数据库 Schema](#2-数据库-schema)
3. [周次/节次解析与当前周计算](#3-周次节次解析与当前周计算)
4. [ICS 生成](#4-ics-生成)
5. [jwxt_parser 教务导入](#5-jwxt_parser-教务导入)
6. [北京时间处理](#6-北京时间处理)
7. [分享文件导出格式](#7-分享文件导出格式)
8. [资产目录](#8-资产目录)
9. [AppDelegate.swift 原生桥](#9-appdelegateswift-原生桥)
10. [测试覆盖清单](#10-测试覆盖清单)

---

## 1. 数据模型

### 1.1 Course（`lib/models/course.dart`）

课表中的一条"课程占用"：某门课在某天某节次段、某周次区间的一次排课。
同一门课多个周段/多节次会展开成多条 Course 记录。

| 字段 | 类型 | JSON 键 | DB 列 | 默认值（fromJson 缺省时） | 语义 |
|---|---|---|---|---|---|
| id | String | `id` | `id TEXT PRIMARY KEY` | `''` | 唯一 ID。`generateId()` = `'{microsecondsSinceEpoch}_{++counter}'`（进程内静态计数器 `_idCounter`） |
| name | String | `name` | `name TEXT` | `''` | 课程名（教务导入时为 `'{courseName} ({coureSequenceNumber})'`） |
| teacher | String | `teacher` | `teacher TEXT` | `''` | 教师名 |
| location | String | `location` | `location TEXT` | `''` | 上课地点（楼+房间拼接） |
| campus | String | `campus` | `campus TEXT NOT NULL DEFAULT ''` | `''` | 校区（教务处 `campusName`，如"江安校区"）；空时从 location 推断。v2 迁移新增列 |
| startWeek | int | `startWeek` | `start_week INTEGER` | 1 | 起始教学周 |
| endWeek | int | `endWeek` | `end_week INTEGER` | `kDefaultTotalWeeks` (=20) | 结束教学周 |
| dayOfWeek | int | `dayOfWeek` | `day_of_week INTEGER` | 1 | 1=周一 … 7=周日 |
| startSection | int | `startSection` | `start_section INTEGER` | 1 | 起始节次（1-based，对应 timeSlots 索引 `startSection-1`） |
| endSection | int | `endSection` | `end_section INTEGER` | 1 | 结束节次 |
| colorValue | int | `colorValue` | `color_value INTEGER` | `0xFF2196F3` | 颜色，ARGB 位编码（Flutter `Color.toARGB32()`；对应 Swift 可用 `UIColor` 的 RGBA 打包，注意 Flutter 是 ARGB 顺序） |
| weekType | WeekType | `weekType`（**int 枚举序号**） | `week_type INTEGER` | `WeekType.every` (0) | 周类型 |

- `enum WeekType { every, odd, even }` — 序号 0/1/2，JSON 与 DB 均存 int 序号。
- `const int kDefaultTotalWeeks = 20;`（教务系统标准 20 周）。
- toJson 全字段输出（见上表 JSON 键）；fromJson 全部宽松缺省。
- `color` getter/setter：`Color(colorValue)` / `colorValue = c.toARGB32()`。
- `isActiveInWeek(week)`：区间内 +（odd 需周为奇 / even 需周为偶）。
- `conflictsWith(other, {excludeId})`：同 dayOfWeek + 节次区间相交 + 周区间相交 +
  `_hasSharedWeek`（odd/even 互斥；every+every 恒真；否则取交集内第一个符合奇偶的周）。
- `duplicate({nameSuffix})`：copyWith 新 id + 名称追加后缀（语义是"新课程"，落库必须走 INSERT）。

`DateTimeExtension`（同文件，周界计算核心）：

```dart
DateTime toMonday() => subtract(Duration(days: weekday - 1));
// 教务系统以周日为每周第一天
DateTime toSunday() => subtract(Duration(days: weekday % 7));
```

### 1.2 ScheduleConfig / TimeSlot（`lib/models/schedule_config.dart`）

#### TimeSlot

| 字段 | 类型 | JSON 键 |
|---|---|---|
| startTime | TimeOfDay | `startTime: {hour, minute}` |
| endTime | TimeOfDay | `endTime: {hour, minute}` |

JSON 形如 `{"startTime":{"hour":8,"minute":15},"endTime":{"hour":9,"minute":0}}`。

#### ScheduleConfig

| 字段 | 类型 | JSON 键 | 默认值 | 语义 |
|---|---|---|---|---|
| id | String | `id` | `'default'` | 课表 ID（导入时用 `DateTime.now().millisecondsSinceEpoch.toString()`） |
| semesterName | String | `semesterName` | `''` | 学期名，如"2025-2026学年秋季学期" |
| semesterStartDate | DateTime | `semesterStartDate`（`yyyy-MM-dd` 手工 padLeft 格式化） | `DateTime.now()` | 学期第一教学周起点（**允许是周日**，见 §3.4） |
| totalWeeks | int | `totalWeeks` | 20 | 总教学周数 |
| morningSections | int | `morningSections` | 4 | 上午节数 |
| afternoonSections | int | `afternoonSections` | 5 | 下午节数 |
| eveningSections | int | `eveningSections` | 3 | 晚上节数 |
| courseDuration | int | `courseDuration` | 45 | 单节课分钟数（默认时间表推导用） |
| breakDuration | int | `breakDuration` | 10 | 课间分钟数 |
| autoSyncTime | bool | `autoSyncTime` | true | 是否自动按校历同步时间 |
| timeSlots | List\<TimeSlot\> | `timeSlots` | `_defaultTimeSlots(4,5,3,45,10)` | 每节课起止时刻表（长度应 = sectionsPerDay） |

派生：`sectionsPerDay = morning+afternoon+evening`；
`semesterEndDate = 起点日期 + (totalWeeks*7 - 1) 天`（最后一教学周最后一天）。

fromJson 兼容逻辑（移植必须保留）：
1. `totalWeeks` 缺失但有 `semesterEndDate` → `(endDate-startDate).inDays/7` 向上取整。
2. 无 `morningSections` 但有旧字段 `sectionsPerDay`（int total）→ morning = min(4,total)，afternoon = total>=9?5:(total>4?total-4:0)，evening = total>9?total-9:0。
3. `timeSlots` 缺失 → 按节数/时长生成默认表；若 4-5-3 直接返回江安预设的拷贝。

#### 校区时间表预设（SCU 两个预设，各 12 节，4-5-3）

`jiangAnTimeSlots`（四川大学江安校区）：

| 节 | 开始 | 结束 | | 节 | 开始 | 结束 | | 节 | 开始 | 结束 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 08:15 | 09:00 | | 5 | 13:50 | 14:35 | | 9  | 17:40 | 18:25 |
| 2 | 09:10 | 09:55 | | 6 | 14:45 | 15:30 | | 10 | 19:20 | 20:05 |
| 3 | 10:15 | 11:00 | | 7 | 15:40 | 16:25 | | 11 | 20:15 | 21:00 |
| 4 | 11:10 | 11:55 | | 8 | 16:45 | 17:30 | | 12 | 21:10 | 21:55 |

`wangJiangHuaXiTimeSlots`（望江/华西校区）：

| 节 | 开始 | 结束 | | 节 | 开始 | 结束 | | 节 | 开始 | 结束 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 08:00 | 08:45 | | 5 | 14:00 | 14:45 | | 9  | 17:50 | 18:35 |
| 2 | 08:55 | 09:40 | | 6 | 14:55 | 15:40 | | 10 | 19:30 | 20:15 |
| 3 | 10:00 | 10:45 | | 7 | 15:50 | 16:35 | | 11 | 20:25 | 21:10 |
| 4 | 10:55 | 11:40 | | 8 | 16:55 | 17:40 | | 12 | 21:20 | 22:05 |

校区相关静态方法：
- `timeSlotsForCampusName(String)`：名字含"江安"→江安表；含"望江"或"华西"→望江/华西表；否则 null。
- `campusKeywords = ['江安', '望江', '华西']`（顺序即优先级）。
- `campusKeywordOfCourse(Course)`：先匹配 `course.campus`，未命中再匹配 `course.location`。
- `dominantCampusOfCourses(List<Course>)`：**按 course.name 去重**后统计校区关键词计数
  （同一门课展开成多条不重复计数，同名多条取第一个命中）；严格最多者胜，并列/为空返回 null。
- `applyCampusTimeSlotsForCourses(config, courses)`：仅当 config 为 4-5-3 且存在主导校区时
  把 `config.timeSlots` 替换为该校区预设（拷贝新列表）。导入流程用它自动套时间表。
- `isPresetTimeSlots(slots)`：与任一预设完全一致（逐项 hour/minute 相等）→ 用户未自定义过。

`_defaultTimeSlots(morning, afternoon, evening, courseDuration, breakDuration)`：
非 4-5-3 时的通用推导 — 上午从 08:00 起、下午从 14:00 起、晚上从 19:00 起，
每节 +courseDuration，节间 +breakDuration，分钟进位到小时。

`getCurrentWeek()`（当前教学周）与 `dateForCourseDay(week, dayOfWeek)` 见 §3.4。

### 1.3 AcademicCalendar（`lib/models/academic_calendar.dart` + `.g.dart`）

三层结构：`AcademicCalendarData { semesters }` → `AcademicCalendarSemester` → `AcademicCalendarEvent`。
手写 `@JsonSerializable`，日期转换器把 DateTime 与 `yyyy-MM-dd`（月/日 padLeft 2 位）互转。

#### AcademicCalendarEvent

| 字段 | 类型 | JSON 键 | 默认值 | 语义 |
|---|---|---|---|---|
| date | DateTime | `date`（yyyy-MM-dd，必填） | — | 起始日 |
| endDate | DateTime? | `endDate`（yyyy-MM-dd） | null | 结束日（null=单日） |
| label | String | `label` | `''` | 展示名，如"国庆节假期" |
| tag | String | `tag` | `'event'` | 分类：`'holiday'` / `'exam'` / `'start'` / `'course'` / `'event'` |

方法：`isActive(target)`（date..endDate 闭区间含 target）、`isFinished(target)`
（target > endDate??date）、`getDaysDifference(target)`（date - target 的整天数）。

#### AcademicCalendarSemester

| 字段 | 类型 | JSON 键 | 默认值 |
|---|---|---|---|
| name | String | `name` | —（必填） |
| startDate | DateTime | `startDate`（yyyy-MM-dd） | —（必填） |
| totalWeeks | int | `totalWeeks` | 20 |
| events | List\<AcademicCalendarEvent\> | `events` | `[]` |

方法：
- `getCurrentWeek(target)`：`(days/7).floor()+1`；学期前或超过 totalWeeks 返回 null。
- `isDateInSemester`：`start .. start+totalWeeks*7-1`。
- `endDate` getter：`startDate + totalWeeks*7 - 1` 天。
- `registrationEvent`：第一个 label 含"报到"的事件。
- `findMatchingScheduleId(schedules)` 匹配优先级：
  1. 学期名完全相等；
  2. 学年键 `(\d{4})-(\d{4})` + 季节字 `[春秋夏冬]` 均包含；
  3. 起点 年+月 相等；
  4. 仅学年键包含。
  （学期名无学年模式时只走 3。）

#### AcademicCalendarData

`semesters` 列表（默认 `[]`），`fromJsonString(String)` 便捷构造，
`findNextSemester(date)`：第一个 `startDate > date` 的学期（假定已按 startDate 排序）。
仅 fromJson（`createToJson: false`）。

### 1.4 BalanceRecord（`lib/models/balance_record.dart`）

电费/水量余额采样记录（行映射模型，非 JSON）。

| 字段 | 类型 | DB 列 | 语义 |
|---|---|---|---|
| id | int? | `id`（自增主键，仅在非 null 时写回） | 行 ID |
| roomKey | String | `room_key` | 房间标识（区域/楼栋/房间编码） |
| balanceType | int | `balance_type` | 余额类型枚举（电量/水量等，见 balance_query 服务） |
| timestamp | DateTime | `timestamp`（**UTC 毫秒**） | 采样时刻；fromRow 用 `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)` |
| balance | double | `balance` | 余额值（safeDouble） |
| price | double | `price` | 单价（safeDouble） |

### 1.5 BackgroundCropParams（`lib/models/background_crop.dart`）

背景图裁剪参数，归一化存储、与分辨率无关。JSON：`{"focusX":d,"focusY":d,"zoom":d}`
（`encode()` = jsonEncode(toJson())；`tryDecode(raw)` 解析失败/字段缺失返回 null，越界 clamp）。

- 常量：`defaultFocus = 0.5`，`minZoom = 1.0`，`maxZoom = 5.0`；`cover` = 全默认值（等价 BoxFit.cover）。
- focusX/focusY ∈ [0,1]：显示在容器中心的图片归一化坐标；zoom 相对 cover 基准的倍数。
- 渲染数学（课程页与裁剪编辑器共用）：
  - `_baseCoverScale = max(containerW/imageW, containerH/imageH)`；
  - `scale = baseCoverScale * zoom`；`scaledW = imageW*scale`；
  - `left = (containerW - scaledW)/2 + (0.5 - clampedFocus.dx) * scaledW`（top 同理）；
  - `clampFocus`：平移余量 `maxD = (scaled - container)/2`，把 `(0.5-focus)*scaled` clamp 到 ±maxD。

### 1.6 CampusItemConfig（`lib/models/campus_item_config.dart`）

校园页 dock 项配置（纯 UI 注册表，无序列化）。字段：`id / icon / selectedIcon /
dockLabel(l10n) / dockFullLabel(l10n) / desc(l10n) / page`。
Dock ID 常量（`lib/utils/constants.dart`）：
`course, campus, profile, grades, ccyl, plan_completion, train_program, classroom,
network_device, passpoint, balance_query, academic_calendar, fitness_test, notice,
downloaded_attachments, class_schedule_inquiry, course_curriculum, exam_plan, zysc, leave, repair`。
`defaultVisibleDockIds = [course, campus, profile]`。分节：
academic（grades/ccyl/plan_completion/fitness_test/exam_plan）、
utilities（train_program/class_schedule_inquiry/course_curriculum/classroom/
network_device/passpoint/balance_query/repair/academic_calendar/zysc/leave）、
notice（notice/downloads）。

### 1.7 Passpoint 模型（`lib/models/passpoint.dart`）

校园网无感认证（newservice `site/passpoint/*`）：
- `PasspointDevice`：`userMac`、`macExpireTime`（**日期字符串 YYYY-MM-DD**，空/`0`/非法 → null 表示"最长 6 年"）、
  `defaultServiceName`、`isOnline`（true | '1' | 'true'）。
- `PasspointUserInfo`：`userId/userName/userGroupName/accountState(int,==1 在线)/mobile/email`。
- `PasspointExit.all`：`校园网('')`、`中国电信`、`中国移动`、`中国联通`。

### 1.8 Repair 模型（`lib/models/repair.dart`）

智慧后勤在线报修（字段均经真实抓包确认，全部 `.toString() ?? ''` 宽松解析）：
- `RepairAddress`：`id/areaName/addressDetail/phone/areaId/isCommon("1"=默认)/userId(createUser 兜底)`；`displayName = 'area / detail（默认）'`。
- `RepairProject`：两级树（大类如水/木/泥 → 叶子项目），`label/value/children`；提交用叶子 value（如 `101`）。
- `RepairAcceptDept`：`deptId/deptName/payName` → 直接作 publish 请求体 `acceptDeptId/acceptDeptName/payName`。
- `RepairAreaNode`：`id/name/parentName/children`，`fullName = 'parent/…/name'`。
- `RepairTicket`（"我的动态"`activeTemplateData/list` 行）：`id(=activeId)/activeId/areaName/projectName/
  serviceUnit/content/status(后端直接给中文：已关闭/待完工/待评价/已撤回)/createTime(int)/activeTime('YYYY-MM-DD HH:mm:ss')`。
  `content` 是 JSON 字符串，兼容 Map / JSON 串 / 最多 5 层转义嵌套 / 值内裸控制字符
  （issue #273：后端不转义用户输入的换行导致 JSON 非法 — `_escapeRawControlChars` 只转义字符串值内部的
  `\n \r \t` 及 <0x20 控制字符后重试解码）。字段取自 `故障地点/维修项目/服务单位/故障描述`；
  展示优先"故障描述"，缺失则 `' · '` 拼接其余字段，绝不展示原始 JSON。
- `RepairTicketDetail`（`repairInfo/get`）：`id/serialNumber(报修编号如 202609030009)/projectName/content/
  areaName/address/acceptDeptName/payName/bookTimeString/ifOnduty(true|'1'|'true')/
  status(数字字符串，'4' 且未评价→可评价)/ifCommont('0'=否)/ifComplete('0'=否)/
  logs(RepairLogItem{statusName,content,createTime})/finishedInfo(RepairFinishedInfo{repairId,completeTime,totalAmount})`。
- `RepairEvaluateProject`：`id/name/weight(如 50/25/25)`，评价提交 `star` 1-5。

### 1.9 SchemeScore 模型（`lib/models/scheme_score.dart`）

成绩单（教务 zhjw）：
- `SchemeScoreItem`：`courseName / englishCourseName? / courseAttributeName(必修/选修/任选) /
  credit(String) / cj(原始成绩 String) / courseScore(double) / gradePointScore(double) /
  gradeName(A/B+/F…) / academicYearCode / termName(秋/春) /
  passed = gradeName!='F' && 非空 / hasEffectiveScore = courseScore>=0 && gradePointScore>=0`。
  **注意**：2026-09 起 schemeScores 接口把百分制成绩挪进复合主键：`json['id']['courseScore']`，
  顶层 `json['courseScore']` 仅为 allPassingScores 回退兼容。
- `SchemeScoreSummary`（`lnList` 每个方案）：`zxf(总学分)/yxxf(已修)/tgms(通过门数)/wtgms(未通过)/zms(总门数)/
  cjlx(方案名)/items(cjList)`。辅助方案关键字 `_auxiliaryPlanKeywords = ['微专业','辅修','第二专业']`
  （defaultScheme 取第一个非辅助方案，否则首个）。统计口径（分母仅计 passed && hasEffectiveScore && credit>0）：
  `gpa`、`requiredGpa`（必修）、`earnedCredits`、`weightedAvgScore`、`requiredWeightedAvgScore`、
  `requiredCredits/electiveCredits/optionalCredits`。
- `PassingScoreGroup` / `PassingScoreResult`：及格成绩按学期分组；排序 — 学年倒序，同学年春在前秋在后
  （label 前 9 字符是学年，`label.contains('春')`）。

### 1.10 其余小模型

- `ReleaseInfo`（`release_info.dart`）：`tagName?/downloadUrl?/filename?/checksumSha256?/isPrerelease(false)/body?`（GitHub 更新源）。
- `VersionInfo`（`version_info.dart`）：`app/environment/flag/build`。
- `WidgetSize`（`widget_size.dart`）：`enum {small, medium, large}`；`toPinArgument()` → `'small'|'medium'|'large'`。
- `WidgetColorStyle`（`widget_appearance.dart`）：`enum {colorful, monochrome}`。
- `WidgetDensity`（`widget_appearance.dart`）：`enum {standard, compact}`。
  （外观两项同步到 iOS 时传 **枚举序号 int**，见 §9。）
- `ExamInfo`（`lib/pages/campus/exam_plan/models/exam_info.dart`，考表 HTML 解析结果）：
  `courseName/week/date('YYYY-MM-DD')/weekday/timeRange('HH:mm-HH:mm')/location/seatNumber/ticketNumber/tip`；
  `isPast` 按 date+结束时间判断。toJson 全字段同名。

---

## 2. 数据库 Schema

文件：`lib/services/database_service.dart`。sqflite，DB 文件名 **`bugaoshan.db`**，`version: 2`。

### 2.1 存储位置与迁移（iOS）

- App Group：**`group.io.github.thebrotherhoodofscu.bugaoshan`**（iOS 用
  `flutter_app_group_directory` 取共享目录，让 Widget Extension 可读 DB；失败回退
  `getApplicationSupportDirectory()`）。macOS 用应用 Support 目录。
- 旧位置迁移：iOS 上若 `<AppSupport>/bugaoshan.db` 存在且 App Group 下不存在 → 复制过去。

### 2.2 CREATE TABLE（原文）

```sql
CREATE TABLE metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)

CREATE TABLE schedules (
  id TEXT PRIMARY KEY,
  config_json TEXT NOT NULL
)

CREATE TABLE courses (
  id TEXT PRIMARY KEY,
  schedule_id TEXT NOT NULL,
  name TEXT,
  teacher TEXT,
  location TEXT,
  campus TEXT NOT NULL DEFAULT '',
  start_week INTEGER,
  end_week INTEGER,
  day_of_week INTEGER,
  start_section INTEGER,
  end_section INTEGER,
  color_value INTEGER,
  week_type INTEGER,
  FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE CASCADE
)

CREATE TABLE IF NOT EXISTS balance_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_key TEXT NOT NULL,
  balance_type INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  balance REAL NOT NULL,
  price REAL NOT NULL
)

CREATE INDEX IF NOT EXISTS idx_balance_records_lookup
ON balance_records(room_key, balance_type, timestamp)
```

要点：
- `schedules` 整行是 JSON blob（`config_json` = ScheduleConfig.toJson()）。
- `courses.week_type` 存 WeekType 枚举序号；`color_value` 存 ARGB int。
- `balance_records` 不在 v1 onCreate 的老库上通过 `init()` 末尾的 `_ensureBalanceRecordsTable()`（CREATE IF NOT EXISTS）补建。
- `metadata` 目前只有一个键：`currentScheduleId`。

### 2.3 迁移历史

- **v1 → v2**（onUpgrade，oldVersion < 2）：
  `ALTER TABLE courses ADD COLUMN campus TEXT NOT NULL DEFAULT ''`（教务处 campusName）。

### 2.4 查询/写入方法（SQL 语义）

内存缓存：`_currentScheduleId`、`_schedulesCache`（全表）、`_coursesCache`（仅当前课表）。
init 时全量加载；**不再自动创建默认课表**，新安装 `_currentScheduleId=''` 直到用户切换。

| 方法 | SQL / 行为 |
|---|---|
| `init()` | openDatabase(version:2, onCreate 建全部表, onUpgrade 加 campus 列)；读 `metadata WHERE key='currentScheduleId'`；加载两缓存 |
| `switchSchedule(id)` | 校验 id 在缓存中，否则早返回；`INSERT OR REPLACE INTO metadata(key,value)` 写 currentScheduleId；重载课程缓存 |
| `getAllSchedules()` / `getScheduleConfig()` | 缓存只读；getScheduleConfig 找不到当前 id 时回退第一个 |
| `saveScheduleConfig(cfg)` | 存在则 `UPDATE schedules SET config_json=? WHERE id=?`，否则 `INSERT` |
| `addSchedule(cfg)` | `INSERT INTO schedules(id, config_json)` |
| `deleteSchedule(id)` | 事务：`DELETE FROM courses WHERE schedule_id=?` → `DELETE FROM schedules WHERE id=?`；若删的是当前课表：有剩余 → switchSchedule(第一个)；无剩余 → currentScheduleId 置 '' 并写 metadata |
| `getCourses({scheduleId?})` | 同步缓存读；非当前课表返回 []（跨课表用 getCoursesAsync） |
| `addCourse(c)` | 当前课表为空时早返回；`INSERT INTO courses(...13 列)`；重载缓存 |
| `replaceScheduleCourses(id, list)` | 事务：`DELETE FROM courses WHERE schedule_id=?` 后逐条 INSERT（"更新课表"场景） |
| `updateCourse(c)` | `UPDATE courses SET ... WHERE id=?` |
| `deleteCourse(id)` | `DELETE FROM courses WHERE id=?` |
| `getCoursesAsync({scheduleId?})` | `SELECT * FROM courses WHERE schedule_id=?` |
| `hasConflict(course, {excludeId})` | 纯内存：缓存任一 `conflictsWith` |
| `clearAllCourseData()` | 事务清空 courses/schedules/metadata 三表 + 清缓存 |
| `insertBalanceRecord(r)` | `INSERT INTO balance_records(...)`（返回 rowid） |
| `getBalanceRecords({roomKey, balanceType, since?, until?})` | `WHERE room_key=? AND balance_type=? [AND timestamp>=?] [AND timestamp<=?] ORDER BY timestamp ASC` |
| `deleteBalanceRecordsBefore(threshold)` | `DELETE FROM balance_records WHERE timestamp < ?` |
| `deleteBalanceRecordsByRoom(roomKey)` | `DELETE FROM balance_records WHERE room_key=?` |

行↔对象映射（snake_case ↔ camelCase；`week_type` int → WeekType 序号，越界回退 every）。

表关系：`courses.schedule_id` → `schedules.id`（逻辑外键，手动级联删除；sqflite 未开 FK pragma）。
`metadata.currentScheduleId` → `schedules.id`。

---

## 3. 周次/节次解析与当前周计算

### 3.1 week_parser.dart — 教务周次描述串（zcsm）

`parseWeeks(String zcsm) → (int startWeek, int endWeek, WeekType weekType)`

语法（教务处"周次说明"字段）：

```
"1-10周"     → (1, 10, every)
"1-10,12周"  → (1, 12, every)   // 12 是独立周，取并集的 min/max
"1-16(单)"   → (1, 16, odd)
"1-16(双)"   → (1, 16, even)
"第16周"     → (16, 16, every)
""           → (1, 20, every)
```

算法：去掉所有"周"字；含"单"→odd，含"双"→even；再用
`text.replaceAll(RegExp(r'[^\d,\-]'), '')` 只留数字/逗号/连字符，按 `,` 分段，
每段按 `-` 分为范围或单值，取全局 min/max；无数字 → `(1, 20, weekType)`；缺端 → `(min??1, max??20, …)`。

### 3.2 class_week_parser.dart — 周次位串（classWeek）

教务 JSON 的 `classWeek` 是**位串**：`'0'/'1'` 字符序列，第 i 位（0-based）为 `'1'`
表示第 `i+1` 周有课（`index+1` 即周号）。

`parseClassWeekSegments(String classWeek) → List<ClassWeekSegment>`，
`typedef ClassWeekSegment = ({int startWeek, int endWeek, WeekType weekType})`：

1. 收集全部活动周 `activeWeeks`（升序）。
2. 空串 → `[]`（该 timeAndPlace 不生成课程）。
3. **完整无缺口交替序列**（所有相邻差为 2 且 >1 个周）→ 合并为单个
   `odd`（首周为奇）或 `even`（首周为偶）区间。
4. 否则按连续段拆分为多个 `every` 区间（差 1 连续；不凭空增加周次）。

例：`"111111101111111"` → 段 [1-7 every] 和 [9-15 every]（第 8 周无课）。

### 3.3 节次（section）编码

- 1-based。`startSection` = `classSessions`（教务字段，起始节）；
  `continuingSession` = 连续节数；`endSection = startSection + continuingSession - 1`。
- 时间：`start = timeSlots[startSection-1].startTime`，`end = timeSlots[endSection-1].endTime`。

### 3.4 当前周计算与周日语义（关键）

`ScheduleConfig.getCurrentWeek()`：

```dart
final today = DateTime(now.y, now.m, now.d);
final start = DateTime(start.y, start.m, start.d);
if (today.isBefore(start)) return 1;
final days = today.difference(start).inDays;
final week = (days / 7).floor() + 1;   // 无 totalWeeks 上限钳制
```

即教学周 = 以 `semesterStartDate` 为第 1 周第 1 天，每 7 天进一周。
（`AcademicCalendarSemester.getCurrentWeek` 同式，但超 totalWeeks 返回 null。）

**周日语义**：教务系统以周日为每周第一天。学期起点可能是周日——该周日属于第 1 教学周，
其次日才是第 1 周周一。因此：

```dart
DateTime dateForCourseDay(int week, int dayOfWeek) {
  final mondayOffset = (DateTime.monday - start.weekday) % 7;
  final daysFromMonday = dayOfWeek == DateTime.sunday ? -1 : dayOfWeek - DateTime.monday;
  return start.add(Duration(days: (week - 1) * 7 + mondayOffset + daysFromMonday));
}
```

- 若起点是周一：mondayOffset=0，dayOfWeek 1..6 → +0..+5，周日 → -1（回退到本周周一的前一天=本周周日，即"第 N 周"的周日实际在周一前 1 天——教务把周日挂在同一教学周内）。
- 若起点是周日：mondayOffset = (1-7)%7 = 1，周一=+1 … 周六=+6，周日=+0。
- 对应 `DateTimeExtension.toSunday()`：`subtract(Duration(days: weekday % 7))`（Dart weekday 周日=7 → 7%7=0）。

### 3.5 holiday_utils.dart — 法定节假日（tyme 库）

基于 `package:tyme`（`SolarDay.getLegalHoliday()`；国务院官方安排，2001-12-29 起；节气为寿星天文算法）：
- `getHolidayName(date)`：法定假日名（如"国庆节"）；**调休上班日返回 null**；tyme 无数据/异常 → 固定日期兜底
  `_kFixedHolidays = {1:{1:'元旦'}, 5:{1:'劳动节'}, 10:{1:'国庆节'}}`。
- `getHolidayTotalDays(name, year, {near})`：总放假日数（near 时 ±30 天窗口双向遍历；带 `{year:{name:days}}` 缓存）。
- `getFestivalName`：公历+农历节日（跳过已归入法定假的春节、清明）。
- `getSolarTermName`：节气（仅当天，`termDay.dayIndex == 0`）。
- `getSpecialDay(date)`：优先级 假 > 节日 > 节气 > 普通日；`enum SpecialDayType { ordinary, festival, holiday, solarTerm }`。
- Swift 侧等价物建议：lunar-calendar/China holiday 数据源或内置每年国务院安排表。

---

## 4. ICS 生成

文件：`lib/services/ics_service.dart`（课程/考试）+ `lib/services/api/academic_calendar_service.dart`（校历）。

### 4.1 VCALENDAR 头（原文，两处一致）

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Bugaoshan//{productName}//EN        // 课程: 'Course Schedule'，考试: 'Exam Schedule'，校历: 'Academic Calendar'
CALSCALE:GREGORIAN
METHOD:PUBLISH
X-WR-TIMEZONE:Asia/Shanghai
BEGIN:VTIMEZONE
TZID:Asia/Shanghai
BEGIN:STANDARD
TZOFFSETFROM:+0800
TZOFFSETTO:+0800
TZNAME:CST
DTSTART:19700101T000000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=3
END:STANDARD
BEGIN:DAYLIGHT
TZOFFSETFROM:+0800
TZOFFSETTO:+0800
TZNAME:CST
DTSTART:19700101T000000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
END:DAYLIGHT
END:VTIMEZONE
```

（伪 VTIMEZONE：固定 +0800，标准/夏令各挂一条不生效的 RRULE。）

### 4.2 课程 VEVENT

对每门课的每个活跃周（startWeek..endWeek 内满足奇偶）生成一条：

```
BEGIN:VEVENT
DTSTART;TZID=Asia/Shanghai:{yyyyMMdd}T{HHmm}00
DTEND;TZID=Asia/Shanghai:{yyyyMMdd}T{HHmm}00
SUMMARY:{course.name}                       // 转义
LOCATION:{解析后的地点标题}                   // CalendarLocationMapper.resolve(location, campusName:).title
DESCRIPTION:{teacherLabel}: {course.teacher}  // teacherLabel 为 l10n（如"教师"）
UID:{courseId}_{week}@bugaoshan
END:VEVENT
```

- 日期 = `config.dateForCourseDay(week, dayOfWeek)`（§3.4）；起止时刻取 timeSlots 首末节。
- **UID 方案**（`calendar_event_identity.dart`，稳定性支撑跨版本去重与 iOS 本地 UID map）：
  - 课程：`'{courseId}_{week}@bugaoshan'`（保持 legacy 形状）。
  - 考试：`'exam-' + sha1('exam|' + normalizeName(name)).hex[0..24) + '@bugaoshan'`
    （仅按规范化课程名去重；`normalizeName` 去掉 `（已结束）/(已结束)` 标记、空白折叠）。
- GEO / X-APPLE-STRUCTURED-LOCATION 分支存在但当前 `CalendarLocationMapper` 不产出坐标，
  实际不输出（保留待坐标数据源）。

### 4.3 考试 VEVENT

- 日期时间解析：`date` 需匹配 `^(\d{4})-(\d{2})-(\d{2})$`，`timeRange` 需匹配 `^(\d{2}):(\d{2})-(\d{2}):(\d{2})$`，任一不匹配跳过该考试。
- `SUMMARY`：课程名（规范化后）不以"考试"结尾则追加"考试"。
- `DESCRIPTION`：`[exam.week, '座位号: {seatNumber}', '准考证号: {ticketNumber}'(非空才加), '提示: {tip}'(≠'无'才加)].join('\n')`。
- `LOCATION`：`CalendarLocationMapper.resolve(exam.location).title`。

### 4.4 校历 VEVENT（AcademicCalendarService.genExportPayload）

- 全天式伪装：start = 事件日 08:00，end = (endDate??date) 日 18:00。
- `LOCATION` = `resolve('四川大学').title`；`DESCRIPTION` = `'四川大学官方校历日程\n类型: {tag}'`。
- `UID = 'acad-{semester.name 空格→_}-{label 空格→_}-{date.millisecondsSinceEpoch}@bugaoshan'`。
- 文件名 `'SCU_Calendar_{学期名sanitize}.ics'`。

### 4.5 文本转义与文件名

```dart
String _escapeIcsText(String text) => text
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;');
```

`safeFileName(value, {allowHyphen=false})`：非 `[A-Za-z0-9_一-鿿.]`（allowHyphen 再加 `-`）
全部替换为 `_`；空结果回退 `'calendar'`。课程表文件名 = `{semesterName sanitize}.ics`。
（注意：**未做 RFC 5545 的 75 字节折叠**，直接 writeln。）

### 4.6 CalendarLocationMapper（地点解析，`calendar_location_mapper.dart`）

输入原始地点（空白折叠）+ 可选 campusName：
1. 校区识别：campusName 含 江安/望江/华西 关键字，否则从 location 找。
2. 建筑匹配：静态表 `_buildingLocations`（三校区全部教学楼/楼栋，含 canonical 名 + matchPatterns 别名），
   **最长 pattern 优先**（pattern 长度 + 字母结尾 +1 加权，如"一教A"胜过"一教"），限定在已识别校区内。
   命中 → title = `'{校区全称}{canonicalBuildingName} · {房间号} [({redirectNote})]'`。
3. 未命中建筑 → 校区级（buildingKeywords 兜底识别）→ `'校区全称 · 原location'`。
4. 无校区 → 原样返回。空 location + 有校区 → 仅校区全称。

房间号提取 `_extractRoomName`：剥离校区全称/关键字 + 一大串楼名（含"一教..十教/各德堂/综"等，
按长度降序），`楼名+字母+数字`（如"综C407"）保留字母数字部分为 "C407"，去"座/栋"，规范 "A 101"→"A101"，
单字母视为无房号。

平台事件 JSON（`CalendarEventPayload.toPlatformJson()`，走 MethodChannel 给 EventKit）：

```json
{
  "title": ..., "location": ..., "notes": ..., "uid": ..., "timeZone": "Asia/Shanghai",
  "start": {"year":..,"month":..,"day":..,"hour":..,"minute":..},
  "end":   {"year":..,"month":..,"day":..,"hour":..,"minute":..},
  "structuredLocation": {"title":.., "latitude":..?, "longitude":..?, "radius":..?}   // 可选
}
```

`CalendarExportPayload = {fileName, icsContent, events: [platformJson…]}`。

---

## 5. jwxt_parser 教务导入

文件：`lib/pages/course/import/jwxt_parser.dart`；流程编排在 `import_schedule_page.dart`。

### 5.1 输入 JSON 形状（教务处导出 / zhjw 在线接口 `fetchJwxtSchedule(planCode)`）

```json
{
  "xkxx": [
    {
      "<任意key>": {                      // 外层 map 的 key 未使用，遍历 value
        "courseName": "高等数学",
        "id": { "coureSequenceNumber": "01" },   // 复合主键对象
        "attendClassTeacher": "张三",
        "timeAndPlaceList": [
          {
            "classDay": 3,                // int，1..7（周一=1）
            "classSessions": 1,           // 起始节次
            "continuingSession": 2,       // 连续节数
            "teachingBuildingName": "一教", // 楼名候选链（见下）
            "jxlm": ..., "building": ...,
            "classroomName": "A101",       // 房间候选链
            "jasm": ..., "classroom": ...,
            "customPlace": ..., "teachingPlace": ..., "place": ..., "skdd": ...,  // 地点兜底链
            "campusName": "江安校区",
            "classWeek": "1111111011111110"  // 位串，见 §3.2
          }
        ]
      }
    }
  ]
}
```

### 5.2 转换规则（parseJwxtData）

- 课程名：`'$courseName ($coureSequenceNumber)'`（序号缺省 `''`，即 "name ()"）。
- 教师：`attendClassTeacher ?? ''`。
- 地点：`teachingBuildingName ?? jxlm ?? building ?? ''` + `classroomName ?? jasm ?? classroom ?? ''`
  拼接；两者皆空 → 依次取 `customPlace / teachingPlace / place / skdd`。
- `endSection = classSessions + continuingSession - 1`。
- `classWeek` 位串 → `parseClassWeekSegments` → 每段一条 Course（同 color）。
- 颜色：`Colors.primaries`（Material 调色板）按 **courseMap（每门课）** 轮转
  `colorIdx++`（仅在该课产出 ≥1 段时递增），`toARGB32()` 存储。
- ScheduleConfig 初始：`semesterStartDate = DateTime.now().toMonday()`，
  其余默认（id 'default' 后被调用方覆盖为毫秒时间戳字符串；名称由用户输入/学期 label）。
- 返回 `hasWeekend = courses.any(dayOfWeek ∈ {6,7})` → 调用方设置 `showWeekend`。

### 5.3 校验（validateImportedSchedule）

抛 `FormatException`：
- config：`totalWeeks < 1 || timeSlots.isEmpty` → 'Invalid schedule config'。
- 每门课：`startWeek<1 || endWeek<startWeek || endWeek>totalWeeks || dayOfWeek∉[1,7] ||
  startSection<1 || endSection<startSection || endSection>timeSlots.length` →
  `'Invalid course range: {course.name}'`。

### 5.4 导入流程（import_schedule_page.dart，三种模式 `ImportMode { share, jwxt, online }`）

- share：剪贴板/粘贴 JSON `{config: ScheduleConfig.toJson, courses: [Course.toJson]}`。
- jwxt：粘贴教务原始 JSON，先弹窗问课表名（默认 l10n "导入的课表(M月D日)"）。
- online：登录态 → `fetchSemesters()` → 选学期（单/全部）→ 逐个 `fetchJwxtSchedule`。
- 公共步骤：`config.id = 毫秒时间戳字符串` → validate →
  `ScheduleConfig.applyCampusTimeSlotsForCourses(config, courses)`（自动校区时间表）→
  名称冲突处理 → addSchedule + 逐条 addCourse。
- **名称冲突检测**：`isScheduleNameTaken(name)` / `findScheduleIdByName(name)`。
  选择：cancel / 加后缀（l10n 后缀或 `名称 ({ms%1000})`）/ **更新**（`replaceScheduleCourses` 整体替换；
  share 模式更新前全部课程 `copyWith(id: Course.generateId())` 防主键冲突）。
  online 全部导入时可批量选 addSuffix/update。
- 更新已有课表后 `_applyCampusTimeSlotsToExisting`：仅当原时间表仍是预置
  （`isPresetTimeSlots`）才按新课程主导校区覆盖。
- online 导入后：把教务标记"（当前）"的学期（`cleanSemesterLabel` 剥离 `（当前）`/`(当前)`）
  设为当前课表；再按校历静默修正每个导入课表的 `semesterStartDate/totalWeeks`
  （`AcademicCalendarService.findMatchingSemester(name)`）。

---

## 6. 北京时间处理

文件：`lib/utils/beijing_time.dart`。SCU 用户统一按北京时区（UTC+8）解释余额趋势时间，
**不依赖设备本地时区**；DB 存 UTC 毫秒，展示/聚合/日界判定固定 +8h（境外用户也看到北京日历日）。

```dart
const Duration kBeijingUtcOffset = Duration(hours: 8);

// 格式化：先 toUtc() 再 +8h，再按 pattern（intl DateFormat）
String formatBeijing(DateTime utcTime, String pattern);

// 北京日 bucket key（UTC 标记的当日 00:00，仅作 key）
DateTime beijingDayBucket(DateTime utcTime);

// utcTime 所在北京日 00:00 对应的 UTC 即时（"今日已采样否"查询下界）
DateTime beijingStartOfDayUtc(DateTime utcTime);
DateTime beijingStartOfTodayUtc();

// 北京日历日 y/m/d [+ h/m/s/ms] → UTC 即时（DatePicker 日期按北京日解释）
DateTime beijingDateToUtc(int y, int m, int d, {int hour=0, ...});
```

Swift 移植：`TimeZone(secondsFromGMT: 8*3600)` 固定时区；存 Date（UTC）、日界换算用它，
不要用 `TimeZone.current`。

---

## 7. 分享文件导出格式（跨 App 迁移）

`ExportScheduleProvider.copyToClipBoard()`（`lib/providers/export_schedule_provider.dart`），
复制到剪贴板的 JSON（也被对端 App 的"从分享导入"读取，见 §5.4 share 模式）：

```json
{
  "config": { /* ScheduleConfig.toJson() 全字段，见 §1.2 */ },
  "courses": [ /* Course.toJson() 全字段，见 §1.1 */ ]
}
```

即两层：`config`（含 `timeSlots` 嵌套数组）+ `courses` 数组。
对端导入容错：`Course.fromJson` 全字段宽松缺省（id 空则重新 generateId，重复 id 也会在
"更新"路径整批重新生成）；`ScheduleConfig.fromJson` 兼容旧 `semesterEndDate` / `sectionsPerDay` 字段。

导出动作三选一（`CalendarExportAction { copy, ics, addToCalendar }`）：
- copy → 上述 JSON jsonEncode 进剪贴板；
- ics → `FilePicker.saveFile` 保存 `{semesterName}.ics`（payload.icsContent）；
- addToCalendar → iOS/macOS 走 EventKit（`importIcsToCalendar` method channel，带 events 列表 + calendarIdentifier）；
  Android 走 ICS 文件路径 intent；其余平台用 OpenFilex 打开缓存 ICS
  （临时目录 `{tmp}/{fileName}`）。

---

## 8. 资产目录（`assets/`）

| 文件 | 用途 / 结构 |
|---|---|
| `academic_calendar.json` | 内置校历（7141 B）。**压缩格式**：顶层 `eventTypes`（key → `{l: 标签, t: tag}`，13 种：register/reexam/first/moon/national/newyear/qingming/duanwu/graduation/exam/practice/winter/summer）+ `semesters: [{n: 名称, s: 起始日, w: 周数, e: {类型key: "日期" 或 ["起","止"]}}]`。`AcademicCalendarService.expandCalendarJson` 展开为模型格式 `{name,startDate,totalWeeks,events:[{label,tag,date,endDate?}]}`（已展开则原样）。当前覆盖 2021-2022-1 至 2027-2028-1 共 12 学期（部分 19 周）。远程更新源：GitHub raw（主）+ gh-proxy 镜像，成功写 SharedPreferences `cached_academic_calendar_json`（空 semesters 不写缓存防污染） |
| `region_data.json` | 中国三级行政区划树 `[{code,name,children:[{code,name,children:[{code,name}]}]}]`（省→市→区县） |
| `js/dom_ready.js` | WebView 双 rAF 后回调 `flutter_inappwebview.callHandler('DOMReady')` |
| `js/jwc_notice_beautify.js` (464 行) | 教务处通知页注入 CSS/JS：隐藏站点 chrome，列表/正文限宽 640px 居中，系统字体 |
| `js/party_notice_beautify.js` (382 行) | 党委通知页同类美化 |
| `js/tuanwei_notice_beautify.js` (436 行) | 团委通知页同类美化 |
| `js/volunteer_sichuan.js` (3 行) | 隐藏志愿四川页面弹窗 `.u-drawer` |
| `scripts/update.sh` / `update.bat` | 桌面端自更新脚本：sleep 3 → 覆盖目录 → 重启 EXE → 自删 |
| `webview_error.html` | WebView 加载失败页 |
| `eula.md` | 最终用户许可协议文本 |
| `icon.png` / `icon.svg` / `icon-foreground.png` / `icon_old.png` | 应用图标（flutter_launcher_icons：Android 自适应前景 #FFFFFF 背景） |
| `brotherhood-of-scu.png` | 组织 logo（关于页） |
| `scu.webp` / `scu_header_dark.webp` / `scu_header_light.webp` | 登录页校徽/明暗页头 |

pubspec 资产声明：`assets/`、`assets/js/`、`assets/scripts/` 整目录 + `CHANGELOG.md`。

---

## 9. AppDelegate.swift 原生桥

文件：`ios/Runner/AppDelegate.swift`。MethodChannel **`bugaoshan/update`**
（= `kUpdateMethodChannel`，Dart 侧 `WidgetUpdateService`/`CalendarImportUtils` 共用）。
App Group：`group.io.github.thebrotherhoodofscu.bugaoshan`。

### 9.1 MethodChannel 方法表

| 方法 | 参数 | 行为 |
|---|---|---|
| `listWritableCalendars` | — | 请求**完整**日历权限（iOS17+ `requestFullAccessToEvents`，旧系统 `requestAccess(to:.event)`）→ `eventStore.calendars(for:.event).filter(allowsContentModifications)` 映射为 `[{id: calendarIdentifier, title, sourceTitle, isDefault}]` |
| `importIcsToCalendar` | `{events: [[String:Any]], calendarIdentifier: String?}` | EventKit 逐事件写入（下详） |
| `updateWidget` | — | `WidgetCenter.shared.reloadAllTimelines()` |
| `syncWidgetShowTomorrow` | `{value: Bool}` | App Group UserDefaults 写 `widget_show_tomorrow`（Bool）+ reloadAllTimelines |
| `syncWidgetAppearance` | `{colorStyle: Int, density: Int}`（**枚举序号**） | 写 `widget_color_style` / `widget_density`（Int）+ reloadAllTimelines |

App Group 共享键（Widget Extension 读取）：`widget_show_tomorrow`、`widget_color_style`、`widget_density`。
（另有共享 DB：App Group 目录下的 `bugaoshan.db`，见 §2.1。）

### 9.2 EventKit 导入与 UID 去重映射

1. 权限：带 calendarIdentifier（要选择器）→ 完整权限；否则 iOS17+ **write-only**
   （`requestWriteOnlyAccessToEvents`），旧系统 `requestAccess(to:.event)`。
2. 目标本：指定 id（须 `allowsContentModifications`，否则 `NO_WRITABLE_CALENDAR`）或 `defaultCalendarForNewEvents`。
3. **去重索引**（`existingEventIndex`）：对目标日历按事件全集（payload 最小 start 日 0 点 ～ 最大 end 日次日 0 点）
   建 `[key: EKEvent]`，key 两种：
   - `uid:{uid}`（来自 event.url 的 `bugaoshan://calendar-event/{percentEncodedUid}` scheme 解析——历史遗留）；
   - `content|{title}|{Int(start.timeIntervalSince1970)}|{Int(end.timeIntervalSince1970)}`（内容指纹）。
4. **匹配顺序**（`matchingExistingEvent`）：
   a. **app 本地 UID map**（`UserDefaults.standard` 键 **`bugaoshan.calendarEventIdentifiers`**，
   `[uid: eventIdentifier]` 字典）→ 直接定位 event（calendar 不匹配则弃用并 forget）；EventKit 没有可写 UID 字段，
   这是 app 私有映射，保证重复导入是**更新**而非复制。
   b. 上面索引的 uid key / content key。
5. 命中已有事件 → `copyEventFields`（title/location/notes/startDate/endDate/timeZone/calendar/structuredLocation，`url = nil`）；
   否则新建（`makeEvent`：title/location/notes/日期组件+timeZone(默认 Asia/Shanghai)/structuredLocation(标题+可选 geo/radius)）。
6. 全部 `save(span:.thisEvent, commit:false)` 后一次 `commit()`，成功后
   `rememberEventIdentifiers` 把 uid→eventIdentifier 写回 UserDefaults。

Dart 侧 `WidgetUpdateService`（`lib/services/widget_update_service.dart`）其余要点：
debounce 500ms 合并、in-flight 防重入 + needsRunAgain、原生回调 `onWidgetPinned {size}` 转广播流；
Android 专属：`pinWidget`（请求 pin）、`getWidgetIds`、`openAppSettings`、电池优化两件套。
iOS/macOS 不支持 pin，返回 false。

---

## 10. 测试覆盖清单

`test/` 下共 91 个文件。按文件名一行一个（— 表示无文档注释/组名，按文件名理解）：

| 测试文件 | 覆盖内容 |
|---|---|
| academic_calendar_cache_test.dart | AcademicCalendarService 本地缓存优先策略与注入 client 生命周期 |
| academic_calendar_page_test.dart | 校历页面 widget 测试 — |
| academic_calendar_test.dart | AcademicCalendar 模型（getCurrentWeek/isDateInSemester/匹配等） |
| add_widget_picker_test.dart | 添加小组件选择器 — |
| app_config_widget_appearance_test.dart | AppConfig 中 widget 外观设置 — |
| auth_logger_test.dart | AuthLogRedactor 日志脱敏 |
| auth_scoped_indexed_stack_test.dart | 登录态作用域 IndexedStack — |
| background_crop_test.dart | 裁剪参数持久化（AppConfigProvider）+ BackgroundCropParams 数学 |
| background_image_view_test.dart | 背景图视图（真实 PNG 字节渲染） — |
| balance_query_provider_test.dart | 余额查询 provider — |
| balance_trend_calculator_test.dart | BalanceTrendCalculator 趋势计算 |
| balance_trend_chart_card_test.dart | 余额趋势图卡 Y 轴刻度 |
| balance_trend_stats_card_test.dart | 余额趋势统计卡"记录时间范围"行 |
| beijing_time_test.dart | beijingDayBucket 等北京时间工具 |
| calendar_event_utils_test.dart | 日历事件工具（payload/UID） |
| calendar_location_mapper_test.dart | CalendarLocationMapper.resolve 校区识别/楼栋/房间号 |
| campus_page_search_test.dart | 校园页搜索 — |
| campus_time_slots_test.dart | dominantCampusOfCourses 等校区时间表逻辑 |
| ccyl_api_retry_test.dart | 团委 API 重试 — |
| ccyl_auth_generation_test.dart | 团委认证代际 — |
| ccyl_auth_principal_test.dart | 团委认证主体 — |
| class_schedule_inquiry_detail_test.dart | 行课明细查询页 — |
| class_week_parser_test.dart | classWeek 位串解析（§3.2 全部规则） |
| classroom_model_test.dart | ClassroomQueryResult.periodStatusMap 教室占用状态 |
| cookie_client_test.dart | CookieClient.followRedirects 敏感请求头 |
| course_copy_mode_test.dart | 编辑页"复制课程"以新建副本模式保存 |
| course_curriculum_api_test.dart | 课程大纲 API（URL 路由 MockClient） |
| course_curriculum_provider_test.dart | 课程大纲 provider — |
| course_display_settings_test.dart | showCourseWeeks 等课程显示设置 |
| course_duplicate_test.dart | Course.duplicate 语义（内存库，副本必须新增而非 UPDATE） |
| course_page_controller_test.dart | 课程页 controller 初始化（外部输入注入） |
| course_page_top_bar_test.dart | 课程页顶栏 — |
| course_provider_test.dart | CourseProvider — |
| download_manager_test.dart | 下载管理器 — |
| download_path_index_test.dart | 已下载附件路径索引 — |
| exam_plan_page_test.dart | 考表页 — |
| exam_plan_test.dart | 考表 ICS 导出 |
| fitness_api_service_test.dart | 体测 API — |
| fitness_test_provider_test.dart | 体测数据 provider — |
| forgot_password_service_test.dart | 忘记密码 fetchCaptcha |
| grades_provider_test.dart | 成绩 provider — |
| grades_tabs_test.dart | 成绩页 tab — |
| grid_logic_test.dart | 课程格 track 分配（网格布局冲突） |
| ics_service_test.dart | 课程日历导出（VEVENT 生成） |
| json_utils_test.dart | safeDouble 等宽松取值 |
| jwxt_parser_test.dart | jwxt_parser（§5 全部转换规则） |
| looks_like_login_page_test.dart | looksLikeLoginPage 不误判业务页（issue #282） |
| network_device_provider_test.dart | 网络设备 provider — |
| passpoint_provider_test.dart | 无感认证 provider — |
| payapp_session_expiry_test.dart | 缴费平台会话过期 — |
| plan_completion_page_test.dart | 培养方案完成度页 — |
| plan_completion_provider_test.dart | 培养方案完成度 provider — |
| repair_ticket_model_test.dart | RepairTicket.fromDynamicJson content 多层转义/裸控制字符解析 |
| scheme_score_test.dart | SchemeScoreItem.fromJson courseScore 在 id 复合键中的取值 |
| scu_auth_test.dart | extractTokenErrorMessage |
| scu_reset_password_policy_test.dart | 重置密码客户端预校验 |
| service_api_service_test.dart | 后勤服务 fetchFormSchema |
| service_applications_provider_test.dart | 服务大厅应用 provider — |
| service_capture_calibration_test.dart | 用真实抓包端到端校准表单解析器 |
| service_form_controller_test.dart | buildFormData 复现 350（离校请假）已验证提交体 |
| service_plugin_models_test.dart | resolveServiceFieldType 字段类型解析 |
| set_app_icon_page_test.dart | 动态图标页 — |
| share_utils_test.dart | share_plus 垫片（Windows 路径等） — |
| swipe_page_view_test.dart | 逐帧拖动模拟 — |
| test_page_test.dart | GitHub release 下载 URL 格式（fetchLatestVersionFromGithub） |
| text_overflow_test.dart | 大文字缩放+窄宽度+长文本溢出防护回归 |
| theme_page_transitions_test.dart | 主题页转场 — |
| train_program_provider_test.dart | 培养方案 provider — |
| update_asset_selector_test.dart | 更新包按平台/arch 选择（无 androidArch 参数的 Android） |
| user_info_provider_test.dart | 用户信息 provider — |
| webview_notice_handlers_test.dart | mergeDownloadHeaders 等通知 WebView handler |
| wfw_auth_test.dart | 微服务认证 — |
| widget_test.dart | Course 周可见性（默认 widget 测试） |
| widget_update_service_test.dart | WidgetUpdateService debounce/重入 — |
| zhhq_api_service_test.dart | 智慧后勤 token 错误 4010-4017 映射 |
| zhhq_crypto_test.dart | 智慧后勤加密 — |
| zhhq_repair_provider_test.dart | 报修 provider — |
| zhjw_api_service_test.dart | 综合教务 API（URL 路由 MockClient） — |
| zhjw_query_providers_test.dart | 教务查询 provider — |

移植时优先对齐行为的高价值测试（可直接翻成 Swift XCTest）：
`class_week_parser_test`、`week 相关（grid_logic/widget_test/course_display_settings）`、
`ics_service_test`、`calendar_location_mapper_test`、`calendar_event_utils_test`、
`beijing_time_test`、`jwxt_parser_test`、`campus_time_slots_test`、`academic_calendar_test`、
`course_duplicate_test`、`scheme_score_test`、`repair_ticket_model_test`、`background_crop_test`。

---

## 附：移植速查（关键不变量）

1. `WeekType` 序号 0/1/2 = every/odd/even，JSON 与 DB 一致；odd=单周(奇数周)、even=双周(偶数周)。
2. `dayOfWeek` 1..7 周一..周日；`section` 1-based 对应 timeSlots 下标 -1。
3. 颜色 = ARGB int（Flutter `toARGB32`）；Swift 侧注意 UIColor 是 RGBA，需自行定义打包格式或转
   `(a<<24)|(r<<16)|(g<<8)|b` 以兼容存量数据与分享 JSON。
4. 教学周 = `(days since semesterStartDate) ~/ 7 + 1`；起点可以是周日，`dateForCourseDay`
   的周日偏移逻辑必须逐行照抄（§3.4），否则周日课全部错位一周。
5. classWeek 位串第 i 个字符（0-based）='1' ⇔ 第 i+1 周有课。
6. ICS UID：课程 `{courseId}_{week}@bugaoshan`；考试 `exam-{sha1[0:24]}@bugaoshan`；
   iOS EventKit 去重依赖 UserDefaults `bugaoshan.calendarEventIdentifiers` 的 uid→eventIdentifier 映射 + content 指纹。
7. 分享格式只有两层 `{config, courses}`；导入必须容忍空/重复 id、缺失 campus、旧字段
   `semesterEndDate`/`sectionsPerDay`。
8. App Group `group.io.github.thebrotherhoodofscu.bugaoshan`；DB 名 `bugaoshan.db`（version 2）；
   widget 偏好键 `widget_show_tomorrow` / `widget_color_style` / `widget_density`（枚举序号 int）。
9. 余额 timestamp 一律 UTC 毫秒；日界按固定 UTC+8。
10. 校历资产是压缩格式（`eventTypes`+`n/s/w/e`），模型是展开格式，`expandCalendarJson` 负责互转
    （两种格式都要能读——远程缓存可能是任一版本）。
