import SwiftUI

/// 校园网设备页（对应 network_device_page.dart）：在线设备列表 + 一键下线
struct NetworkDevicePage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var devices: [WfwApiService.NetworkDevice] = []
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?
    @State private var offliningDeviceId: String?
    @State private var confirmOffline: WfwApiService.NetworkDevice?

    private var api: WfwApiService {
        WfwApiService(auth: environment.wfwAuth)
    }

    var body: some View {
        Group {
            if isLoading && devices.isEmpty {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if needsLogin {
                ContentUnavailableView {
                    Label("未登录", systemImage: "person.badge.key")
                } description: {
                    Text("请先登录统一身份认证后查看在线设备")
                }
            } else if let errorMessage, devices.isEmpty {
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
                deviceList
            }
        }
        .navigationTitle("校园网设备")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if devices.isEmpty {
                await load()
            }
        }
        .refreshable {
            await load()
        }
        .confirmationDialog(
            confirmOffline.map { "下线 \($0.ip)？" } ?? "下线设备？",
            isPresented: Binding(get: { confirmOffline != nil }, set: { if !$0 { confirmOffline = nil } }),
            titleVisibility: .visible
        ) {
            Button("下线", role: .destructive) {
                if let device = confirmOffline {
                    confirmOffline = nil
                    Task { await offline(device) }
                }
            }
        }
    }

    private var deviceList: some View {
        List {
            if devices.isEmpty {
                ContentUnavailableView("当前无在线设备", systemImage: "wifi.router")
                    .listRowBackground(Color.clear)
            }
            ForEach(devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: deviceIcon(device))
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.ip)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if !device.mac.isEmpty {
                            Text("MAC \(device.mac)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !device.location.isEmpty {
                            Text(device.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if offliningDeviceId == device.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            confirmOffline = device
                        } label: {
                            Text("下线")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deviceIcon(_ device: WfwApiService.NetworkDevice) -> String {
        let raw = device.raw
        let terminalType = SafeJSON.string(raw["terminalType"] ?? raw["deviceType"]).lowercased()
        if terminalType.contains("pc") || terminalType.contains("computer") {
            return "desktopcomputer"
        }
        if terminalType.contains("pad") {
            return "ipad"
        }
        return "iphone"
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
            devices = try await api.fetchNetworkDevices()
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func offline(_ device: WfwApiService.NetworkDevice) async {
        offliningDeviceId = device.id
        defer { offliningDeviceId = nil }
        do {
            try await api.offlineDevice(deviceId: device.deviceId, ip: device.ip)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
