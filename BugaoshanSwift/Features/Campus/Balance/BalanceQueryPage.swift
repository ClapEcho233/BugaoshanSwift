import SwiftUI
import Charts

/// 电费查询页（对应 balance_query_page.dart + 趋势）：绑定房间 + 余额 + 历史趋势
struct BalanceQueryPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @AppStorage("balance_room_school_code") private var schoolCode = ""
    @AppStorage("balance_room_reg_code") private var regCode = ""
    @AppStorage("balance_room_unit_code") private var unitCode = ""
    @AppStorage("balance_room_no") private var roomNo = ""
    @AppStorage("balance_room_school_name") private var schoolName = ""
    @AppStorage("balance_room_reg_name") private var regName = ""
    @AppStorage("balance_room_unit_name") private var unitName = ""
    @AppStorage("balance_room_cus_no") private var cusNo = ""
    @AppStorage("balance_room_cus_name") private var cusName = ""
    @AppStorage("balance_room_type") private var roomType = 0

    @State private var roomInfo: PayAppApiService.RoomInfo?
    @State private var history: [BalanceRecord] = []
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?
    @State private var showBindSheet = false

    private var api: PayAppApiService {
        PayAppApiService(auth: environment.payappAuth)
    }

    private var isBound: Bool { !cusNo.isEmpty }

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
            } else if isLoading && roomInfo == nil {
                ProgressView("查询中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else {
                balanceContent
            }
        }
        .navigationTitle("电费查询")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重新绑定") { showBindSheet = true }
                    Button(role: .destructive) {
                        unbind()
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
                await load()
            }
        }
        .refreshable {
            await load()
        }
        .sheet(isPresented: $showBindSheet) {
            NavigationStack {
                BindRoomDialog(
                    api: api,
                    initial: BindState(
                        schoolCode: schoolCode, regCode: regCode, unitCode: unitCode,
                        roomNo: roomNo, schoolName: schoolName, regName: regName,
                        unitName: unitName, cusName: cusName, roomType: roomType
                    )
                ) { bound in
                    schoolCode = bound.schoolCode
                    regCode = bound.regCode
                    unitCode = bound.unitCode
                    roomNo = bound.roomNo
                    schoolName = bound.schoolName
                    regName = bound.regName
                    unitName = bound.unitName
                    cusNo = bound.cusNo
                    cusName = bound.cusName
                    roomType = bound.roomType
                    showBindSheet = false
                    Task { await load() }
                }
            }
        }
    }

    private var balanceContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let info = roomInfo {
                    // 余额卡
                    VStack(spacing: 8) {
                        Text("当前余额")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", info.balance))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(info.balance < 10 ? .red : .primary)
                        Text("\(info.schoolName) \(info.regName) \(info.unitName) \(info.roomNo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if info.price > 0 {
                            Text(String(format: "单价 %.4f 元/度", info.price))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

                    // 趋势图
                    if history.count >= 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("余额趋势")
                                .font(.headline)
                            Chart(history, id: \.timestamp) { record in
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
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .frame(height: 180)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }

                    // 统计
                    if history.count >= 2, let first = history.first, let last = history.last,
                       last.balance < first.balance {
                        let consumed = first.balance - last.balance
                        HStack {
                            statBlock("期间用量", String(format: "%.2f 度", consumed / max(roomInfo?.price ?? 1, 0.0001)))
                            statBlock("期间电费", String(format: "%.2f 元", consumed))
                        }
                    }

                    // 原始记录
                    VStack(alignment: .leading, spacing: 6) {
                        Text("采样记录（\(history.count)）")
                            .font(.headline)
                        ForEach(history.suffix(20).reversed(), id: \.timestamp) { record in
                            HStack {
                                Text(BeijingTime.format(record.date, pattern: "MM-dd HH:mm"))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f 元", record.balance))
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
            let info = try await api.queryRoomInfo(cusNo: cusNo, type: roomType, cusName: cusName)
            roomInfo = info
            errorMessage = nil
            // 采样入库（type=0 电；北京时间今日已采样则跳过）
            let todayStart = BeijingTime.startOfTodayUtc().timeIntervalSince1970 * 1000
            let existing = try await environment.database.getBalanceRecords(
                roomKey: roomKey, balanceType: 0, since: Int64(todayStart))
            if existing.isEmpty {
                try await environment.database.insertBalanceRecord(BalanceRecord(
                    id: nil,
                    roomKey: roomKey,
                    balanceType: 0,
                    timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                    balance: info.balance,
                    price: info.price
                ))
            }
            history = try await environment.database.getBalanceRecords(roomKey: roomKey, balanceType: 0)
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var roomKey: String {
        "\(schoolCode)/\(regCode)/\(unitCode)/\(roomNo)"
    }

    private func unbind() {
        cusNo = ""
        roomNo = ""
        roomInfo = nil
        history = []
    }
}

// MARK: - 绑定对话框（校区→楼栋→单元→房间 级联）

struct BindState {
    var schoolCode: String
    var regCode: String
    var unitCode: String
    var roomNo: String
    var schoolName: String
    var regName: String
    var unitName: String
    var cusName: String
    var roomType: Int
    var cusNo: String = ""
}

struct BindRoomDialog: View {
    let api: PayAppApiService
    let initial: BindState
    let onBound: (BindState) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var campuses: [PayAppApiService.Option] = []
    @State private var buildings: [PayAppApiService.Option] = []
    @State private var units: [PayAppApiService.Option] = []
    @State private var state: BindState
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(api: PayAppApiService, initial: BindState, onBound: @escaping (BindState) -> Void) {
        self.api = api
        self.initial = initial
        self.onBound = onBound
        _state = State(initialValue: initial)
    }

    var body: some View {
        Form {
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
                Picker("单元", selection: $state.unitCode) {
                    Text(state.unitCode.isEmpty ? "请先选楼栋" : "请选择").tag("")
                    ForEach(units) { Text($0.name).tag($0.code) }
                }
                .disabled(state.regCode.isEmpty)
                TextField("房间号", text: $state.roomNo)
                    .keyboardType(.numbersAndPunctuation)
                TextField("户名（一般为学生姓名）", text: $state.cusName)
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
                .disabled(state.schoolCode.isEmpty || state.regCode.isEmpty
                    || state.unitCode.isEmpty || state.roomNo.isEmpty || state.cusName.isEmpty)
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
            campuses = (try? await api.fetchCampuses()) ?? []
            if !state.schoolCode.isEmpty {
                buildings = (try? await api.fetchBuildings(schoolCode: state.schoolCode)) ?? []
            }
            if !state.regCode.isEmpty {
                units = (try? await api.fetchUnits(schoolCode: state.schoolCode, regCode: state.regCode)) ?? []
            }
        }
        .onChange(of: state.schoolCode) { code in
            state.regCode = ""
            state.unitCode = ""
            buildings = []
            units = []
            Task {
                buildings = (try? await api.fetchBuildings(schoolCode: code)) ?? []
            }
        }
        .onChange(of: state.regCode) { code in
            state.unitCode = ""
            units = []
            Task {
                units = (try? await api.fetchUnits(schoolCode: state.schoolCode, regCode: code)) ?? []
            }
        }
    }

    private func verify() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let cusNo = "\(state.schoolCode)-\(state.regCode)-\(state.unitCode)-\(state.roomNo)"
            let ok = try await api.verifyRoom(
                cusNo: cusNo, type: state.roomType, cusName: state.cusName,
                schoolCode: state.schoolCode, regCode: state.regCode,
                unitCode: state.unitCode, roomNo: state.roomNo
            )
            guard ok else {
                errorMessage = "房间验证失败：请核对位置、房间号与户名"
                return
            }
            state.cusNo = cusNo
            state.schoolName = campuses.first { $0.code == state.schoolCode }?.name ?? ""
            state.regName = buildings.first { $0.code == state.regCode }?.name ?? ""
            state.unitName = units.first { $0.code == state.unitCode }?.name ?? ""
            onBound(state)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
