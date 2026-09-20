import SwiftUI

/// 课表主页面（对应 course_page.dart）：
/// 顶栏（周导航/课表切换/导入导出/添加）+ 水平翻页周网格 + 假期页 + 空态。
struct CoursePage: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var config: AppConfig
    @StateObject private var provider: CourseProvider

    @State private var pageIndex = 0
    @State private var showVacationPage = false
    @State private var selectedCourse: Course?
    @State private var showEditPage = false
    @State private var editingCourse: Course?
    @State private var showImportSheet = false
    @State private var showCalendarExport = false
    @State private var showManagement = false

    init() {
        // CourseProvider 依赖 environment，占位注入，onAppear 内重建
        _provider = StateObject(wrappedValue: CourseProvider(database: DatabaseService()))
    }

    var body: some View {
        Group {
            if provider.hasSchedule, let scheduleConfig = provider.config {
                courseContent(scheduleConfig)
            } else {
                NoScheduleView(
                    onImport: { showImportSheet = true },
                    onManage: { showManagement = true },
                    onCreate: {
                        Task {
                            await provider.createSchedule(name: "默认课表")
                        }
                    }
                )
            }
        }
        .task {
            provider.attach(database: environment.database)
            await provider.reload()
            resetToToday()
        }
        .onChange(of: provider.config?.id) { _ in
            resetToToday()
        }
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(
                course: course,
                config: provider.config ?? ScheduleConfig(),
                onClose: { selectedCourse = nil },
                onEdit: { courseToEdit in
                    selectedCourse = nil
                    editingCourse = courseToEdit
                    showEditPage = true
                },
                onDelete: { courseId in
                    selectedCourse = nil
                    Task { await provider.deleteCourse(id: courseId) }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showEditPage) {
            NavigationStack {
                CourseEditPage(
                    provider: provider,
                    original: editingCourse,
                    prefillDayOfWeek: nil,
                    prefillSection: nil
                )
            }
        }
        .sheet(isPresented: $showCalendarExport) {
            if let sheet = exportSheet {
                sheet.environmentObject(environment)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportScheduleSheet(provider: provider)
        }
        .sheet(isPresented: $showManagement) {
            NavigationStack {
                ScheduleManagementPage(provider: provider)
            }
        }
    }

    // MARK: - 主体

    @ViewBuilder
    private func courseContent(_ scheduleConfig: ScheduleConfig) -> some View {
        let pageCount = showVacationPage ? scheduleConfig.totalWeeks + 1 : scheduleConfig.totalWeeks
        let headerWeek = min(pageIndex + 1, scheduleConfig.totalWeeks)
        // 行高自适应：12 节整体放进一屏，免去竖向滚动
        //（顶部玻璃栏 + 表头 + 底部 dock + 安全区合计约 300pt）
        let rowHeight = min(
            config.courseRowHeight,
            (UIScreen.main.bounds.height - 300) / CGFloat(scheduleConfig.sectionsPerDay)
        )
        let gridHeight = CGFloat(scheduleConfig.sectionsPerDay) * rowHeight
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                CourseGridHeader(
                    config: scheduleConfig,
                    week: headerWeek,
                    showWeekend: config.showWeekend,
                    todayWeek: provider.currentWeek
                )
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    // 节次列固定在分页视图外：横向翻周时不随页滑动
                    CourseGridGutter(config: scheduleConfig, rowHeight: rowHeight)
                    TabView(selection: $pageIndex) {
                        ForEach(1...scheduleConfig.totalWeeks, id: \.self) { week in
                            CourseGridDayColumns(
                                courses: provider.courses,
                                config: scheduleConfig,
                                week: week,
                                showWeekend: config.showWeekend,
                                rowHeight: rowHeight,
                                onTapCourse: { course in
                                    selectedCourse = course
                                }
                            )
                            .tag(week - 1)
                        }
                        if showVacationPage {
                            VacationView(config: scheduleConfig)
                                .tag(scheduleConfig.totalWeeks)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: gridHeight)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 54)

            // 顶栏悬浮玻璃
            CourseTopBar(
                config: scheduleConfig,
                visibleWeek: min(pageIndex + 1, scheduleConfig.totalWeeks),
                isViewingVacation: showVacationPage && pageIndex >= scheduleConfig.totalWeeks,
                canGoPrevious: pageIndex > 0,
                canGoNext: pageIndex < pageCount - 1,
                schedules: provider.schedules,
                currentScheduleId: provider.currentScheduleId,
                onGoToday: { resetToToday() },
                onMove: { delta in
                    movePage(delta, total: pageCount)
                },
                onSwitchSchedule: { id in
                    Task { await provider.switchSchedule(id: id) }
                },
                onManage: { showManagement = true },
                onImport: { showImportSheet = true },
                onExport: { exportSchedule() },
                onAddCourse: {
                    editingCourse = nil
                    showEditPage = true
                }
            )
            .glassEffect(.regular, in: .rect)
        }
    }

    // MARK: - 翻周

    private func resetToToday() {
        guard let scheduleConfig = provider.config else { return }
        withAnimation(config.enablePageTransitionAnimation ? .easeOut(duration: 0.25) : nil) {
            pageIndex = min(max(provider.currentWeek - 1, 0), scheduleConfig.totalWeeks - 1)
        }
    }

    private func movePage(_ delta: Int, total: Int) {
        let target = min(max(pageIndex + delta, 0), total - 1)
        withAnimation(config.enablePageTransitionAnimation ? .easeOut(duration: 0.25) : nil) {
            pageIndex = target
        }
    }

    private func exportSchedule() {
        showCalendarExport = true
    }

    private var exportSheet: CalendarExportSheet? {
        guard let config = provider.config else { return nil }
        return CalendarExportSheet(
            title: "导出课表",
            icsContent: IcsBuilder.courseScheduleIcs(config: config, courses: provider.courses),
            icsFileName: IcsBuilder.calendarFileName(semesterName: config.semesterName),
            events: CalendarEventBuilder.courseEvents(config: config, courses: provider.courses),
            includeCopy: true,
            onCopy: {
                if let json = provider.exportCurrentSchedule() {
                    UIPasteboard.general.string = json
                }
            }
        )
    }
}

