import SwiftUI
import Combine

/// 入口：AppEnvironment 构造 + 启动错误降级页（对应 main.dart 的 try/catch 壳）
@main
struct BugaoshanSwiftApp: App {
    @StateObject private var environment = AppEnvironment()
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            if let startupError = environment.startupError {
                StartupErrorView(message: startupError) {
                    environment.clearStartupError()
                    Task { await environment.bootstrap() }
                }
            } else {
                RootView()
                    .environmentObject(environment)
                    .environmentObject(environment.config)
                    .environmentObject(environment.authBus)
                    .environmentObject(theme)
                    .task {
                        if environment.startupError == nil {
                            await environment.bootstrap()
                        }
                    }
            }
        }
    }
}

/// 启动失败降级页
struct StartupErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Bugaoshan 启动失败")
                .font(.title2.bold())
            ScrollView {
                Text(message)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

/// 主题管理（三模式：system 退化为默认蓝 / custom 用户选色 / backgroundImage 取色——后续阶段补全）
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    enum Mode: String, CaseIterable {
        case system
        case custom
    }

    @Published var mode: Mode = .system
    @Published var customColor: Color = .blue

    var accentColor: Color? {
        switch mode {
        case .system: return nil
        case .custom: return customColor
        }
    }
}
