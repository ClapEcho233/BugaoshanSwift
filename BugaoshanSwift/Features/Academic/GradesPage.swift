import SwiftUI

/// 成绩页（对应 grades_page.dart）：及格成绩（按学期分组）+ 方案成绩（统计 + 明细）
struct GradesPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var tab = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var needsLogin = false
    @State private var passingGroups: [PassingScoreGroup] = []
    @State private var summaries: [SchemeScoreSummary] = []
    @State private var searchText = ""
    @State private var selectedPlanIndex = 0

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    private var defaultSummary: SchemeScoreSummary? {
        SchemeScoreSummary.defaultScheme(summaries)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("成绩类型", selection: $tab) {
                Text("及格成绩").tag(0)
                Text("方案成绩").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if needsLogin {
                Spacer()
                ContentUnavailableView {
                    Label("未登录", systemImage: "person.badge.key")
                } description: {
                    Text("请先登录统一身份认证后查看成绩")
                }
                Spacer()
            } else if let errorMessage {
                Spacer()
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
                Spacer()
            } else if tab == 0 {
                passingList
            } else {
                schemeList
            }
        }
        .navigationTitle("成绩")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索课程")
        .task {
            if passingGroups.isEmpty && summaries.isEmpty {
                await load()
            }
        }
        .refreshable {
            await load()
        }
    }

    private var filteredPassingGroups: [PassingScoreGroup] {
        guard !searchText.isEmpty else { return passingGroups }
        return passingGroups.map { group in
            PassingScoreGroup(label: group.label, items: group.items.filter {
                $0.courseName.localizedCaseInsensitiveContains(searchText)
            })
        }
        .filter { !$0.items.isEmpty }
    }

    private var passingList: some View {
        List {
            ForEach(filteredPassingGroups) { group in
                Section(group.label) {
                    ForEach(group.items) { item in
                        scoreRow(item)
                    }
                }
            }
            if filteredPassingGroups.isEmpty {
                ContentUnavailableView("暂无成绩", systemImage: "chart.bar")
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var schemeList: some View {
        Group {
            if let summary = defaultSummary {
                List {
                    Section {
                        statsGrid(summary)
                    }
                    if summaries.count > 1 {
                        Section("培养方案") {
                            Picker("方案", selection: $selectedPlanIndex) {
                                ForEach(summaries.indices, id: \.self) { index in
                                    Text(summaries[index].planName.isEmpty ? "方案 \(index + 1)" : summaries[index].planName)
                                        .tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        let selected = summaries[min(selectedPlanIndex, summaries.count - 1)]
                        Section("\(selected.planName) · \(selected.items.count) 门") {
                            ForEach(selected.items) { item in
                                scoreRow(item)
                            }
                        }
                    } else {
                        Section("\(summary.planName)") {
                            ForEach(summary.items) { item in
                                scoreRow(item)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("暂无方案成绩", systemImage: "chart.bar.xaxis")
            }
        }
        .onChange(of: selectedPlanIndex) { _ in }
    }

    private func statsGrid(_ summary: SchemeScoreSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statTile("GPA", String(format: "%.2f", summary.gpa))
            statTile("必修 GPA", String(format: "%.2f", summary.requiredGpa))
            statTile("加权平均分", String(format: "%.1f", summary.weightedAvgScore))
            statTile("已修学分", String(format: "%.1f", summary.earnedCredits))
            statTile("通过门数", "\(summary.passedCount)")
            statTile("未通过", "\(summary.failedCount)")
        }
        .padding(.vertical, 4)
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func scoreRow(_ item: SchemeScoreItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.courseName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(item.courseAttributeName)
                    Text("\(item.credit) 学分")
                    if !item.termName.isEmpty {
                        Text(item.termName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.gradeName.isEmpty ? item.cj : item.gradeName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(item.passed ? Color.primary : Color.red)
                if !item.cj.isEmpty && item.cj != item.gradeName {
                    Text(item.cj)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 并行拉两组成绩
            async let passing = api.fetchScores(kind: .passing)
            async let scheme = api.fetchScores(kind: .scheme)
            let (passingJson, schemeJson) = try await (passing, scheme)

            // 及格成绩：{cjList: [...]}（allPassingScores）
            let passingItems = ((passingJson["cjList"] as? [[String: Any]]) ?? [])
                .map(SchemeScoreItem.fromJson)
                .filter { !$0.courseName.isEmpty }
            passingGroups = PassingScoreGroup.group(passingItems)

            summaries = SchemeScoreSummary.parseSummaries(schemeJson)
            selectedPlanIndex = 0
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
