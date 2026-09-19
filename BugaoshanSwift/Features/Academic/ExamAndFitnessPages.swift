import SwiftUI

/// 考表页（对应 exam_plan_page.dart）：考试卡片列表 + ICS 导出
struct ExamPlanPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var exams: [ExamInfo] = []
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?
    @State private var showExportSheet = false

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    var body: some View {
        Group {
            if isLoading && exams.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if let errorMessage, exams.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if exams.isEmpty {
                ContentUnavailableView(
                    "暂无考试安排",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("考试周临近时会在这里显示"))
            } else {
                examList
            }
        }
        .navigationTitle("考表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportIcs()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .disabled(exams.isEmpty)
            }
        }
        .task {
            if exams.isEmpty {
                await load()
            }
        }
        .refreshable {
            await load()
        }
        .sheet(isPresented: $showExportSheet) {
            IcsPreviewSheet(
                title: "考表日历",
                fileName: "SCU_Exams.ics",
                content: icsContent
            )
        }
    }

    private var examList: some View {
        List {
            ForEach(exams) { exam in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(exam.courseName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if exam.isPast {
                            Text("已结束")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Label("\(exam.date) \(exam.weekday) \(exam.timeRange)", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(exam.location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if exam.seatNumber != "未知" {
                            Text("座位号 \(exam.seatNumber)")
                        }
                        if !exam.ticketNumber.isEmpty {
                            Text("准考证 \(exam.ticketNumber)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    if exam.tip != "无" && !exam.tip.isEmpty {
                        Text(exam.tip)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func load() async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        needsLogin = false
        isLoading = true
        defer { isLoading = false }
        do {
            exams = try await api.fetchExamPlan()
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var icsContent: String {
        IcsBuilder.examIcs(exams: exams.map { exam in
            (name: exam.courseName, week: "第\(exam.week)周", date: exam.date,
             timeRange: exam.timeRange, location: exam.location,
             seatNumber: exam.seatNumber, ticketNumber: exam.ticketNumber, tip: exam.tip)
        })
    }

    private func exportIcs() {
        showExportSheet = true
    }
}

/// ICS 预览/分享弹层
struct IcsPreviewSheet: View {
    let title: String
    let fileName: String
    let content: String
    var events: [CalendarEventPayload] = []

    @Environment(\.dismiss) private var dismiss
    @State private var showCalendarPicker = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: content, subject: Text(title), preview: SharePreview(fileName)) {
                        Text("分享")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !events.isEmpty {
                    Button {
                        Task { await startImport() }
                    } label: {
                        Label("添加到系统日历", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                calendarPickerSheet
            }
            .alert("提示", isPresented: Binding(
                get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    @State private var calendars: [CalendarImportService.Destination] = []
    @State private var importService = CalendarImportService()

    private func startImport() async {
        do {
            try await importService.requestWriteAccess()
            let list = importService.writableCalendars()
            guard !list.isEmpty else {
                importMessage = "没有可写的日历"
                return
            }
            calendars = list
            showCalendarPicker = true
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private var calendarPickerSheet: some View {
        NavigationStack {
            List(calendars) { calendar in
                Button {
                    showCalendarPicker = false
                    Task {
                        do {
                            try importService.importEvents(events, calendarIdentifier: calendar.identifier)
                            importMessage = "已添加到系统日历（\(events.count) 个事件）"
                        } catch {
                            importMessage = (error as? LocalizedError)?.errorDescription ?? "导入失败"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: calendar.isDefault ? "star.circle" : "calendar")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.title).foregroundStyle(.primary)
                            if calendar.isDefault || !calendar.sourceTitle.isEmpty {
                                Text([calendar.isDefault ? "默认" : nil, calendar.sourceTitle.isEmpty ? nil : calendar.sourceTitle]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showCalendarPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 体测页（成绩单页）：胶囊年份条（入学学年 → 当前学年）+ 成绩卡
struct FitnessTestPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var score: FitnessApiService.FitnessScore?
    @State private var year = String(Calendar.current.component(.year, from: Date()))
    @State private var isScoreLoading = false
    @State private var needsLogin = false
    @State private var scoreError: String?
    @State private var scoreGeneration = 0
    @State private var showLogin = false

    private var api: FitnessApiService {
        FitnessApiService(auth: environment.fitnessAuth)
    }

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// 入学年：学号前 4 位（2025141530009 → 2025）；取不到时按本科四年回退
    private var enrollmentYear: Int {
        let number = UserDefaults.standard.string(forKey: StorageKeys.scuUserNumber)
            ?? environment.authBus.username ?? ""
        guard number.count >= 4,
              let parsed = Int(number.prefix(4)),
              (1990...currentYear).contains(parsed) else {
            return max(currentYear - 4, 2000)
        }
        return parsed
    }

    private var availableYears: [String] {
        (enrollmentYear...currentYear).map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            yearBar
                .padding(.bottom, 8)
            scoreContent
        }
        .navigationTitle("体测")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .onChange(of: year) { _ in
            Task { await loadScore(allowFallback: false) }
        }
    }

    /// 液态玻璃胶囊年份条：入学学年 → 当前学年横向陈列（各状态同一位置同一样式）
    private var yearBar: some View {
        Picker("查询年份", selection: $year) {
            ForEach(availableYears, id: \.self) { y in
                Text(y).tag(y)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .disabled(needsLogin)
    }

    @ViewBuilder
    private var scoreContent: some View {
        if needsLogin {
            loginPrompt
        } else {
            List {
                if isScoreLoading {
                    loadingRow("查询中…")
                } else if let score {
                    totalScoreSection(score)
                    itemsSection(score)
                } else if let scoreError {
                    Section {
                        errorRow(scoreError) {
                            Task { await loadScore(allowFallback: false) }
                        }
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.run")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("\(year) 年暂无体测成绩")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await loadScore(allowFallback: false)
            }
        }
    }

    private func totalScoreSection(_ score: FitnessApiService.FitnessScore) -> some View {
        Section {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .strokeBorder(gradeColor(score.totalGrade), lineWidth: 4)
                    Text(score.totalScore)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(gradeColor(score.totalGrade))
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text("总分")
                        .font(.subheadline.weight(.semibold))
                    Text(score.totalGrade)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gradeColor(score.totalGrade))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(gradeColor(score.totalGrade).opacity(0.12), in: Capsule())
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private func itemsSection(_ score: FitnessApiService.FitnessScore) -> some View {
        Section("单项成绩") {
            scoreItemRow(label: "身高/体重", item: score.bmi, unit: nil)
            scoreItemRow(label: "肺活量", item: score.vitalCapacity, unit: nil)
            scoreItemRow(label: "立定跳远", item: score.jump, unit: "cm")
            scoreItemRow(label: "坐位体前屈", item: score.sitAndReach, unit: "cm")
            scoreItemRow(
                label: score.sex == "女" ? "仰卧起坐" : "引体向上",
                item: score.pullAndSit, unit: nil)
            scoreItemRow(label: "50米跑", item: score.fiftyM, unit: "s")
            scoreItemRow(label: "800/1000米跑", item: score.run, unit: nil)
        }
    }

    private func scoreItemRow(
        label: String, item: FitnessApiService.FitnessScoreItem, unit: String?
    ) -> some View {
        let color = item.isFail ? Color.red : Color.green
        let display = item.rawScore == "-" ? "-" : (unit.map { "\(item.rawScore) \($0)" } ?? item.rawScore)
        return HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(display)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Text("\(item.gradedScore) 分 · \(item.grade)")
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
        .padding(.vertical, 2)
    }

    /// 等级 → 颜色（不及格须先于及格判断，"不及格"包含"及格"）
    private func gradeColor(_ grade: String) -> Color {
        if grade.contains("优秀") { return .blue }
        if grade.contains("良好") { return .green }
        if grade.contains("不及格") { return .red }
        if grade.contains("及格") { return .orange }
        return .secondary
    }

    private func loadingRow(_ text: String) -> some View {
        Section {
            HStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 48)
        }
    }

    private func errorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Label("加载失败", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var loginPrompt: some View {
        ContentUnavailableView {
            Label("未登录", systemImage: "person.badge.key")
        } actions: {
            Button("去登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showLogin, onDismiss: {
            Task { await load() }
        }) {
            NavigationStack {
                ScuLoginPage()
            }
        }
    }

    // MARK: - 加载

    private func load() async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        needsLogin = false
        await loadScore(allowFallback: true)
    }

    private func loadScore(allowFallback: Bool) async {
        scoreGeneration += 1
        let generation = scoreGeneration
        isScoreLoading = true
        score = nil
        scoreError = nil
        defer {
            if generation == scoreGeneration {
                isScoreLoading = false
            }
        }
        let fetchedYear = year
        do {
            let result = try await api.fetchScore(year: fetchedYear)
            guard generation == scoreGeneration else { return }
            score = result
            // 首次进入默认查当前历年；无数据（体测在秋季，年初尚未开测）时
            // 自动回退上一年（仍在滚轮范围内）。用户手动选年不回退。
            if result == nil, allowFallback, fetchedYear == String(currentYear),
               currentYear - 1 >= enrollmentYear {
                year = String(currentYear - 1)
            }
        } catch let error as SCUError where error.isUnauthenticated {
            guard generation == scoreGeneration else { return }
            needsLogin = true
        } catch {
            guard generation == scoreGeneration else { return }
            scoreError = error.localizedDescription
        }
    }
}
