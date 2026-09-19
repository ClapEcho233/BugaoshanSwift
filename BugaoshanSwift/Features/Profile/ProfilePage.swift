import SwiftUI

/// 校园功能聚合页（对应 campus_page.dart）：搜索 + 三节分组网格，
/// 功能卡玻璃小卡片（GlassEffectContainer 分组）。
struct CampusPage: View {
    @State private var searchText = ""

    private var filteredSections: [(title: String, items: [DockItem])] {
        DockRegistry.campusSections.map { section in
            let items = section.ids
                .compactMap(DockRegistry.item(id:))
                .filter { item in
                    searchText.isEmpty
                        || item.label.localizedCaseInsensitiveContains(searchText)
                }
            return (section.title, items)
        }
        .filter { !$0.items.isEmpty }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(filteredSections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)
                            .padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
                            ForEach(section.items, id: \.id) { item in
                                NavigationLink {
                                    PlaceholderFeaturePage(dockId: item.id)
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
        .navigationTitle("校园")
        .searchable(text: $searchText, prompt: "搜索功能")
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
            }

            Section("通用") {
                NavigationLink {
                    PlaceholderFeaturePage(dockId: "academic_calendar")
                } label: {
                    Label("校历", systemImage: "calendar.circle")
                }
            }

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
        .navigationTitle("我的")
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                ScuLoginPage()
                    .environmentObject(environment)
            }
        }
    }
}

/// 软件设置页（后续阶段补齐 ~40 项）
struct SoftwareSettingsPage: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        Form {
            Section("课表") {
                Toggle("显示周末", isOn: $config.showWeekend)
                VStack(alignment: .leading) {
                    HStack {
                        Text("行高")
                        Spacer()
                        Text("\(Int(config.courseRowHeight))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $config.courseRowHeight, in: 48...120, step: 1)
                }
            }
            Section("动画") {
                Toggle("页面切换动画", isOn: $config.enablePageTransitionAnimation)
            }
            Section("Dock") {
                Button("恢复默认 Dock") {
                    config.resetDockToDefault()
                }
            }
            Section("危险区") {
                Button(role: .destructive) {
                    // 清数据（后续阶段补确认对话框与全量清理）
                } label: {
                    Text("清除课表数据")
                }
                .disabled(true)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 关于页
struct AboutPage: View {
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("链接") {
                Link(destination: URL(string: Constants.officialWebsiteLink)!) {
                    Label("官方网站", systemImage: "globe")
                }
                Link(destination: URL(string: Constants.appLink)!) {
                    Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
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