// MARK: - 顶栏

struct CourseTopBar: View {
    let config: ScheduleConfig
    let visibleWeek: Int
    let isViewingVacation: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let schedules: [ScheduleConfig]
    let currentScheduleId: String

    let onGoToday: () -> Void
    let onMove: (Int) -> Void
    let onSwitchSchedule: (String) -> Void
    let onManage: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void
    let onAddCourse: () -> Void

    private var actualWeek: Int { config.getCurrentWeek() }
    private var notStarted: Bool {
        Date().startOfDay < config.semesterStartDate.startOfDay
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onGoToday) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(todayLabel)
                        .font(.subheadline.bold())
                    HStack(spacing: 4) {
                        Button {
                            onMove(-1)
                        } label: {
                            Image(systemName: "chevron.left").font(.footnote)
                        }
                        .disabled(!canGoPrevious)
                        Text(weekLabel)
                            .font(.caption.weight(.medium))
                            .frame(minWidth: 44)
                        Button {
                            onMove(1)
                        } label: {
                            Image(systemName: "chevron.right").font(.footnote)
                        }
                        .disabled(!canGoNext)
                        weekBadge
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 课表切换 + 管理（原导航栏工具栏入口，单栈架构下迁入玻璃顶栏）
            Menu {
                ForEach(schedules, id: \.id) { schedule in
                    Button {
                        onSwitchSchedule(schedule.id)
                    } label: {
                        if schedule.id == currentScheduleId {
                            Label(schedule.semesterName.isEmpty ? "默认课表" : schedule.semesterName, systemImage: "checkmark")
                        } else {
                            Text(schedule.semesterName.isEmpty ? "默认课表" : schedule.semesterName)
                        }
                    }
                }
                Divider()
                Button {
                    onManage()
                } label: {
                    Label("管理课表", systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .disabled(schedules.isEmpty)

            Button(action: onImport) {
                Image(systemName: "square.and.arrow.down")
            }
            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
            }
            Button(action: onAddCourse) {
                Image(systemName: "plus.circle")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var todayLabel: String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year!)/\(comps.month!)/\(comps.day!)"
    }

    private var weekLabel: String {
        if isViewingVacation { return "放假中" }
        return "第 \(visibleWeek) 周"
    }

    @ViewBuilder
    private var weekBadge: some View {
        if notStarted {
            badgeText("未开学", .gray)
        } else if isViewingVacation {
            badgeText("放假中", .teal)
        } else if visibleWeek == actualWeek {
            badgeText("本周", Color.accentColor)
        } else {
            badgeText("当前第 \(actualWeek) 周", .secondary)
        }
    }

    private func badgeText(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - 空态

struct NoScheduleView: View {
    let onImport: () -> Void
    let onManage: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "calendar")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
            }
            Text("暂无课表")
                .font(.title3.weight(.semibold))
            Text("从教务系统导入，或从其他设备分享的文件导入")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button {
                    onImport()
                } label: {
                    Label("导入课表", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    onManage()
                } label: {
                    Label("课表管理", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    onCreate()
                } label: {
                    Label("新建课表", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 假期页

struct VacationView: View {
    let config: ScheduleConfig

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "beach.umbrella.fill")
                .font(.system(size: 56))
                .foregroundStyle(.teal)
            Text("放假中")
                .font(.title.bold())
            Text(vacationText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var vacationText: String {
        let today = Date().startOfDay
        let end = config.semesterEndDate.startOfDay
        if today > end {
            let days = today.days(since: end)
            return "本学期已结束（\(days) 天前）"
        }
        let days = end.days(since: today)
        return "距离放假还有 \(days) 天"
    }
}
