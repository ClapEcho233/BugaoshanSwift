import SwiftUI

/// 校园网无感认证页（对应 passpoint_page.dart）：账户卡（隐私打码）+
/// 设备列表 + 添加/取消设备。绑定 MAC 后接入校园网自动通过认证。
struct PasspointPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var devices: [PasspointDevice] = []
    @State private var userInfo: PasspointUserInfo?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var needsLogin = false
    @State private var loadErrorMessage: String?
    @State private var operationMessage: String?
    @State private var cancellingMac: String?
    @State private var pendingCancel: PasspointDevice?
    @State private var showAddSheet = false
    @State private var privacyHidden = true

    private var api: NewServiceApiService {
        NewServiceApiService(auth: environment.newserviceAuth)
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else {
                list
            }
        }
        .navigationTitle("无感认证")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .overlay(alignment: .bottom) {
            if hasLoaded && devices.isEmpty && loadErrorMessage == nil && !isLoading {
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加无感设备", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PasspointAddSheet(api: api) {
                Task { await load(force: true) }
            }
        }
        .confirmationDialog(
            "取消无感认证",
            isPresented: Binding(
                get: { pendingCancel != nil },
                set: { if !$0 { pendingCancel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("取消无感认证", role: .destructive) {
                if let device = pendingCancel {
                    Task { await cancel(device) }
                }
            }
            Button("取消", role: .cancel) { pendingCancel = nil }
        } message: {
            Text("确定要取消该设备的无感认证吗？\nMAC 地址: \(pendingCancel?.userMac ?? "")")
        }
        .alert(
            "操作结果",
            isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(operationMessage ?? "")
        }
        .task {
            if !hasLoaded {
                await load(force: false)
            }
        }
        .refreshable {
            await load(force: true)
        }
    }

    private var list: some View {
        List {
            if let loadErrorMessage {
                Section {
                    Label(loadErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let userInfo {
                Section("用户信息") {
                    privacyRow("姓名", mask(userInfo.userName, visibleStart: 1))
                    privacyRow("学号", mask(userInfo.userId, visibleStart: 2, visibleEnd: 2))
                    if !userInfo.userGroupName.isEmpty {
                        LabeledContent("用户组", value: userInfo.userGroupName)
                    }
                    LabeledContent("账户状态") {
                        Label(userInfo.isOnline ? "在线" : "离线",
                              systemImage: userInfo.isOnline ? "circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(userInfo.isOnline ? Color.green : .secondary)
                    }
                }
            }

            Section("我的设备") {
                if devices.isEmpty {
                    if isLoading && !hasLoaded {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text("暂无数据")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(devices) { device in
                    PasspointDeviceRow(
                        device: device,
                        isCancelling: cancellingMac == device.userMac,
                        disabled: cancellingMac != nil
                    ) {
                        pendingCancel = device
                    }
                }
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加无感设备", systemImage: "plus.circle")
                }
                .disabled(isLoading && !hasLoaded)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func privacyRow(_ label: String, _ maskedValue: String) -> some View {
        Button {
            privacyHidden.toggle()
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(maskedValue)
                    .foregroundStyle(.secondary)
                Image(systemName: privacyHidden ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func mask(_ text: String, visibleStart: Int, visibleEnd: Int = 0) -> String {
        if privacyHidden {
            let count = text.count
            guard count > visibleStart + visibleEnd else { return String(repeating: "*", count: count) }
            let start = text.prefix(visibleStart)
            let end = visibleEnd > 0 ? text.suffix(visibleEnd) : ""
            return start + String(repeating: "*", count: count - visibleStart - visibleEnd) + end
        }
        return text
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
            let list = try await api.fetchDevices()
            // 账户信息失败不阻断列表展示（与 Flutter 容错一致）
            let user = try? await api.fetchUserInfo()
            devices = list
            userInfo = user ?? userInfo
            hasLoaded = true
            loadErrorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            loadErrorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func cancel(_ device: PasspointDevice) async {
        cancellingMac = device.userMac
        defer { cancellingMac = nil }
        do {
            try await api.cancelDevice(userMac: device.userMac)
            operationMessage = "操作成功"
            await load(force: true)
        } catch {
            operationMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        }
    }
}

/// 设备行：在线状态点 + MAC（等宽）+ 到期/出口 + 取消按钮
private struct PasspointDeviceRow: View {
    let device: PasspointDevice
    let isCancelling: Bool
    let disabled: Bool
    let onCancel: () -> Void

    private var expireText: String {
        guard let date = device.macExpireTime else { return "最长有效期6年" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.isOnline ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                    Text(device.userMac)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(device.isOnline ? "在线" : "离线") · 到期时间: \(expireText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let exitLabel = PasspointExit.label(for: device.defaultServiceName), !exitLabel.isEmpty,
                   !device.defaultServiceName.isEmpty {
                    Text("无感设备出口: \(exitLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onCancel) {
                if isCancelling {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "power")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.borderless)
            .disabled(disabled)
        }
        .padding(.vertical, 2)
    }
}

/// 添加无感设备弹窗：MAC（12 位大写十六进制）+ 有效期 0-365 天 + 出口
private struct PasspointAddSheet: View {
    let api: NewServiceApiService
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mac = ""
    @State private var expireText = "0"
    @State private var exitValue = ""
    @State private var submitting = false
    @State private var errorText: String?

    private var macIsValid: Bool {
        mac.count == 12 && mac.allSatisfy { $0.isHexDigit }
    }

    private var expireDays: Int? { Int(expireText.trimmingCharacters(in: .whitespaces)) }

    private var canSubmit: Bool {
        macIsValid && validExpireDays != nil && !submitting
    }

    private var validExpireDays: Int? {
        guard let days = expireDays, (0...365).contains(days) else { return nil }
        return days
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("MAC 地址", text: $mac)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .monospaced()
                        .onChange(of: mac) { _, newValue in
                            let filtered = String(newValue.uppercased().filter { $0.isHexDigit }.prefix(12))
                            if filtered != newValue {
                                mac = filtered
                            }
                        }
                    if !mac.isEmpty && !macIsValid {
                        Label("MAC 格式无效，需 12 位十六进制", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("MAC 地址")
                } footer: {
                    Text("示例：B8782EBDCE85")
                }

                Section {
                    TextField("绑定有效期（天）", text: $expireText)
                        .keyboardType(.numberPad)
                        .onChange(of: expireText) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(3))
                            if filtered != newValue {
                                expireText = filtered
                            }
                        }
                    if let days = expireDays, !(0...365).contains(days) {
                        Label("有效期需在 0-365 之间", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("绑定有效期")
                } footer: {
                    Text("0-365 天，0 表示最长有效期 6 年")
                }

                Section("无感设备出口") {
                    Picker("出口", selection: $exitValue) {
                        ForEach(PasspointExit.all) { exit in
                            Text(exit.label).tag(exit.value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Text("特别提醒：自助开通无感知设备（MAC）后设备将自动接入校园网，学生宿舍区域将自动计时，请谨慎选择！")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if submitting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("确定")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("添加无感设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard let days = validExpireDays else { return }
        submitting = true
        defer { submitting = false }
        do {
            try await api.addDevice(
                userMac: mac,
                macExpireTime: days,
                defaultServiceName: exitValue
            )
            dismiss()
            onSuccess()
        } catch {
            // 优先展示服务端具体文案（如「MAC 已绑定」）
            errorText = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        }
    }
}
