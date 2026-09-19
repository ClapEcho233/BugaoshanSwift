import SwiftUI

/// 班级课表查询页（对应 class_schedule_inquiry_page.dart）：
/// 五级筛选（学期/年级/院系/专业/班级）→ 分页班级列表 → 详情周网格。
struct ClassScheduleInquiryPage: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var appConfig: AppConfig

    @State private var semesters: [CurriculumSemesterOption] = []
    @State private var grades: [String] = []
    @State private var departments: [DepartmentOption] = []
    @State private var subjects: [SubjectOption] = []
    @State private var classOptions: [ClassOption] = []
    @State private var classes: [ClassInfo] = []
    @State private var totalCount = 0
    @State private var pageNum = 1

    @State private var selectedSemester = ""
    @State private var selectedGrade = ""
    @State private var selectedDepartment = ""
    @State private var selectedSubject = ""
    @State private var selectedClass = ""

    @State private var indexLoading = false
    @State private var indexLoaded = false
    @State private var needsLogin = false
    @State private var indexError: String?
    @State private var searchLoading = false
    @State private var loadingMore = false
    @State private var searchError: String?

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    private var hasMore: Bool { classes.count < totalCount }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if indexLoading && !indexLoaded {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let indexError, !indexLoaded {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(indexError)
                } actions: {
                    Button("重试") { Task { await loadIndex(force: true) } }
                }
            } else {
                list
            }
        }
        .navigationTitle("班级课表")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !indexLoaded {
                await loadIndex(force: false)
            }
        }
    }

    private var list: some View {
        List {
            Section("筛选") {
                Picker("学年学期", selection: $selectedSemester) {
                    Text("全部").tag("")
                    ForEach(semesters) { Text($0.label).tag($0.value) }
                }
                Picker("年级", selection: $selectedGrade) {
                    Text("全部").tag("")
                    ForEach(grades, id: \.self) { Text("\($0)级").tag($0) }
                }
                .onChange(of: selectedGrade) { _, _ in
                    selectedClass = ""
                    Task { await loadClassOptions() }
                }
                Picker("院系", selection: $selectedDepartment) {
                    Text("全部").tag("")
                    ForEach(departments) { Text($0.name).tag($0.value) }
                }
                .onChange(of: selectedDepartment) { _, _ in
                    selectedSubject = ""
                    selectedClass = ""
                    subjects = []
                    classOptions = []
                    Task {
                        await loadSubjects()
                        await loadClassOptions()
                    }
                }
                Picker("专业", selection: $selectedSubject) {
                    Text("全部").tag("")
                    ForEach(subjects) { Text($0.name).tag($0.code) }
                }
                .onChange(of: selectedSubject) { _, _ in
                    selectedClass = ""
                    Task { await loadClassOptions() }
                }
                Picker("班级", selection: $selectedClass) {
                    Text("全部").tag("")
                    ForEach(classOptions) { Text($0.name).tag($0.code) }
                }
                Button {
                    Task { await search() }
                } label: {
                    HStack {
                        Spacer()
                        if searchLoading && classes.isEmpty {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("查询")
                        }
                        Spacer()
                    }
                }
                .disabled(searchLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let searchError, classes.isEmpty {
                Section {
                    Label(searchError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("班级（\(classes.count)/\(totalCount)）") {
                if classes.isEmpty && !searchLoading {
                    Text("暂无数据")
                        .foregroundStyle(.secondary)
                }
                ForEach(classes) { classInfo in
                    NavigationLink {
                        ClassScheduleDetailPage(
                            title: classInfo.className,
                            subtitle: classInfo.planName,
                            loader: { try await api.fetchClassSchedule(planCode: classInfo.planCode, classCode: classInfo.classCode) }
                        )
                    } label: {
                        classRow(classInfo)
                    }
                }
                if hasMore {
                    HStack {
                        Spacer()
                        Button(loadingMore ? "加载中…" : (searchError != nil ? "重试" : "加载更多")) {
                            Task { await loadMore() }
                        }
                        .disabled(loadingMore)
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await search()
        }
    }

    private func classRow(_ classInfo: ClassInfo) -> some View {
        HStack(spacing: 12) {
            Text(String(classInfo.className.suffix(4)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(classInfo.className)
                    .font(.subheadline.weight(.medium))
                Text(classInfo.subjectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !classInfo.departmentName.isEmpty {
                    Text(classInfo.departmentName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 加载

    private func ensureReady() async -> Bool {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        if !ready { needsLogin = true }
        return ready
    }

    private func loadIndex(force: Bool) async {
        guard await ensureReady() else { return }
        if !force && indexLoaded { return }
        indexLoading = true
        defer { indexLoading = false }
        do {
            let index = try await api.fetchClassScheduleInquiryIndex()
            semesters = index.semesters
            grades = index.grades
            departments = index.departments
            indexLoaded = true
            indexError = nil
            await search()
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            indexError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadSubjects() async {
        guard !selectedDepartment.isEmpty else {
            subjects = []
            return
        }
        // 静默加载：失败只清空（与 Flutter 行为一致，不打断主列表）
        subjects = (try? await api.fetchSubjectsByDepartment(selectedDepartment)) ?? []
    }

    private func loadClassOptions() async {
        guard !selectedGrade.isEmpty, !selectedDepartment.isEmpty else {
            classOptions = []
            return
        }
        classOptions = (try? await api.fetchClassOptions(
            yearNum: selectedGrade,
            departmentNum: selectedDepartment,
            subjectNum: selectedSubject
        )) ?? []
    }

    private func search() async {
        searchError = nil
        await loadClasses(page: 1, replace: true)
    }

    private func loadMore() async {
        guard !searchLoading, hasMore else { return }
        await loadClasses(page: pageNum + 1, replace: false)
    }

    private func loadClasses(page: Int, replace: Bool) async {
        searchLoading = true
        loadingMore = !replace
        defer {
            searchLoading = false
            loadingMore = false
        }
        do {
            let result = try await api.fetchClassList(
                pageNum: page,
                executiveEducationPlanNum: selectedSemester,
                yearNum: selectedGrade,
                departmentNum: selectedDepartment,
                subjectNum: selectedSubject,
                classNum: selectedClass
            )
            pageNum = page
            classes = replace ? result.classes : classes + result.classes
            totalCount = result.totalCount
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            searchError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 课程课表查询页（对应 course_curriculum_page.dart）

struct CourseCurriculumPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var semesters: [CurriculumSemesterOption] = []
    @State private var departments: [DepartmentOption] = []
    @State private var categories: [CourseCategoryOption] = []
    @State private var courses: [CourseSectionInfo] = []
    @State private var totalCount = 0
    @State private var pageNum = 1

    @State private var selectedSemester = ""
    @State private var selectedDepartment = ""
    @State private var selectedCategory = ""
    @State private var courseNameText = ""
    @State private var courseCodeText = ""
    @State private var courseSeqText = ""

    @State private var indexLoading = false
    @State private var indexLoaded = false
    @State private var needsLogin = false
    @State private var indexError: String?
    @State private var searchLoading = false
    @State private var loadingMore = false
    @State private var searchError: String?

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    private var hasMore: Bool { courses.count < totalCount }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if indexLoading && !indexLoaded {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let indexError, !indexLoaded {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(indexError)
                } actions: {
                    Button("重试") { Task { await loadIndex(force: true) } }
                }
            } else {
                list
            }
        }
        .navigationTitle("课程课表")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !indexLoaded {
                await loadIndex(force: false)
            }
        }
    }

    private var list: some View {
        List {
            Section("筛选") {
                Picker("学年学期", selection: $selectedSemester) {
                    Text("全部").tag("")
                    ForEach(semesters) { Text($0.label).tag($0.value) }
                }
                Picker("开课院系", selection: $selectedDepartment) {
                    Text("全部").tag("")
                    ForEach(departments) { Text($0.name).tag($0.value) }
                }
                Picker("课程类别", selection: $selectedCategory) {
                    Text("全部").tag("")
                    ForEach(categories) { Text($0.name).tag($0.code) }
                }
                TextField("课程名", text: $courseNameText)
                    .autocorrectionDisabled()
                TextField("课程号", text: $courseCodeText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField("课序号", text: $courseSeqText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button {
                    Task { await search() }
                } label: {
                    HStack {
                        Spacer()
                        if searchLoading && courses.isEmpty {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("查询")
                        }
                        Spacer()
                    }
                }
                .disabled(searchLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let searchError, courses.isEmpty {
                Section {
                    Label(searchError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("课程（\(courses.count)/\(totalCount)）") {
                if courses.isEmpty && !searchLoading {
                    Text("暂无数据")
                        .foregroundStyle(.secondary)
                }
                ForEach(courses) { course in
                    NavigationLink {
                        ClassScheduleDetailPage(
                            title: course.courseName,
                            subtitle: course.planName,
                            loader: {
                                try await api.fetchCourseSchedule(
                                    planCode: course.planCode,
                                    courseCode: course.courseCode,
                                    courseSequenceCode: course.courseSeq
                                )
                            }
                        )
                    } label: {
                        courseRow(course)
                    }
                }
                if hasMore {
                    HStack {
                        Spacer()
                        Button(loadingMore ? "加载中…" : (searchError != nil ? "重试" : "加载更多")) {
                            Task { await loadMore() }
                        }
                        .disabled(loadingMore)
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await search()
        }
    }

    private func courseRow(_ course: CourseSectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(course.courseName)
                    .font(.subheadline.weight(.medium))
                if !course.courseSeq.isEmpty {
                    Text("#\(course.courseSeq)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if !course.credits.isEmpty { Text("\(course.credits) 学分") }
                if !course.category.isEmpty { Text(course.category) }
                if !course.examType.isEmpty { Text(course.examType) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !course.teachers.isEmpty || !course.department.isEmpty {
                Text([course.teachers, course.department].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 加载

    private func loadIndex(force: Bool) async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        if !force && indexLoaded { return }
        indexLoading = true
        defer { indexLoading = false }
        do {
            let index = try await api.fetchCourseCurriculumIndex()
            semesters = index.semesters
            departments = index.departments
            categories = index.categories
            // 与 Flutter 一致：默认选第一个学期
            if selectedSemester.isEmpty {
                selectedSemester = index.semesters.first?.value ?? ""
            }
            indexLoaded = true
            indexError = nil
            await search()
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            indexError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func search() async {
        searchError = nil
        await loadCourses(page: 1, replace: true)
    }

    private func loadMore() async {
        guard !searchLoading, hasMore else { return }
        await loadCourses(page: pageNum + 1, replace: false)
    }

    private func loadCourses(page: Int, replace: Bool) async {
        searchLoading = true
        loadingMore = !replace
        defer {
            searchLoading = false
            loadingMore = false
        }
        do {
            let result = try await api.fetchCourseList(
                pageNum: page,
                semester: selectedSemester,
                department: selectedDepartment,
                courseName: courseNameText,
                courseCode: courseCodeText,
                courseSeq: courseSeqText,
                category: selectedCategory
            )
            pageNum = page
            courses = replace ? result.courses : courses + result.courses
            totalCount = result.totalCount
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            searchError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 周网格详情页（班级/课程课表共用；对应两个 detail 页）

/// 历年学期查询：日期与「当前周」无意义——固定从第 1 周起，隐去表头日期，
/// 左右滑动或顶部箭头切换周次。
struct ClassScheduleDetailPage: View {
    @EnvironmentObject private var appConfig: AppConfig

    let title: String
    let subtitle: String
    let loader: () async throws -> [ClassScheduleInquiryItem]

    @State private var items: [ClassScheduleInquiryItem] = []
    @State private var isLoading = true
    @State private var needsLogin = false
    @State private var errorMessage: String?
    @State private var displayWeek = 1
    @State private var selectedCourse: Course?

    private var totalWeeks: Int { Course.defaultTotalWeeks }

    /// 学期起点仅占位：不参与日期计算（表头日期已隐藏）
    private var gridConfig: ScheduleConfig {
        var config = ScheduleConfig()
        config.semesterStartDate = Date(timeIntervalSince1970: 1_756_665_600) // 2025-09-01（占位）
        return config
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if items.isEmpty {
                ContentUnavailableView("暂无课表", systemImage: "calendar.badge.exclamationmark")
            } else {
                grid
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isLoading && items.isEmpty {
                await load()
            }
        }
        .sheet(item: $selectedCourse) { course in
            InquiryCourseDetailSheet(course: course)
        }
    }

    private var grid: some View {
        let hasWeekend = items.contains { $0.dayOfWeek > 5 }
        let courses = items.map(\.toCourse)
        return VStack(spacing: 0) {
            weekSwitchBar
            TabView(selection: $displayWeek) {
                ForEach(1...totalWeeks, id: \.self) { week in
                    ScrollView(.vertical) {
                        CourseGrid(
                            courses: courses,
                            config: gridConfig,
                            week: week,
                            showWeekend: hasWeekend,
                            rowHeight: appConfig.courseRowHeight,
                            todayWeek: 0,
                            showDates: false,
                            onTapCourse: { selectedCourse = $0 }
                        )
                        .padding(.horizontal, 2)
                        .padding(.bottom, 16)
                    }
                    .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private var weekSwitchBar: some View {
        HStack {
            Button {
                if displayWeek > 1 { displayWeek -= 1 }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(displayWeek <= 1)
            Spacer()
            Text("第 \(displayWeek) 周")
                .font(.subheadline.weight(.bold))
            Spacer()
            Button {
                if displayWeek < totalWeeks { displayWeek += 1 }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(displayWeek >= totalWeeks)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await loader()
            displayWeek = 1
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
            isLoading = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

/// 只读课程详情弹层（查询页课程不可编辑/删除，区别于主课表的 CourseDetailSheet）
struct InquiryCourseDetailSheet: View {
    let course: Course

    @Environment(\.dismiss) private var dismiss

    private var weekText: String {
        let base = course.startWeek == course.endWeek
            ? "第\(course.startWeek)周"
            : "第\(course.startWeek)-\(course.endWeek)周"
        switch course.weekType {
        case .every: return base
        case .odd: return base + "（单周）"
        case .even: return base + "（双周）"
        }
    }

    private var weekdayText: String {
        ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][max(1, min(7, course.dayOfWeek)) - 1]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("课程", value: course.name)
                    if !course.teacher.isEmpty {
                        LabeledContent("教师", value: course.teacher)
                    }
                    if !course.location.isEmpty {
                        LabeledContent("地点", value: course.location)
                    }
                    LabeledContent("周次", value: weekText)
                    LabeledContent("星期", value: weekdayText)
                    LabeledContent("节次", value: "第 \(course.startSection)-\(course.endSection) 节")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
