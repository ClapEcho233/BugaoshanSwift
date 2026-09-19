import SwiftUI

/// 三级启动门：EULA 门 → 首启向导 → 主界面。
/// 会话过期全局提示（5s 冷却）挂在这里（对应 SessionExpiredListener）。
struct RootView: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authBus: AuthBus

    @State private var showLogin = false
    @State private var lastExpiredNoticeAt = Date.distantPast

    var body: some View {
        Group {
            if config.acceptedEulaVersion < AppConfig.currentEulaVersion {
                EulaGatePage()
            } else if !config.firstLaunchWizardCompleted {
                WizardPage()
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                ScuLoginPage()
                    .environmentObject(environment)
            }
        }
        .onChange(of: authBus.sessionExpiredTrigger) { _ in
            let now = Date()
            guard now.timeIntervalSince(lastExpiredNoticeAt) > 5 else { return }
            lastExpiredNoticeAt = now
            showLogin = true
        }
    }
}

// MARK: - EULA 门（不能返回；不同意即退出）

struct EulaGatePage: View {
    @EnvironmentObject private var config: AppConfig
    @State private var agreed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                EulaContent()
                    .padding()
            }
            Divider()
            HStack {
                Button("不同意") {
                    exit(0)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("同意") {
                    config.acceptedEulaVersion = AppConfig.currentEulaVersion
                }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
            }
            .padding()
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) {
            // EULA 正文上方固定标题
            VStack(spacing: 4) {
                Text("最终用户许可协议")
                    .font(.headline)
                Toggle("我已阅读并同意以上协议", isOn: $agreed)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            .background(.bar)
        }
    }
}

/// EULA 正文（对应 assets/eula.md，简化渲染为纯文本段落）
struct EulaContent: View {
    private static let paragraphs: [String] = [
        "本应用（不高山上）是由四川大学学生自发组织的开源社区维护的校园助手工具，面向四川大学在校学生与教职工提供课表管理、成绩查询、校园服务聚合等便利功能。",
        "本应用与四川大学官方无关，所有数据均直接来源于学校官方系统（统一身份认证、教务处、微服务平台等），应用本身不运营任何后台服务器存储您的账号信息。",
        "您的统一身份认证凭据仅保存在您本人的设备安全存储中，用于在您授权范围内完成自动登录与数据获取。请妥善保管设备，避免账号信息泄露。",
        "本应用按「现状」提供，不对其可用性、准确性与适用性作任何保证。因学校系统变更导致的临时不可用，请理解并等待适配更新。",
        "继续使用即表示您已阅读、理解并同意本协议的全部内容。",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(Self.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                if index == 0 {
                    Divider()
                }
            }
        }
    }
}

// MARK: - 首启向导（欢迎 → 登录+导入 → 功能一览 → 开始使用）

struct WizardPage: View {
    @EnvironmentObject private var config: AppConfig
    @EnvironmentObject private var environment: AppEnvironment

    @State private var page = 0
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WizardWelcomePage().tag(0)
                WizardLoginImportPage(onLogin: { showLogin = true }).tag(1)
                WizardFeaturesPage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 底部控制：页点 + 按钮
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color(.systemGray4))
                        .frame(width: index == page ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 12)

            HStack {
                if page == 0 {
                    Button("跳过") {
                        config.firstLaunchWizardCompleted = true
                    }
                } else {
                    Button("上一页") {
                        withAnimation { page -= 1 }
                    }
                }
                Spacer()
                Button(page == 2 ? "开始使用" : "下一页") {
                    if page == 2 {
                        config.firstLaunchWizardCompleted = true
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                ScuLoginPage()
                    .environmentObject(environment)
            }
        }
    }
}

struct WizardWelcomePage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .frame(width: 96, height: 96)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.accentColor.opacity(0.2), radius: 24, y: 8)
            Text("不高山上")
                .font(.largeTitle.bold())
            Text("四川大学校园助手 · 原生重制版")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// 向导第 2 页：两步卡（登录 → 导入）
struct WizardLoginImportPage: View {
    @EnvironmentObject private var authBus: AuthBus

    let onLogin: () -> Void

    private var isLoggedIn: Bool { authBus.scuState == .ready }

    var body: some View {
        VStack(spacing: 16) {
            Text("开始之前")
                .font(.title2.bold())
                .padding(.top, 32)
            WizardStepCard(
                step: 1,
                title: "完成统一身份认证登录",
                subtitle: "使用学号与统一身份认证密码登录",
                done: isLoggedIn
            ) {
                onLogin()
            }
            WizardStepCard(
                step: 2,
                title: "从教务系统导入课表",
                subtitle: "登录后可一键导入本学期课表",
                done: false
            ) {
                // 导入入口在课表页（导入功能后续阶段接入）
            }
            .disabled(true)
            .opacity(0.5)
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct WizardStepCard: View {
    let step: Int
    let title: String
    let subtitle: String
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if done {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                            .bold()
                    } else {
                        Text("\(step)")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if done {
                            Text("完成")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct WizardFeaturesPage: View {
    private let features: [(icon: String, title: String, desc: String)] = [
        ("book", "课表", "多课表管理、教务导入、日历导出、桌面小组件"),
        ("graduationcap", "校园", "成绩、电费、报修、通知等 18 项校园服务"),
        ("person.crop.circle", "我的", "账号信息与个性化设置"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("功能一览")
                .font(.title2.bold())
                .padding(.top, 32)
            ForEach(features, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal)
    }
}
