import SwiftUI

/// 课程编辑页（对应 course_edit_page.dart）：添加 / 编辑 / 副本三模式，
/// 12 预设色、周次/单双周/星期/节次选择、跨时段校验、冲突校验。
struct CourseEditPage: View {
    @Environment(\.dismiss) private var dismiss

    let provider: CourseProvider
    /// 编辑/副本模式传入原课程；添加为 nil
    let original: Course?
    var prefillDayOfWeek: Int?
    var prefillSection: Int?

    enum Mode {
        case create
        case edit
        case copy
    }

    private var mode: Mode {
        if original == nil { return .create }
        return isCopy ? .copy : .edit
    }

    var isCopy = false

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var colorValue = 0xFF42A5F5
    @State private var startWeek = 1
    @State private var endWeek = 16
    @State private var weekType: WeekType = .every
    @State private var dayOfWeek = 1
    @State private var startSection = 1
    @State private var endSection = 2
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private static let presetColors: [Int] = [
        0xFFEF5350, 0xFFEC407A, 0xFFAB47BC, 0xFF7E57C2,
        0xFF5C6BC0, 0xFF42A5F5, 0xFF26C6DA, 0xFF26A69A,
        0xFF66BB6A, 0xFF9CCC65, 0xFFFFA726, 0xFF8D6E63,
    ]

