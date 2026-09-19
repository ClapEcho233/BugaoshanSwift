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

    @Environment(\.dismiss) private var dismiss

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
        }
    }
}

/// 体测页（对应 fitness_test_page.dart）：成绩 + 通知双 Tab
struct FitnessTestPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var tab = 0
    @State private var score: FitnessApiService.FitnessScore?
    @State private var notices: [FitnessApiService.FitnessNotice] = []
    @State private var year = String(Calendar.current.component(.year, from: Date()))
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?

    private var api: FitnessApiService {
        FitnessApiService(auth: environment.fitnessAuth)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $tab) {
                Text("成绩").tag(0)
                Text("通知").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 {
                scoreTab
            } else {
                noticeTab
            }
        }
        .navigationTitle("体测")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private var scoreTab: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if let score {
                List {
                    Section("体测成绩（\(year)）") {
                        ForEach(score.raw.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                Spacer()
                                Text(value)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if isLoading {
                ProgressView("查询中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Picker("年度", selection: $year) {
                        ForEach(availableYears, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    ContentUnavailableView(
                        "暂无成绩",
                        systemImage: "figure.run",
                        description: Text("选择年度后下拉刷新"))
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if score != nil {
                Picker("年度", selection: $year) {
                    ForEach(availableYears, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
        }
        .onChange(of: year) { _ in
            Task { await loadScore() }
        }
    }

    private var noticeTab: some View {
        Group {
            if notices.isEmpty && isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notices.isEmpty {
                ContentUnavailableView("暂无通知", systemImage: "bell")
            } else {
                List {
                    ForEach(notices) { notice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.title)
                                .font(.subheadline.weight(.medium))
                            Text(notice.time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var availableYears: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (current - 5...current).map(String.init).reversed()
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
            score = try await api.fetchScore(year: year)
            notices = (try? await api.fetchNotices()) ?? []
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadScore() async {
        score = try? await api.fetchScore(year: year)
    }
}
