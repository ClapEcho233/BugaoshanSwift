import SwiftUI

/// 校园功能聚合页（对应 campus_page.dart）：三节分组网格，
/// 功能卡玻璃小卡片（GlassEffectContainer 分组）。
/// 大标题由页面内容承担（根级导航栏隐藏，见 MainTabView 注释），
/// 与课表页自绘头部模式一致，随内容滚动。
struct CampusPage: View {

    private var sections: [(title: String, items: [DockItem])] {
        DockRegistry.campusSections.map { section in
            (section.title, section.ids.compactMap(DockRegistry.item(id:)))
        }
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("校园")
                    .font(.largeTitle.bold())
                    .padding(.leading, 32)
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)
                            .padding(.leading, 32)
                            .padding(.trailing, 16)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
                            ForEach(section.items, id: \.id) { item in
                                NavigationLink {
                                    campusDestination(item.id)
                                } label: {
                                    CampusItemCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    /// 功能路由：已实现的走真页面，其余占位
    @ViewBuilder
    private func campusDestination(_ id: String) -> some View {
        switch id {
        case "grades":
            GradesPage()
        case "academic_calendar":
            AcademicCalendarPage()
        case "network_device":
            NetworkDevicePage()
        case "passpoint":
            PasspointPage()
        case "repair":
            RepairPage()
        case "balance_query":
            BalanceQueryPage()
        case "exam_plan":
            ExamPlanPage()
        case "fitness_test":
            FitnessTestPage()
        case "plan_completion":
            PlanCompletionPage()
        case "leave":
            ServiceHallPage()
        case "ccyl":
            CcylPage()
        case "zysc":
            WebViewNoticePage(
                url: URL(string: "https://zysc.scyol.com/fzysc/#/pages/tabbar/index")!,
                beautifyJSFileName: "volunteer_sichuan",
                title: "志愿四川"
            )
        default:
            PlaceholderFeaturePage(dockId: id)
        }
    }
}

struct CampusItemCard: View {
    let item: DockItem

    private var accent: Color { item.accent.argbColor }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            Text(item.label)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// 我的页（对应 profile_page.dart）：登录状态卡 + 用户信息 + 菜单
struct ProfilePage: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authBus: AuthBus

    @State private var showLogin = false

    private var isLoggedIn: Bool { authBus.scuState == .ready }

    var body: some View {
        List {
            // 大标题作为原生 Section header：随内容滚动、天然对齐列表
            // 内容边距（x=16），与 CampusPage 标题几何一致
            Section {
                if isLoggedIn {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authBus.realname ?? authBus.username ?? "已登录")
                                    .font(.headline)
                                Text(authBus.username ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await environment.logout() }
                            } label: {
                                Text("退出登录")
                                    .font(.footnote)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 44))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("未登录")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("登录后可使用校园功能")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("我的")
                    .font(.largeTitle.bold())
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
            }
            .headerProminence(.increased)

            Section("应用") {
                NavigationLink {
                    SoftwareSettingsPage()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                NavigationLink {
                    AboutPage()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                ScuLoginPage()
                    .environmentObject(environment)
            }
        }
    }
}

/// 软件设置页（software_setting_page.dart 全量入口）
struct SoftwareSettingsPage: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        List {
            Section("外观") {
                NavigationLink {
                    SetThemeColorPage()
                } label: {
                    Label("主题色", systemImage: "paintpalette")
                }
                NavigationLink {
                    SetFontPage()
                } label: {
                    Label("字体大小", systemImage: "textformat.size")
                }
                NavigationLink {
                    SetLanguagePage()
                } label: {
                    Label("语言", systemImage: "globe")
                }
            }
            Section("Dock") {
                NavigationLink {
                    SetDockPage()
                } label: {
                    Label("Dock 设置", systemImage: "square.grid.2x2")
                }
            }
            Section("动画") {
                Toggle("页面切换动画", isOn: $config.enablePageTransitionAnimation)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 关于页：版本号连点 5 次开启开发者模式；检查更新；开源致谢
struct AboutPage: View {
    @EnvironmentObject private var config: AppConfig

    @State private var versionTapCount = 0

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                    Text("不高山上")
                        .font(.title2.bold())
                    Text("iOS 原生重制版")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("版本 \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= 5 {
                                versionTapCount = 0
                                config.developerModeEnabled = true
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            UpdateCheckSection()

            Section("链接") {
                Link(destination: URL(string: Constants.officialWebsiteLink)!) {
                    Label("官方网站", systemImage: "globe")
                }
                Link(destination: URL(string: Constants.appLink)!) {
                    Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            if config.developerModeEnabled {
                Section("开发者") {
                    NavigationLink {
                        DevPage()
                    } label: {
                        Label("开发者选项", systemImage: "wrench.and.screwdriver")
                    }
                }
            }

            Section("开源致谢") {
                Text("本项目衍生自 The-Brotherhood-of-SCU/Bugaoshan（AGPL-3.0）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