    var body: some View {
        Form {
            Section("课程信息") {
                TextField("课程名称（必填）", text: $name)
                TextField("教师", text: $teacher)
                TextField("上课地点", text: $location)
            }

            Section("课程颜色") {
                colorPicker
            }

            Section("上课周次") {
                HStack {
                    Picker("开始", selection: $startWeek) {
                        ForEach(1...max(totalWeeks, 1), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("至").foregroundStyle(.secondary)
                    Picker("结束", selection: $endWeek) {
                        ForEach(startWeek...max(totalWeeks, startWeek), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("周").foregroundStyle(.secondary)
                }
                Picker("周类型", selection: $weekType) {
                    Text("每周").tag(WeekType.every)
                    Text("单周").tag(WeekType.odd)
                    Text("双周").tag(WeekType.even)
                }
                .pickerStyle(.segmented)
            }

            Section("时间") {
                Picker("星期", selection: $dayOfWeek) {
                    ForEach([7, 1, 2, 3, 4, 5, 6], id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Picker("开始节次", selection: $startSection) {
                        ForEach(1...max(sectionsPerDay, 1), id: \.self) { Text("第\($0)节").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("至").foregroundStyle(.secondary)
                    Picker("结束节次", selection: $endSection) {
                        ForEach(startSection...max(sectionsPerDay, startSection), id: \.self) { Text("第\($0)节").tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if mode == .edit {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除课程", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(name.isEmpty)
            }
        }
        .onAppear(perform: populate)
        .confirmationDialog("删除这门课？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    await provider.deleteCourse(id: original!.id)
                    dismiss()
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "添加课程"
        case .edit: return "编辑课程"
        case .copy: return "创建课程副本"
        }
    }

    private var totalWeeks: Int { provider.config?.totalWeeks ?? 20 }
    private var sectionsPerDay: Int { provider.config?.sectionsPerDay ?? 12 }

    private func weekdayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][day - 1]
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(Self.presetColors, id: \.self) { argb in
                Button {
                    colorValue = argb
                } label: {
                    Circle()
                        .fill(argb.argbColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle().strokeBorder(
                                colorValue == argb ? Color.primary : Color.clear,
                                lineWidth: 3
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func populate() {
        if let original {
            if mode == .copy {
                name = original.name + "（副本）"
            } else {
                name = original.name
            }
            teacher = original.teacher
            location = original.location
            colorValue = original.colorValue
            startWeek = original.startWeek
            endWeek = original.endWeek
            weekType = original.weekType
            dayOfWeek = original.dayOfWeek
            startSection = original.startSection
            endSection = original.endSection
        } else if let prefillDayOfWeek, let prefillSection {
            dayOfWeek = prefillDayOfWeek
            startSection = prefillSection
            endSection = min(prefillSection + 1, max(sectionsPerDay, prefillSection))
        }
    }

    private func save() async {
        guard let config = provider.config else { return }
        // 跨时段校验：需完整落在上午 / 下午 / 晚上之一
        let morningEnd = config.morningSections
        let afternoonEnd = config.morningSections + config.afternoonSections
        let fitsMorning = startSection >= 1 && endSection <= morningEnd
        let fitsAfternoon = startSection == morningEnd + 1 && endSection <= afternoonEnd
        let fitsEvening = startSection == afternoonEnd + 1 && endSection <= config.sectionsPerDay
        if !(fitsMorning || fitsAfternoon || fitsEvening) {
            errorMessage = "课程不能跨时段（上午 / 下午 / 晚上）"
            return
        }

        var course = Course(
            id: mode == .edit ? original!.id : Course.generateId(),
            name: name,
            teacher: teacher,
            location: location,
            campus: original?.campus ?? "",
            startWeek: startWeek,
            endWeek: endWeek,
            dayOfWeek: dayOfWeek,
            startSection: startSection,
            endSection: endSection,
            colorValue: colorValue,
            weekType: weekType
        )
        if course.id.isEmpty {
            course.id = Course.generateId()
        }

        // 冲突校验（编辑模式排除自身）
        let excludeId = (mode == .edit) ? original!.id : nil
        if await provider.hasConflict(course, excludeId: excludeId) {
            errorMessage = "与已有课程时间冲突"
            return
        }

        let ok: Bool
        switch mode {
        case .edit:
            ok = await provider.updateCourse(course)
        default:
            ok = await provider.addCourse(course)
        }
        if ok {
            dismiss()
        } else {
            errorMessage = provider.loadError ?? "保存失败"
        }
    }
}

// MARK: - 导入弹层（分享 JSON 粘贴 / 教务 JSON 粘贴 / 在线拉取）

struct ImportScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    let provider: CourseProvider

    @State private var showPaste = false
    @State private var pastedJson = ""
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showPaste = true
                } label: {
                    Label("从分享文件导入（粘贴 JSON）", systemImage: "square.and.arrow.down.on.square")
                }
                Button {
                    showPaste = true  // jwxt JSON 粘贴与分享共用粘贴入口，解析时自动判别
                } label: {
                    Label("从教务 JSON 导入", systemImage: "doc.text")
                }
                NavigationLink {
                    OnlineImportPage(provider: provider)
                } label: {
                    Label("从教务系统在线导入", systemImage: "cloud")
                }
            }
            .navigationTitle("导入课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaste) {
                pasteSheet
            }
        }
    }

    private var pasteSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $pastedJson)
                    .font(.body.monospaced())
                    .frame(maxHeight: .infinity)
                    .padding(8)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }
                Button {
                    Task { await importPasted() }
                } label: {
                    Text(isImporting ? "导入中…" : "导入")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                .padding()
            }
            .navigationTitle("粘贴 JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPaste = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func importPasted() async {
        isImporting = true
        defer { isImporting = false }
        guard let (config, courses) = CourseProvider.parseShareImport(pastedJson) else {
            importError = "JSON 解析失败：请确认粘贴完整的分享文件内容"
            return
        }
        var mutableConfig = config
        await provider.importSchedule(
            config: &mutableConfig,
            courses: courses
        ) { _ in
            .addWithSuffix
        }
        if provider.loadError == nil {
            showPaste = false
            dismiss()
        } else {
            importError = provider.loadError
        }
    }
}

/// 在线导入（教务拉取）——依赖 ZhjwApiService（Phase 3 接入后启用）
struct OnlineImportPage: View {
    let provider: CourseProvider

    var body: some View {
        ContentUnavailableView(
            "在线导入",
            systemImage: "cloud",
            description: Text("教务系统在线导入将在后续版本开放\n可先使用分享文件 / 教务 JSON 导入")
        )
    }
}

// MARK: - 课表管理页

struct ScheduleManagementPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    let provider: CourseProvider
    @State private var newScheduleName = ""
    @State private var showCreateDialog = false

    var body: some View {
        List {
            ForEach(provider.schedules, id: \.id) { schedule in
                Button {
                    Task {
                        await provider.switchSchedule(id: schedule.id)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: schedule.id == provider.currentScheduleId ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(schedule.id == provider.currentScheduleId ? Color.accentColor : Color(.systemGray3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.semesterName.isEmpty ? "默认课表" : schedule.semesterName)
                                .foregroundStyle(.primary)
                            Text("共 \(schedule.totalWeeks) 周 · \(ScheduleConfig.formatDate(schedule.semesterStartDate)) 开学")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await provider.deleteSchedule(id: schedule.id) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if provider.schedules.isEmpty {
                ContentUnavailableView("暂无课表", systemImage: "calendar")
            }
        }
        .navigationTitle("课表管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateDialog = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .alert("新建课表", isPresented: $showCreateDialog) {
            TextField("课表名称（如 2026-2027学年秋季学期）", text: $newScheduleName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                let name = newScheduleName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await provider.createSchedule(name: name)
                    newScheduleName = ""
                }
            }
        }
    }
}
