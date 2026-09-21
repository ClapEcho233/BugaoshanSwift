import SwiftUI
import Charts

/// 余额类型常量，与 SCU 缴费平台 API 一致
/// （对应 Flutter 版 kBalanceTypeElectric / kBalanceTypeAc）
private enum BalanceType {
    /// 照明电费
    static let electric = 1
    /// 空调电费
    static let ac = 2
}

/// 房间绑定信息。
/// `cusNo` = 学号、`cusName` = 户名（真实姓名），均自动取自登录账号，
/// 与 Flutter 版 BindRoomDialog 一致，不询问用户（对应 bind_room_dialog.dart）。
private struct RoomBinding: Equatable {
    var schoolCode = ""
    var schoolName = ""
    var regCode = ""
    var regName = ""
    var unitCode = ""
    var unitName = ""
    var roomNo = ""
    var cusNo = ""
    var cusName = ""

    /// 房间标识：仅由房间属性构成，与 Flutter 版 _roomKeyFor 一致（下划线分隔）。
    /// 余额是房间维度的公共数据，历史记录按房间共享，不包含账号信息。
    var roomKey: String { "\(schoolCode)_\(regCode)_\(unitCode)_\(roomNo)" }

    var displayName: String {
        [schoolName, regName, unitName, roomNo].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// 电费查询页（对应 balance_query_page.dart + BalanceList）：
/// 绑定房间 + 照明/空调余额两张卡 + 历史趋势
struct BalanceQueryPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    // 绑定持久化。v2 语义：cusNo=学号、cusName=自动取自登录账号；
    // 旧格式（cusNo 为拼接房间串、type=0）一律视为未绑定。
    @AppStorage("balance_room_school_code") private var schoolCode = ""
    @AppStorage("balance_room_reg_code") private var regCode = ""
    @AppStorage("balance_room_unit_code") private var unitCode = ""
    @AppStorage("balance_room_no") private var roomNo = ""
    @AppStorage("balance_room_school_name") private var schoolName = ""
    @AppStorage("balance_room_reg_name") private var regName = ""
    @AppStorage("balance_room_unit_name") private var unitName = ""
    @AppStorage("balance_room_cus_no") private var cusNo = ""
    @AppStorage("balance_room_cus_name") private var cusName = ""
    @AppStorage("balance_binding_version") private var bindingVersion = 0

    @State private var infos: [Int: PayAppApiService.RoomInfo] = [:]
    @State private var errors: [Int: String] = [:]
    @State private var loadingTypes: Set<Int> = []
    @State private var needsLogin = false
    @State private var showBindSheet = false
    @State private var trendType = BalanceType.electric
    @State private var history: [BalanceRecord] = []
    /// 采样记录折叠：默认只展示最近几条，可展开全部
    @State private var recordsExpanded = false
    private let collapsedRecordCount = 5

    private var api: PayAppApiService {
        PayAppApiService(auth: environment.payappAuth)
    }

    private var binding: RoomBinding {
        RoomBinding(
            schoolCode: schoolCode, schoolName: schoolName,
            regCode: regCode, regName: regName,
            unitCode: unitCode, unitName: unitName,
            roomNo: roomNo, cusNo: cusNo, cusName: cusName
        )
    }

    private var isBound: Bool { bindingVersion >= 2 && !cusNo.isEmpty && !roomNo.isEmpty }

    /// 首次加载且尚无任何数据/错误时展示全屏 loading
    private var isInitialLoading: Bool {
        infos.isEmpty && errors.isEmpty
            && (loadingTypes.contains(BalanceType.electric) || loadingTypes.contains(BalanceType.ac))
    }

    var body: some View {
        Group {
            if !isBound {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("尚未绑定房间")
                        .font(.headline)
                    Text("绑定后可查看电费余额与用量趋势")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("绑定房间") { showBindSheet = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if isInitialLoading {
                ProgressView("查询中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                balanceContent
            }
        }
        .navigationTitle("电费查询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Text(binding.displayName)
                        Text("户名 \(cusName)")
                    }
                    Button("重新绑定") { showBindSheet = true }
                    Button(role: .destructive) {
                        Task { await unbind() }
                    } label: {
                        Text("解绑房间")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if isBound {
                await loadAll()
                await loadHistory()
            }
        }
        .refreshable {
            await loadAll()
            await loadHistory()
        }
        .sheet(isPresented: $showBindSheet) {
            NavigationStack {
                BindRoomDialog(api: api, initial: isBound ? binding : RoomBinding()) { bound in
                    save(bound)
                    showBindSheet = false
                    infos = [:]
                    errors = [:]
                    history = []
                    Task {
                        await loadAll()
                        await loadHistory()
                    }
                }
            }
        }
    }

    // MARK: - 内容

    private var balanceContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                BalanceCard(
                    title: "照明", icon: "bolt.fill", tint: .orange,
                    info: infos[BalanceType.electric],
                    isLoading: loadingTypes.contains(BalanceType.electric),
                    errorMessage: errors[BalanceType.electric]
                ) {
                    Task { await refresh(type: BalanceType.electric) }
                }

                BalanceCard(
                    title: "空调", icon: "snowflake", tint: .blue,
                    info: infos[BalanceType.ac],
                    isLoading: loadingTypes.contains(BalanceType.ac),
                    errorMessage: errors[BalanceType.ac]
                ) {
                    Task { await refresh(type: BalanceType.ac) }
                }

                trendSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var trendSection: some View {
        // 一次算齐全部绘图派生数据：SwiftUI 计算属性每次访问都会重算，
        // 若在 body 多处直接访问 chartData，同一帧内日聚合会重复执行多次，
        // 切换照明/空调时主线程阻塞导致掉帧。
        let data = trendDisplayData
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("余额趋势")
                    .font(.headline)
                Spacer()
                Picker("类型", selection: $trendType) {
                    Text("照明").tag(BalanceType.electric)
                    Text("空调").tag(BalanceType.ac)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }

            if data.points.count >= 2 {
                Chart(data.points, id: \.timestamp) { record in
                    LineMark(
                        x: .value("时间", record.date),
                        y: .value("余额", record.balance)
                    )
                    .foregroundStyle(Color.accentColor)
                    AreaMark(
                        x: .value("时间", record.date),
                        y: .value("余额", record.balance)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                .chartXScale(domain: data.domain)
                .chartXAxis {
                    AxisMarks(values: data.axisDates) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(BeijingTime.format(date, pattern: data.axisPattern))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)

                if let first = data.points.first, let last = data.points.last,
                   last.balance < first.balance {
                    let consumed = first.balance - last.balance
                    let price = infos[trendType]?.price ?? 0
                    HStack {
                        statBlock("期间用量", price > 0 ? String(format: "%.2f 度", consumed / price) : "—")
                        statBlock("期间电费", String(format: "%.2f 元", consumed))
                    }
                }
            } else {
                Text("趋势按日聚合（每日取最后一次查询结果），记录满 2 天后展示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("采样记录（\(history.count)）")
                            .font(.headline)
                        Spacer()
                        if history.count > collapsedRecordCount {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    recordsExpanded.toggle()
                                }
                            } label: {
                                Text(recordsExpanded ? "收起" : "展开全部（\(history.count)）")
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            // 文字宽度变化不参与动画，避免按钮被弹性压缩回弹
                            .transaction { $0.animation = nil }
                        }
                    }
                    ForEach(visibleRecords, id: \.timestamp) { record in
                        HStack {
                            Text(BeijingTime.format(record.date, pattern: "MM-dd HH:mm"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f 元", record.balance))
                                .font(.caption.monospacedDigit())
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: trendType) { _ in
            recordsExpanded = false
            Task { await loadHistory() }
        }
    }

    // MARK: - 趋势图派生数据

    /// 趋势图全部绘图输入，一次聚合生成，避免 body 求值期间重复计算
    private struct TrendDisplayData {
        /// 按北京日聚合的日代表点（每日取最后一条，对应 Flutter dailyPoints）
        var points: [BalanceRecord] = []
        /// 横轴坐标域：最小缩放 10 分钟 + 2% 呼吸边距
        var domain: ClosedRange<Date> = Date()...Date().addingTimeInterval(1)
        /// 横轴刻度：坐标域内均匀分布的内部时间点，标签不会超出图表边界
        var axisDates: [Date] = []
        /// 横轴标签格式：不足一天 HH:mm，否则 MM-dd
        var axisPattern: String = "MM-dd"
    }

    private var trendDisplayData: TrendDisplayData {
        let points = BalanceTrendMath.dailyPoints(from: history)
        guard let first = points.first?.date, let last = points.last?.date else {
            return TrendDisplayData(points: points)
        }
        let domain = BalanceTrendMath.domain(from: first, to: last)
        return TrendDisplayData(
            points: points,
            domain: domain,
            axisDates: BalanceTrendMath.axisDates(from: domain.lowerBound, to: domain.upperBound),
            axisPattern: BalanceTrendMath.axisPattern(span: last.timeIntervalSince(first))
        )
    }

    /// 采样记录列表：默认最近 5 条，展开后全部（新→旧）
    private var visibleRecords: [BalanceRecord] {
        let newestFirst = history.reversed()
        return recordsExpanded ? Array(newestFirst) : Array(newestFirst.prefix(collapsedRecordCount))
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 查询与采样（对应 balance_query_provider.dart _loadBalanceFor/_recordHistory）

    private func ensureAuthReady() async -> Bool {
        if environment.authBus.scuState == .ready { return true }
        return await environment.scuAuth.isReady
    }

    private func loadAll() async {
        guard await ensureAuthReady() else {
            needsLogin = true
            return
        }
        needsLogin = false
        // 并发查询照明（type=1）与空调（type=2）
        async let e: Void = refresh(type: BalanceType.electric)
        async let a: Void = refresh(type: BalanceType.ac)
        _ = await (e, a)
    }

    private func refresh(type: Int) async {
        guard await ensureAuthReady() else {
            needsLogin = true
            return
        }
        needsLogin = false
        loadingTypes.insert(type)
        defer { loadingTypes.remove(type) }
        do {
            let info = try await api.queryRoomInfo(cusNo: cusNo, type: type, cusName: cusName)
            infos[type] = info
            errors[type] = nil
            await record(info, type: type)
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errors[type] = error.localizedDescription
        }
    }

    /// 每次成功查询记录一条历史快照，保留 365 天（与 Flutter 版一致；失败不影响主流程）
    private func record(_ info: PayAppApiService.RoomInfo, type: Int) async {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let record = BalanceRecord(
            id: nil,
            roomKey: binding.roomKey,
            balanceType: type,
            timestamp: nowMs,
            balance: info.balance,
            price: info.price
        )
        do {
            try await environment.database.insertBalanceRecord(record)
            try await environment.database.deleteBalanceRecordsBefore(
                threshold: nowMs - 365 * 24 * 3600 * 1000)
        } catch {
            // 采样失败忽略
        }
    }

    private func loadHistory() async {
        history = (try? await environment.database.getBalanceRecords(
            roomKey: binding.roomKey, balanceType: trendType)) ?? []
    }

    // MARK: - 绑定持久化

    private func save(_ bound: RoomBinding) {
        schoolCode = bound.schoolCode
        regCode = bound.regCode
        unitCode = bound.unitCode
        roomNo = bound.roomNo
        schoolName = bound.schoolName
        regName = bound.regName
        unitName = bound.unitName
        cusNo = bound.cusNo
        cusName = bound.cusName
        bindingVersion = 2
    }

    private func unbind() async {
        let key = binding.roomKey
        schoolCode = ""; regCode = ""; unitCode = ""; roomNo = ""
        schoolName = ""; regName = ""; unitName = ""
        cusNo = ""; cusName = ""
        bindingVersion = 0
        infos = [:]
        errors = [:]
        history = []
        // 同步删除该房间的历史记录，避免残留（对应 removeBinding）
        try? await environment.database.deleteBalanceRecordsByRoom(roomKey: key)
    }
}

// MARK: - 余额卡（对应 balance_card.dart）

private struct BalanceCard: View {
    let title: String
    let icon: String
    let tint: Color
    let info: PayAppApiService.RoomInfo?
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if let info {
                Text(String(format: "%.2f", info.balance))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(info.balance < 10 ? .red : .primary)
                if info.price > 0 {
                    Text(String(format: "单价 %.4f 元/度", info.price))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if let errorMessage {
                VStack(spacing: 6) {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - 绑定对话框（对应 bind_room_dialog.dart：校区→楼栋→单元（可选）→房间号；
// 户名/学号自动取自登录账号，不询问用户）

private struct BindRoomDialog: View {
    let api: PayAppApiService
    let initial: RoomBinding
    let onBound: (RoomBinding) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var campuses: [PayAppApiService.Option] = []
    @State private var buildings: [PayAppApiService.Option] = []
    @State private var units: [PayAppApiService.Option] = []
    /// 已加载单元列表后为 true；区分「加载中」与「该楼栋未划分单元」
    @State private var unitsLoaded = false
    @State private var state: RoomBinding
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(api: PayAppApiService, initial: RoomBinding, onBound: @escaping (RoomBinding) -> Void) {
        self.api = api
        self.initial = initial
        self.onBound = onBound
        _state = State(initialValue: initial)
    }

    /// 学号：优先 wfw 档案缓存，回退登录账号
    private var accountNumber: String {
        UserDefaults.standard.string(forKey: StorageKeys.scuUserNumber)
            ?? environment.authBus.username ?? ""
    }

    /// 户名（真实姓名）：自动取自登录账号
    private var accountRealname: String {
        UserDefaults.standard.string(forKey: StorageKeys.scuUserRealname)
            ?? environment.authBus.realname ?? ""
    }

    /// 是否需要选择单元（楼栋未划分单元时允许为空，对应 Flutter _hasUnits=false）
    private var unitRequired: Bool { !unitsLoaded || !units.isEmpty }

    private var canSubmit: Bool {
        !state.schoolCode.isEmpty && !state.regCode.isEmpty && !state.roomNo.isEmpty
            && (!unitRequired || !state.unitCode.isEmpty)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    if accountRealname.isEmpty && accountNumber.isEmpty {
                        Text("正在获取账号信息…")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accountRealname.isEmpty ? "—" : accountRealname)
                            Text(accountNumber)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("缴费账户")
            } footer: {
                Text("户名与户号取自当前登录账号，房间需为本人寝室")
            }

            Section("位置") {
                Picker("校区", selection: $state.schoolCode) {
                    Text("请选择").tag("")
                    ForEach(campuses) { Text($0.name).tag($0.code) }
                }
                Picker("楼栋", selection: $state.regCode) {
                    Text(state.regCode.isEmpty ? "请先选校区" : "请选择").tag("")
                    ForEach(buildings) { Text($0.name).tag($0.code) }
                }
                .disabled(state.schoolCode.isEmpty)
                if unitRequired {
                    Picker("单元", selection: $state.unitCode) {
                        Text(state.unitCode.isEmpty ? "请先选楼栋" : "请选择").tag("")
                        ForEach(units) { Text($0.name).tag($0.code) }
                    }
                    .disabled(state.regCode.isEmpty)
                } else {
                    LabeledContent("单元", value: "未划分")
                }
                TextField("房间号", text: $state.roomNo)
                    .keyboardType(.numbersAndPunctuation)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await verify() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("验证并绑定")
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("绑定房间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task {
            // 冷启动档案未就绪时补拉一次（户名/学号来源）
            if accountRealname.isEmpty || accountNumber.isEmpty {
                await environment.fetchUserInfo()
            }
            campuses = (try? await api.fetchCampuses()) ?? []
            if !state.schoolCode.isEmpty {
                buildings = (try? await api.fetchBuildings(schoolCode: state.schoolCode)) ?? []
            }
            if !state.regCode.isEmpty {
                await loadUnits()
            }
        }
        .onChange(of: state.schoolCode) { code in
            state.regCode = ""
            state.unitCode = ""
            buildings = []
            units = []
            unitsLoaded = false
            Task {
                buildings = (try? await api.fetchBuildings(schoolCode: code)) ?? []
            }
        }
        .onChange(of: state.regCode) { _ in
            state.unitCode = ""
            units = []
            unitsLoaded = false
            Task { await loadUnits() }
        }
    }

    private func loadUnits() async {
        let loaded = (try? await api.fetchUnits(
            schoolCode: state.schoolCode, regCode: state.regCode)) ?? []
        units = loaded
        unitsLoaded = true
    }

    private func verify() async {
        guard !accountNumber.isEmpty else {
            errorMessage = "未获取到学号，请稍后重试或重新登录"
            return
        }
        guard !accountRealname.isEmpty else {
            errorMessage = "未获取到姓名，请稍后重试或重新登录"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 验证固定用照明（type=1），cusNo=学号、cusName=登录账号真实姓名
            let ok = try await api.verifyRoom(
                cusNo: accountNumber, type: BalanceType.electric, cusName: accountRealname,
                schoolCode: state.schoolCode, regCode: state.regCode,
                unitCode: state.unitCode, roomNo: state.roomNo
            )
            guard ok else {
                errorMessage = "房间验证失败：请核对位置与房间号"
                return
            }
            var bound = state
            bound.cusNo = accountNumber
            bound.cusName = accountRealname
            bound.schoolName = campuses.first { $0.code == state.schoolCode }?.name ?? ""
            bound.regName = buildings.first { $0.code == state.regCode }?.name ?? ""
            bound.unitName = units.first { $0.code == state.unitCode }?.name ?? ""
            onBound(bound)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
