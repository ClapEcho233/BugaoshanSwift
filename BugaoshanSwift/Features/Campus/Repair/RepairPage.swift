import SwiftUI
import PhotosUI

/// 宿舍报修页（对应 repair_page.dart）：提交报修 / 我的工单 双 Tab
struct RepairPage: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $tab) {
                Text("提交报修").tag(0)
                Text("我的工单").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 {
                RepairSubmitTab()
            } else {
                RepairMyTicketsTab()
            }
        }
        .navigationTitle("宿舍报修")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 提交报修

struct RepairSubmitTab: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var addresses: [RepairAddress] = []
    @State private var areas: [RepairAreaNode] = []
    @State private var projectsByArea: [String: [RepairProject]] = [:]
    @State private var selectedAddressId = ""
    @State private var selectedAreaId = ""
    @State private var selectedProjectId = ""
    @State private var description = ""
    @State private var phone = ""
    @State private var bookDates: [String] = []
    @State private var bookDate = ""
    @State private var bookTimes: [String] = []
    @State private var bookTime = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var uploadedPaths: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var api: ZhhqApiService {
        ZhhqApiService(auth: environment.zhhqAuth)
    }

    var body: some View {
        Form {
            addressSection
            projectSection
            descriptionSection
            bookTimeSection
            imageSection
            messageSection
            submitSection
        }
        .refreshable {
            await loadInitial()
        }
        .task {
            if addresses.isEmpty {
                await loadInitial()
            }
        }
        .onChange(of: pickedItems) { items in
            Task { await uploadImages(items) }
        }
        .onChange(of: selectedArea) { area in
            Task {
                guard let area, projectsByArea[area.id] == nil else { return }
                projectsByArea[area.id] = (try? await api.fetchProjects(areaId: area.id)) ?? []
                selectedProjectId = ""
            }
        }
    }


    @ViewBuilder
    private var addressSection: some View {
        Section("报修地址") {
            if addresses.isEmpty {
                Text(addressPlaceholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("地址", selection: $selectedAddressId) {
                    ForEach(addresses) { address in
                        Text(address.displayName).tag(address.id)
                    }
                }
            }
        }
    }

    private var addressPlaceholder: String {
        if isLoading { return "加载中…" }
        if let errorMessage { return errorMessage }
        return "暂无常用地址，请下拉刷新"
    }

    private var projectSection: some View {
        Section("维修项目") {
            Picker("区域", selection: $selectedAreaId) {
                Text("请选择").tag("")
                ForEach(flatAreas) { area in
                    Text(area.fullName).tag(area.id)
                }
            }
            Picker("项目", selection: $selectedProjectId) {
                Text("请选择").tag("")
                ForEach(leafProjects) { project in
                    Text(project.label).tag(project.value)
                }
            }
            .disabled(selectedAreaId.isEmpty)
        }
    }

    private var descriptionSection: some View {
        Section("故障描述") {
            TextField("联系电话", text: $phone)
                .keyboardType(.phonePad)
            TextEditor(text: $description)
                .frame(minHeight: 90)
        }
    }

    private var bookTimeSection: some View {
        Section("预约时间") {
            Picker("日期", selection: $bookDate) {
                Text("不预约").tag("")
                ForEach(bookDates, id: \.self) { date in
                    Text(date).tag(date)
                }
            }
            Picker("时段", selection: $bookTime) {
                Text("不限").tag("")
                ForEach(bookTimes, id: \.self) { time in
                    Text(time).tag(time)
                }
            }
            .disabled(bookDate.isEmpty)
        }
    }

    private var imageSection: some View {
        Section("图片（最多 3 张）") {
            PhotosPicker(selection: $pickedItems, maxSelectionCount: 3, matching: .images) {
                Label("选择图片", systemImage: "photo.on.rectangle")
            }
            if !uploadedPaths.isEmpty {
                Text("已上传 \(uploadedPaths.count) 张")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        if let successMessage {
            Section {
                Label(successMessage, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("提交报修")
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

    private var flatAreas: [RepairAreaNode] {
        areas.flatMap { [ $0 ] + $0.children }
    }

    private var selectedAddress: RepairAddress? {
        addresses.first { $0.id == selectedAddressId }
    }

    private var selectedArea: RepairAreaNode? {
        flatAreas.first { $0.id == selectedAreaId }
    }

    private var leafProjects: [RepairProject] {
        guard let area = selectedArea else { return [] }
        return (projectsByArea[area.id] ?? []).flatMap { [$0] + $0.children }
    }

    private var canSubmit: Bool {
        selectedAddress != nil && selectedArea != nil && !selectedProjectId.isEmpty
            && !description.isEmpty && !phone.isEmpty
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let addressesTask = api.fetchCommonAddresses()
            async let areasTask = api.fetchAreaTree()
            async let datesTask = api.fetchBookDates()
            let (loadedAddresses, loadedAreas, dates) = try await (addressesTask, areasTask, datesTask)
            addresses = loadedAddresses
            areas = loadedAreas
            bookDates = dates
            let preferred = loadedAddresses.first { $0.isCommon } ?? loadedAddresses.first
            selectedAddressId = preferred?.id ?? ""
            selectedAreaId = flatAreas.first { $0.id == preferred?.areaId }?.id ?? ""
            if phone.isEmpty {
                phone = selectedAddress?.phone ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadImages(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(3) {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let path = try? await api.uploadImage(
                data: data, mimeType: "image/jpeg", fileName: "photo.jpg") {
                uploadedPaths.append(path)
            }
        }
    }

    private func submit() async {
        guard let address = selectedAddress, let area = selectedArea,
              let project = leafProjects.first(where: { $0.value == selectedProjectId }) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 受理部门预取（可失败——后端兜底）
            let dept = try await api.fetchAcceptDept(areaId: area.id, projectId: project.value)
            var payload: [String: Any] = [
                "areaId": area.id,
                "areaName": address.areaName,
                "addressDetail": address.addressDetail,
                "phone": phone,
                "projectId": project.value,
                "projectName": project.label,
                "content": description,
                "systemCode": "newRepair",
            ]
            if let dept {
                payload["acceptDeptId"] = dept.deptId
                payload["acceptDeptName"] = dept.deptName
                payload["payName"] = dept.payName
            }
            if !bookDate.isEmpty {
                payload["bookDate"] = bookDate
                payload["bookTime"] = bookTime
            }
            if !uploadedPaths.isEmpty {
                payload["resourcesVOS"] = uploadedPaths.map { ["fileUrl": $0] }
            }
            try await api.submitTicket(payload: payload)
            successMessage = "提交成功"
            description = ""
            uploadedPaths = []
            pickedItems = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 我的工单

struct RepairMyTicketsTab: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var tickets: [RepairTicket] = []
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?

    private var api: ZhhqApiService {
        ZhhqApiService(auth: environment.zhhqAuth)
    }

    var body: some View {
        Group {
            if isLoading && tickets.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if let errorMessage, tickets.isEmpty {
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
            } else {
                List {
                    if tickets.isEmpty {
                        ContentUnavailableView("暂无工单", systemImage: "wrench.and.screwdriver")
                            .listRowBackground(Color.clear)
                    }
                    ForEach(tickets) { ticket in
                        NavigationLink {
                            RepairDetailPage(ticketId: ticket.activeId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ticket.projectName.isEmpty ? "报修工单" : ticket.projectName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(ticket.status)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(statusColor(ticket.status).opacity(0.12), in: Capsule())
                                        .foregroundStyle(statusColor(ticket.status))
                                }
                                if !ticket.content.isEmpty {
                                    Text(ticket.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(ticket.activeTime.isEmpty
                                     ? timestampText(ticket.createTime)
                                     : ticket.activeTime)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task {
            if tickets.isEmpty {
                await load()
            }
        }
        .refreshable {
            await load()
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "已关闭": return .gray
        case "待完工", "待处理": return .orange
        case "待评价": return .blue
        case "已撤回": return .red
        default: return .secondary
        }
    }

    private func timestampText(_ millis: Int) -> String {
        guard millis > 0 else { return "" }
        return BeijingTime.format(Date(timeIntervalSince1970: Double(millis) / 1000), pattern: "yyyy-MM-dd HH:mm")
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
            // userId 从常用地址取（getCommonAddress 返回带 userId）
            let addresses = try await api.fetchCommonAddresses()
            let userId = addresses.first?.userId ?? ""
            tickets = try await api.fetchMyTickets(userId: userId)
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 工单详情（时间线 + 撤回/评价）

struct RepairDetailPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    let ticketId: String

    @State private var detail: RepairTicketDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var canWithdraw = false
    @State private var showWithdrawConfirm = false
    @State private var evaluateProjects: [RepairEvaluateProject] = []
    @State private var showEvaluate = false
    @State private var evaluateContent = ""

    private var api: ZhhqApiService {
        ZhhqApiService(auth: environment.zhhqAuth)
    }

    var body: some View {
        Group {
            if let detail {
                List {
                    Section("工单信息") {
                        infoRow("报修编号", detail.serialNumber)
                        infoRow("项目", detail.projectName)
                        infoRow("状态", detail.status)
                        infoRow("区域", detail.areaName)
                        if !detail.address.isEmpty {
                            infoRow("地址", detail.address)
                        }
                        infoRow("受理部门", detail.acceptDeptName)
                        if !detail.bookTimeString.isEmpty {
                            infoRow("预约时间", detail.bookTimeString)
                        }
                        if !detail.content.isEmpty {
                            infoRow("描述", detail.content)
                        }
                    }
                    if !detail.logs.isEmpty {
                        Section("处理进度") {
                            ForEach(detail.logs) { log in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.statusName)
                                            .font(.subheadline.weight(.medium))
                                        if !log.content.isEmpty {
                                            Text(log.content)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if log.createTime > 0 {
                                            Text(BeijingTime.format(
                                                Date(timeIntervalSince1970: Double(log.createTime) / 1000),
                                                pattern: "yyyy-MM-dd HH:mm"))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    Section {
                        if canWithdraw {
                            Button(role: .destructive) {
                                showWithdrawConfirm = true
                            } label: {
                                Label("撤回工单", systemImage: "arrow.uturn.backward")
                            }
                        }
                        if detail.canEvaluate {
                            Button {
                                Task { await openEvaluate() }
                            } label: {
                                Label("评价", systemImage: "star")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
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
            } else {
                // 兜底：detail 为空且无错误时不留纯空白页
                ContentUnavailableView("暂无数据", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle("工单详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .confirmationDialog("撤回该工单？", isPresented: $showWithdrawConfirm, titleVisibility: .visible) {
            Button("撤回", role: .destructive) {
                Task {
                    try? await api.withdrawTicket(id: ticketId)
                    await load()
                }
            }
        }
        .sheet(isPresented: $showEvaluate) {
            NavigationStack {
                Form {
                    ForEach($evaluateProjects) { $project in
                        HStack {
                            Text(project.name)
                            Spacer()
                            Stepper("评分 \(project.star)", value: $project.star, in: 1...5)
                                .labelsHidden()
                            Text("\(project.star) 星")
                                .monospacedDigit()
                        }
                    }
                    Section("评价内容") {
                        TextEditor(text: $evaluateContent)
                            .frame(minHeight: 80)
                    }
                    Section {
                        Button("提交评价") {
                            Task {
                                try? await api.submitEvaluation(
                                    projects: evaluateProjects,
                                    content: evaluateContent,
                                    repairId: detail?.finishedInfoRepairId ?? ""
                                )
                                showEvaluate = false
                                await load()
                            }
                        }
                    }
                }
                .navigationTitle("评价工单")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showEvaluate = false }
                    }
                }
            }
        }
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await api.fetchTicketDetail(id: ticketId)
            errorMessage = nil
            canWithdraw = (try? await api.fetchWithdrawAllowed(id: ticketId)) ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openEvaluate() async {
        evaluateProjects = (try? await api.fetchEvaluateProjects()) ?? []
        evaluateContent = ""
        showEvaluate = true
    }
}
