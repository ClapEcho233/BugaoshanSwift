import SwiftUI

// MARK: - 主题色设置（set_theme_color_page.dart）

struct SetThemeColorPage: View {
    @EnvironmentObject private var config: AppConfig

    static let presets: [(name: String, argb: Int)] = [
        ("川大蓝", 0xFF2196F3),
        ("松绿", 0xFF3FA796),
        ("竹青", 0xFF5AB8A8),
        ("绛紫", 0xFF8B7CF6),
        ("珊瑚", 0xFFE86A92),
        ("琥珀", 0xFFE8A33D),
        ("朱红", 0xFFE05D5D),
        ("墨灰", 0xFF536473),
    ]

    @State private var customColor: Color = .accentColor

    var body: some View {
        List {
            Section("预设") {
                Button {
                    config.themeColorARGB = 0
                } label: {
                    checkRow("跟随系统", color: Color.accentColor, selected: config.themeColorARGB == 0)
                }
                ForEach(Self.presets, id: \.name) { preset in
                    Button {
                        config.themeColorARGB = preset.argb
                    } label: {
                        checkRow(preset.name, color: preset.argb.argbColor,
                                 selected: config.themeColorARGB == preset.argb)
                    }
                }
            }
            Section("自定义") {
                ColorPicker("选择颜色", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        config.themeColorARGB = newValue.argbValue
                    }
            }
        }
        .navigationTitle("主题色")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if config.themeColorARGB != 0 {
                customColor = config.themeColorARGB.argbColor
            }
        }
    }

    private func checkRow(_ name: String, color: Color, selected: Bool) -> some View {
        HStack {
            Circle().fill(color).frame(width: 22, height: 22)
            Text(name).foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - Dock 设置（set_dock_page.dart）

/// 主 dock 项可见性与顺序
struct SetDockPage: View {
    @EnvironmentObject private var config: AppConfig

    /// 可放入主 dock 的候选（除固定项外的功能页）
    private var candidates: [DockItem] {
        DockRegistry.all.filter { item in
            ["course", "campus", "profile", "grades"].contains(item.id)
        }
    }

    var body: some View {
        List {
            Section("已启用（自上而下）") {
                ForEach(config.visibleDockIds, id: \.self) { id in
                    if let item = DockRegistry.item(id: id) {
                        dockRow(item)
                    }
                }
                .onMove { from, to in
                    config.visibleDockIds.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    let removable = offsets.filter { config.visibleDockIds[$0] != "course" && config.visibleDockIds[$0] != "profile" }
                    for index in removable.reversed() {
                        config.visibleDockIds.remove(at: index)
                    }
                }
            }
            Section("可添加") {
                let available = candidates.filter { !config.visibleDockIds.contains($0.id) }
                if available.isEmpty {
                    Text("全部已启用").foregroundStyle(.secondary)
                }
                ForEach(available, id: \.id) { item in
                    Button {
                        config.visibleDockIds.append(item.id)
                    } label: {
                        HStack {
                            Image(systemName: item.icon).foregroundStyle(item.accent.argbColor)
                            Text(item.label).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            Section {
                Button("恢复默认") {
                    config.resetDockToDefault()
                }
            }
        }
        .navigationTitle("Dock 设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
    }

    private func dockRow(_ item: DockItem) -> some View {
        HStack {
            Image(systemName: item.icon).foregroundStyle(item.accent.argbColor)
            Text(item.label)
            if item.id == "course" || item.id == "profile" {
                Text("固定").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 字体与语言（set_font_page.dart / set_language_page.dart）

struct SetFontPage: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        List {
            Picker("字体大小", selection: $config.fontScale) {
                Text("小").tag("small")
                Text("跟随系统").tag("")
                Text("大").tag("large")
            }
            .pickerStyle(.inline)
        }
        .navigationTitle("字体大小")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 语言切换（写入 AppleLanguages，重启后生效；覆盖 UI 文案经
/// Localizable.xcstrings 本地化，键为中文原文）
struct SetLanguagePage: View {
    @AppStorage("app_language") private var language = ""
    @State private var pendingRestart = false

    var body: some View {
        List {
            Picker("语言", selection: $language) {
                Text("跟随系统").tag("")
                Text("中文").tag("zh")
                Text("English").tag("en")
            }
            .pickerStyle(.inline)
            .onChange(of: language) { _, newValue in
                apply(newValue)
            }
            Section {
                Text("切换语言后需要重新启动 App 才能完全生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
        .alert("需要重启", isPresented: $pendingRestart) {
            Button("好", role: .cancel) {}
        } message: {
            Text("语言设置将在重新打开 App 后生效。")
        }
    }

    private func apply(_ value: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([value], forKey: "AppleLanguages")
        }
        pendingRestart = true
    }
}

// MARK: - 开发者页（dev_page.dart + auth_log_viewer_page.dart）

struct DevPage: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        List {
            Section("诊断") {
                NavigationLink {
                    AuthLogViewerPage()
                } label: {
                    Label("认证日志", systemImage: "doc.text.magnifyingglass")
                }
            }
            Section("关于本机") {
                LabeledContent("系统", value: UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                LabeledContent("设备", value: UIDevice.current.model)
                LabeledContent("语言", value: Locale.current.identifier)
            }
            Section {
                Button(role: .destructive) {
                    config.developerModeEnabled = false
                } label: {
                    Text("关闭开发者模式")
                }
            }
        }
        .navigationTitle("开发者")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 认证日志查看器：级别过滤 + 复制/清空
struct AuthLogViewerPage: View {
    @State private var logText = AuthLogger.shared.exportText()
    @State private var levelFilter = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("级别", selection: $levelFilter) {
                Text("全部").tag("")
                Text("W 警告").tag("W")
                Text("E 错误").tag("E")
            }
            .pickerStyle(.segmented)
            .padding(8)
            ScrollView {
                Text(filteredText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .navigationTitle("认证日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = filteredText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                Button(role: .destructive) {
                    AuthLogger.shared.clear()
                    logText = ""
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            logText = AuthLogger.shared.exportText()
        }
    }

    private var filteredText: String {
        guard !levelFilter.isEmpty else { return logText }
        let marker = "[\(levelFilter)]"
        return logText
            .components(separatedBy: "\n")
            .filter { $0.contains(marker) }
            .joined(separator: "\n")
    }
}

// MARK: - 更新检查（关于页内嵌）

struct UpdateCheckSection: View {
    @EnvironmentObject private var config: AppConfig

    @State private var isChecking = false
    @State private var resultMessage: String?
    @State private var updateURL: URL?

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Section("更新") {
            Toggle("包含预发布版", isOn: $config.includePrerelease)
            Button {
                Task { await check() }
            } label: {
                HStack {
                    if isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .disabled(isChecking)
            if let resultMessage {
                Text(resultMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let updateURL {
                Link(destination: updateURL) {
                    Label("前往下载页", systemImage: "arrow.up.right.square")
                }
            }
        }
        .alert("检查更新", isPresented: Binding(
            get: { resultMessage != nil && updateURL == nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func check() async {
        isChecking = true
        resultMessage = nil
        updateURL = nil
        defer { isChecking = false }
        do {
            let latest = try await UpdateChecker.fetchLatestVersion()
            if UpdateChecker.hasUpdate(currentVersion: currentVersion, latestVersion: latest) {
                resultMessage = "发现新版本 \(latest)"
                updateURL = URL(string: "https://github.com/\(UpdateChecker.githubRepo)/releases/latest")
                return
            }
            if config.includePrerelease {
                if let pre = try await UpdateChecker.fetchLatestPrerelease(),
                   UpdateChecker.isNewerPrerelease(pre, currentVersion: currentVersion, gitTag: "v\(currentVersion)") {
                    resultMessage = "发现预发布版 \(pre)"
                    updateURL = URL(string: "https://github.com/\(UpdateChecker.githubRepo)/releases")
                    return
                }
            }
            resultMessage = "已是最新版本（\(currentVersion)）"
        } catch {
            resultMessage = "检查失败：\(error.localizedDescription)"
        }
    }
}
