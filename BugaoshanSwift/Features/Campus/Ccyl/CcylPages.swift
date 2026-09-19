import SwiftUI

// MARK: - 第二课堂主页（ccyl_page.dart）：4 Tab + 绑定门

struct CcylPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var currentIndex = 0
    @State private var showBind = false
    @State private var ccylBound = false

    private var api: CcylApiService {
        CcylApiService(auth: environment.ccylAuth)
    }

    var body: some View {
        Group {
            if environment.authBus.scuState != .ready {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if !ccylBound {
                VStack(spacing: 16) {
                    ContentUnavailableView("请先绑定第二课堂账号", systemImage: "link.badge.plus")
                    Button {
                        showBind = true
                    } label: {
                        Label("绑定第二课堂", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 60)
            } else {
                tabs
            }
        }
        .navigationTitle("第二课堂")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            ccylBound = await environment.ccylAuth.isLoggedIn()
        }
        .sheet(isPresented: $showBind) {
            CcylBindPage(api: api, scuAuth: environment.scuAuth) {
                ccylBound = true
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                CcylActivitiesTab(api: api).tag(0)
                CcylMyActivitiesTab(api: api).tag(1)
                CcylOrderedActivitiesTab(api: api).tag(2)
                CcylCreditListPage(api: api).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Divider()
            HStack {
                tabItem(0, icon: "magnifyingglass", label: "活动搜索")
                tabItem(1, icon: "person", label: "我参与的活动")
                tabItem(2, icon: "bookmark", label: "预约的活动")
                tabItem(3, icon: "doc.plaintext", label: "成绩单")
            }
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func tabItem(_ index: Int, icon: String, label: String) -> some View {
        Button {
            // 禁用动画：.page 样式带动画切换内容会闪跳
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { currentIndex = index }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline.weight(currentIndex == index ? .semibold : .regular))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(currentIndex == index ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 绑定页（ccyl_bind_page.dart）

struct CcylBindPage: View {
    let api: CcylApiService
    let scuAuth: ScuAuth
    let onBound: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ContentUnavailableView("绑定第二课堂", systemImage: "link.badge.plus")
                    .padding(.top, 60)
                Text("绑定第二课堂账号后即可查看活动信息")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("点击按钮自动完成绑定")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button {
                    Task { await doBind() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "arrow.up.right.square")
                            Text("打开统一认证授权页")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .navigationTitle("绑定第二课堂")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func doBind() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let oauth = await CcylOAuthService.getOAuthCode(scuAuth: scuAuth)
        guard let code = oauth.code else {
            errorMessage = oauth.diagnostic ?? "获取授权码失败"
            return
        }
        do {
            try await api.loginWithOAuthCode(code)
            onBound()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "绑定失败"
        }
    }
}

// MARK: - 活动搜索 Tab（activities_tab.dart）

struct CcylActivitiesTab: View {
    let api: CcylApiService

    @State private var activities: [CyclActivity] = []
    @State private var searchText = ""
    @State private var pageNum = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            list
                .contentMargins(.top, 54, for: .scrollContent)
                .scrollEdgeEffectStyle(.hard, for: .top)
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .autocorrectionDisabled()
    }

    /// 液态玻璃胶囊悬浮搜索框（不用 interactive：会随滚动边缘联动吸附）
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索活动名称", text: $searchText)
                .autocorrectionDisabled()
                .onSubmit {
                    Task { await load(loadMore: false) }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    Task { await load(loadMore: false) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private var list: some View {
        if let errorMessage, activities.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await load(loadMore: false) } }
            }
        } else {
            List {
                ForEach(activities) { activity in
                    NavigationLink {
                        CcylActivityLibDetailPage(api: api, activityLibraryId: activity.activityLibraryId)
                    } label: {
                        CcylActivityCard(activity: activity)
                    }
                }
                if hasMore {
                    Button("加载更多") {
                        Task { await load(loadMore: true) }
                    }
                    .disabled(isLoading)
                    .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                await load(loadMore: false)
            }
        }
    }

    private func load(loadMore: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = loadMore ? pageNum + 1 : 1
            let results = try await api.searchActivities(pageNum: page, name: searchText)
            if loadMore {
                activities += results
                pageNum = page
            } else {
                activities = results
                pageNum = 1
            }
            hasMore = results.count >= 10
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 我参与的活动（my_activities_tab.dart）

struct CcylMyActivitiesTab: View {
    let api: CcylApiService

    @State private var activities: [CyclActivity] = []
    @State private var pageNum = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage, activities.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(loadMore: false) } }
                }
            } else {
                List {
                    ForEach(activities) { activity in
                        NavigationLink {
                            CcylActivityDetailPage(api: api, activityId: activity.activityId ?? activity.id)
                        } label: {
                            CcylActivityCard(activity: activity)
                        }
                    }
                    if hasMore {
                        Button("加载更多") {
                            Task { await load(loadMore: true) }
                        }
                        .disabled(isLoading)
                        .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(loadMore: false) }
            }
        }
        .task {
            if activities.isEmpty {
                await load(loadMore: false)
            }
        }
    }

    private func load(loadMore: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = loadMore ? pageNum + 1 : 1
            let results = try await api.getMyActivities(pageNum: page)
            if loadMore {
                activities += results
                pageNum = page
            } else {
                activities = results
                pageNum = 1
            }
            hasMore = results.count >= 10
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 预约的活动（ordered_activities_tab.dart）

struct CcylOrderedActivitiesTab: View {
    let api: CcylApiService

    @State private var activities: [CyclActivity] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage, activities.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else {
                List {
                    ForEach(activities) { activity in
                        NavigationLink {
                            CcylActivityLibDetailPage(api: api, activityLibraryId: activity.activityLibraryId)
                        } label: {
                            CcylActivityCard(activity: activity)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .task {
            if activities.isEmpty {
                await load()
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            activities = try await api.getOrderedActivities()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 活动卡片

struct CcylActivityCard: View {
    let activity: CyclActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.activityName.isEmpty ? activity.name : activity.activityName)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(.caption2)
                Text(activity.orgName)
                    .lineLimit(1)
                Spacer()
                Text(activity.statusText)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (activity.doing ? Color.green : Color.gray).opacity(0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(activity.doing ? .green : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let levelName = activity.levelName, !levelName.isEmpty {
                    Text(levelName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                if let starName = activity.starName, !starName.isEmpty {
                    Label(starName, systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(activity.classHour, specifier: "%.1f") 学时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 活动系列详情（activity_lib_detail_page.dart）

struct CcylActivityLibDetailPage: View {
    let api: CcylApiService
    let activityLibraryId: String

    @State private var detail: CcylService.LibDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionLoading = false
    @State private var toastMessage: String?

    var body: some View {
        Group {
            if isLoading {
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
            } else if let detail {
                content(detail)
            }
        }
        .navigationTitle("活动系列")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("提示", isPresented: Binding(
            get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private func content(_ detail: CcylService.LibDetail) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.activityLib.name)
                        .font(.headline)
                    infoRows(detail.activityLib)
                    Button {
                        Task { await toggleSubscription(detail) }
                    } label: {
                        HStack {
                            Spacer()
                            if actionLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(detail.subscribed ? "取消预约" : "预约")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(detail.subscribed ? .red : .accentColor)
                    .disabled(actionLoading)
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(detail.activities) { activity in
                    NavigationLink {
                        CcylActivityDetailPage(api: api, activityId: activity.activityId ?? activity.id)
                    } label: {
                        CcylActivityCard(activity: activity)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func infoRows(_ lib: CyclActivityLib) -> some View {
        let rows: [(String, String)] = [
            ("主办方", lib.orgName),
            ("学时", String(format: "%.1f", lib.classHour)),
            ("星级", lib.starName ?? lib.star),
            ("性质", lib.qualityName ?? lib.quality.joined(separator: "、")),
            ("积分类型", lib.scoreTypeNames ?? ""),
            ("负责人", lib.liablePer.isEmpty ? "" : "\(lib.liablePer) \(lib.liablePerPhone)"),
        ]
        if let describe = lib.describe, !describe.isEmpty {
            Text(describe)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { label, value in
                if !value.isEmpty {
                    HStack(alignment: .top) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text(value)
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func toggleSubscription(_ detail: CcylService.LibDetail) async {
        actionLoading = true
        defer { actionLoading = false }
        do {
            if detail.subscribed {
                try await api.cancelSubscribe(activityLibraryId: activityLibraryId)
                toastMessage = "取消预约成功"
            } else {
                try await api.subscribeActivity(activityLibraryId: activityLibraryId)
                toastMessage = "预约成功"
            }
            await load()
        } catch {
            toastMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        }
    }

    private func load() async {
        isLoading = detail == nil
        errorMessage = nil
        if detail != nil { isLoading = false }
        defer { isLoading = false }
        do {
            detail = try await api.getActivityLibDetail(activityLibraryId: activityLibraryId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 活动详情 + 报名（activity_detail_page.dart）

struct CcylActivityDetailPage: View {
    let api: CcylApiService
    let activityId: String

    @State private var detail: CcylService.ActivityDetail?
    @State private var signedUp = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionLoading = false
    @State private var toastMessage: String?
    @State private var scoreTypePicker: [CyclScoreType]?

    var body: some View {
        Group {
            if isLoading {
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
            } else if let detail {
                content(detail)
            }
        }
        .navigationTitle("活动详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("提示", isPresented: Binding(
            get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { scoreTypePicker != nil }, set: { if !$0 { scoreTypePicker = nil } }
        )) {
            if let scoreTypes = scoreTypePicker {
                scoreTypeSheet(scoreTypes)
            }
        }
    }

    private func content(_ detail: CcylService.ActivityDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    let activity = detail.activity
                    VStack(alignment: .leading, spacing: 8) {
                        Text(activity.activityName.isEmpty ? activity.name : activity.activityName)
                            .font(.headline)
                        sectionRows(activity, lib: detail.activityLib)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            Button {
                Task { await toggleSignUp() }
            } label: {
                HStack {
                    Spacer()
                    if actionLoading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Text(signedUp ? "取消报名" : "报名")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(signedUp ? .red : .accentColor)
            .disabled(actionLoading)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func sectionRows(_ activity: CyclActivity, lib: CyclActivityLib?) -> some View {
        let rows: [(String, String, String)] = [
            ("时间", "clock", "\(activity.startTime ?? "—") ~ \(activity.endTime ?? "—")"),
            ("报名时间", "calendar.badge.plus", "\(activity.enrollStartTime ?? "—") ~ \(activity.enrollEndTime ?? "—")"),
            ("地点", "mappin.and.ellipse", activity.activityAddress ?? "—"),
            ("主办方", "building.2", activity.orgName),
            ("星级", "star.fill", activity.starName ?? lib?.starName ?? ""),
            ("性质", "tag", activity.qualityName ?? ""),
            ("积分类型", "point.3.connected.trianglepath.dotted", lib?.scoreTypeNames ?? ""),
            ("学时", "hourglass", String(format: "%.1f", activity.classHour)),
            ("联系人", "phone", activity.mobile ?? ""),
        ]
        if let describe = activity.describe ?? lib?.describe, !describe.isEmpty {
            Text(describe)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { label, icon, value in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(value.isEmpty ? "—" : value)
                        .font(.footnote)
                }
            }
        }
    }

    private func scoreTypeSheet(_ scoreTypes: [CyclScoreType]) -> some View {
        NavigationStack {
            List {
                ForEach(scoreTypes) { type in
                    Button {
                        scoreTypePicker = nil
                        Task { await performSignUp(type) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name)
                                .foregroundStyle(.primary)
                            Text("当前值: \(type.value)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择希望提升的能力类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        scoreTypePicker = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - 报名流程

    private func toggleSignUp() async {
        guard !actionLoading else { return }
        if signedUp {
            actionLoading = true
            defer { actionLoading = false }
            do {
                try await api.cancelSignUp(activityId: activityId)
                signedUp = false
                toastMessage = "取消报名成功"
            } catch {
                toastMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
            }
        } else {
            actionLoading = true
            defer { actionLoading = false }
            do {
                guard let libId = detail?.activity.activityLibraryId ?? detail?.activityLib?.activityLibraryId,
                      !libId.isEmpty else {
                    toastMessage = "操作失败"
                    return
                }
                let scoreTypes = try await api.getActivityScoreTypes(activityLibraryId: libId)
                if scoreTypes.isEmpty {
                    toastMessage = "暂无能力类型"
                    return
                }
                scoreTypePicker = scoreTypes
            } catch {
                toastMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
            }
        }
    }

    private func performSignUp(_ type: CyclScoreType) async {
        actionLoading = true
        defer { actionLoading = false }
        do {
            try await api.signUpActivity(activityId: activityId, scoreType: type.code ?? "")
            signedUp = true
            toastMessage = "报名成功"
        } catch {
            toastMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        }
    }

    private func load() async {
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            let d = try await api.getActivityDetail(activityId: activityId)
            detail = d
            signedUp = d.signUp
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - 成绩单（credit_list_page.dart）

struct CcylCreditListPage: View {
    let api: CcylApiService

    @State private var credits: [CyclCredit] = []
    @State private var pageNum = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selecting = false
    @State private var selectedIds = Set<String>()
    @State private var showEmailDialog = false
    @State private var emailText = ""
    @State private var toastMessage: String?
    @State private var exporting = false

    /// 按积分类型聚合学时
    private var statsByType: [(String, Double)] {
        var stats: [String: Double] = [:]
        for credit in credits {
            stats[credit.scoreTypeName, default: 0] += credit.classHour
        }
        return stats.sorted { $0.key < $1.key }
    }

    var body: some View {
        Group {
            if let errorMessage, credits.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(loadMore: false) } }
                }
            } else {
                list
            }
        }
        .task {
            if credits.isEmpty {
                await load(loadMore: false)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
        .sheet(isPresented: $showEmailDialog) {
            emailSheet
        }
    }

    private var list: some View {
        List {
            if !statsByType.isEmpty {
                Section("学时统计") {
                    ForEach(statsByType, id: \.0) { name, hours in
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(hours, specifier: "%.1f") 学时")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            Section {
                if !credits.isEmpty {
                    Button(selecting ? "取消选择" : "选择") {
                        selecting.toggle()
                        if !selecting { selectedIds.removeAll() }
                    }
                }
                if selecting, !credits.isEmpty {
                    Button(credits.count == selectedIds.count ? "取消全选" : "全选") {
                        if credits.count == selectedIds.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(credits.map(\.id))
                        }
                    }
                    Button {
                        showEmailDialog = true
                    } label: {
                        Label("导出到邮箱", systemImage: "envelope")
                    }
                    .disabled(selectedIds.isEmpty || exporting)
                }
            }
            Section {
                ForEach(credits) { credit in
                    creditRow(credit)
                }
                if hasMore {
                    Button("加载更多") {
                        Task { await load(loadMore: true) }
                    }
                    .disabled(isLoading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load(loadMore: false) }
    }

    private func creditRow(_ credit: CyclCredit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if selecting {
                Image(systemName: selectedIds.contains(credit.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(credit.id) ? Color.accentColor : Color(.systemGray3))
                    .onTapGesture { toggleSelection(credit.id) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(credit.activityName)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(credit.scoreTypeName)
                    Text("\(credit.classHour, specifier: "%.1f") 学时")
                    Text(credit.creditStatusName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(credit.createTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting { toggleSelection(credit.id) }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private var emailSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("请输入接收成绩单的QQ邮箱", text: $emailText)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("QQ邮箱")
                }
                Section {
                    Button {
                        let email = emailText.trimmingCharacters(in: .whitespaces)
                        guard !email.isEmpty else { return }
                        showEmailDialog = false
                        Task { await exportTo(email) }
                    } label: {
                        if exporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("确定")
                        }
                    }
                    .disabled(exporting || emailText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("导出到邮箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showEmailDialog = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exportTo(_ email: String) async {
        exporting = true
        defer { exporting = false }
        do {
            let message = try await api.exportCreditsToEmail(creditIds: Array(selectedIds), email: email)
            toastMessage = message
            selecting = false
            selectedIds.removeAll()
        } catch {
            toastMessage = (error as? LocalizedError)?.errorDescription ?? "导出失败"
        }
    }

    private func load(loadMore: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = loadMore ? pageNum + 1 : 1
            let results = try await api.getCreditList(pageNum: page)
            if loadMore {
                credits += results
                pageNum = page
            } else {
                credits = results
                pageNum = 1
            }
            hasMore = results.count >= 10
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
