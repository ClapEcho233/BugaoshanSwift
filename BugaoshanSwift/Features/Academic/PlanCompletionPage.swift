import SwiftUI

/// 方案修读情况页（对应 plan_completion_page.dart）：
/// 摘要卡 + 根模块树（大类/课程组/课程三级），多方案左右滑动切换。
struct PlanCompletionPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var plans: [PlanCompletionPlan] = []
    @State private var currentPlanIndex = 0
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var needsLogin = false
    @State private var errorMessage: String?
    @State private var isRateLimited = false

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if isLoading && !hasLoaded {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, !hasLoaded {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(force: true) } }
                }
            } else if plans.isEmpty {
                ContentUnavailableView("暂无方案修读数据", systemImage: "doc.text.magnifyingglass")
            } else {
                content
            }
        }
        .navigationTitle("计划完成度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task {
            if !hasLoaded {
                await load(force: false)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // 顶部方案名指示栏（多方案时提示可滑动 + 序号）
            HStack(spacing: 6) {
                if plans.count > 1 {
                    Image(systemName: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(currentPlan.name.isEmpty ? "培养方案" : currentPlan.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if plans.count > 1 {
                    Text("\(currentPlanIndex + 1)/\(plans.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(isRateLimited ? .orange : .red)
                    .padding(.bottom, 4)
            }

            // 方案数量变化时以 id 强制重建，视口回第 0 页（对应 Flutter ValueKey）
            TabView(selection: $currentPlanIndex) {
                ForEach(Array(plans.enumerated()), id: \.element.uid) { index, plan in
                    PlanPlanView(plan: plan)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: plans.count > 1 ? .automatic : .never))
            .id(plans.count)
        }
    }

    private var currentPlan: PlanCompletionPlan {
        plans.indices.contains(currentPlanIndex) ? plans[currentPlanIndex] : plans[0]
    }

    private func load(force: Bool) async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        needsLogin = false
        if !force && hasLoaded { return }
        isLoading = true
        defer { isLoading = false }
        do {
            plans = try await api.fetchPlanCompletion()
            hasLoaded = true
            currentPlanIndex = 0
            errorMessage = nil
            isRateLimited = false
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch let error as SCUError where error == .rateLimited {
            // 有缓存时保留旧数据，只提示
            errorMessage = "请勿频繁刷新，请稍后再试"
            isRateLimited = true
        } catch {
            if hasLoaded {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "刷新失败，展示的是缓存数据"
                isRateLimited = false
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                isRateLimited = false
            }
        }
    }
}

/// 单份方案内容：摘要卡 + 根模块树
private struct PlanPlanView: View {
    let plan: PlanCompletionPlan

    private var rootNodes: [PlanCompletionNode] {
        plan.nodes.filter { $0.pId == "-1" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if rootNodes.isEmpty {
                    Text("暂无方案修读数据")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    let stats = PlanCompletionSummaryStats.compute(plan.nodes)
                    summaryCard(stats)
                    ForEach(Array(rootNodes.enumerated()), id: \.element.id) { _, node in
                        PlanNodeTile(nodes: plan.nodes, node: node, depth: 0)
                    }
                }
            }
            .padding()
        }
    }

    private func summaryCard(_ stats: PlanCompletionSummaryStats) -> some View {
        HStack {
            Spacer()
            statItem(value: String(format: "%.1f", stats.totalEarned), label: "已获学分")
            Spacer()
            Rectangle().fill(.quaternary).frame(width: 1, height: 34)
            Spacer()
            statItem(value: "\(stats.completedCount)/\(stats.moduleCount)", label: "已完成模块")
            Spacer()
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 树节点瓦片：有子节点的大类/课程组 → 可展开；叶子模块 → 普通行；课程 → 成绩行
private struct PlanNodeTile: View {
    let nodes: [PlanCompletionNode]
    let node: PlanCompletionNode
    let depth: Int

    @State private var isExpanded = false

    private var children: [PlanCompletionNode] {
        nodes.filter { $0.pId == node.id }
    }

    /// 公共基础课(最低修读学分:25,…) → 公共基础课
    private var displayName: String {
        guard let idx = node.name.firstIndex(of: "("), idx > node.name.startIndex else { return node.name }
        return String(node.name[..<idx]).trimmingCharacters(in: .whitespaces)
    }

    private var progress: Double {
        let earned = Double(node.earnedCredits) ?? 0
        let required = Double(node.requiredCredits) ?? 0
        guard required > 0 else { return 0 }
        return min(max(earned / required, 0), 1)
    }

    var body: some View {
        if node.isCourse {
            courseRow
        } else if children.isEmpty {
            leafRow
        } else {
            categoryTile
        }
    }

    // MARK: 大类/课程组（可展开）

    private var categoryTile: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: node.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(node.completed ? Color.accentColor : Color(.systemGray3))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 12) {
                            Text("学分: \(node.earnedCredits)/\(node.requiredCredits)")
                            if let countInfo = courseCountInfo {
                                Text(countInfo)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { _, child in
                        PlanNodeTile(nodes: nodes, node: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 22)
                .padding(.bottom, 6)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 8)
    }

    /// 已及格课程门数:17,必修课未修读:3 → 课程: 17/20
    private var courseCountInfo: String? {
        guard node.name.contains("已修课程门数"),
              let m = RegexHelper.firstMatch(#"已及格课程门数:(\d+)"#, in: node.name) else { return nil }
        let passed = Int(m[1]) ?? 0
        let uncompleted = Int(RegexHelper.firstMatch(#"必修课未修读:(\d+)"#, in: node.name)?[1] ?? "") ?? 0
        return "课程: \(passed)/\(passed + uncompleted)"
    }

    // MARK: 叶子模块（美育、创新创业教育等无子节点模块）

    private var leafRow: some View {
        HStack(spacing: 12) {
            Image(systemName: node.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(node.completed ? Color.accentColor : Color(.systemGray3))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                Text("学分: \(node.earnedCredits)/\(node.requiredCredits)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView(value: progress)
                .frame(width: 64)
                .tint(Color.accentColor)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 8)
    }

    // MARK: 课程行

    private var isPassed: Bool {
        RegexHelper.matches(#"fa-smile-o.*green"#, in: node.rawName)
    }

    /// (必修,96.0(20240107)) → 96.0
    private var gradeDisplay: String? {
        guard !node.gradeInfo.isEmpty else { return nil }
        return RegexHelper.firstMatch(#",([\d.]+)\("#, in: node.gradeInfo)?[1]
    }

    private var courseRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isPassed ? "checkmark.circle" : "circle.dashed")
                .font(.subheadline)
                .foregroundStyle(isPassed ? Color.accentColor : Color(.systemGray3))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.courseName.isEmpty ? displayName : node.courseName)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    if !node.courseCode.isEmpty {
                        Text(node.courseCode)
                    }
                    if !node.courseCredits.isEmpty {
                        Text("\(node.courseCredits)学分")
                    }
                    if !node.academicTerm.isEmpty {
                        Text(node.academicTerm)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let gradeDisplay {
                Text(gradeDisplay)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (isPassed ? Color.accentColor : Color.red).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(isPassed ? Color.accentColor : Color.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
