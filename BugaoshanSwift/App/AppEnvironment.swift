import Foundation
import Combine
import SwiftUI

/// 手动 DI 容器（对应 lib/injection/injector.dart 的注册顺序）：
/// SharedPreferences → ScuAuth → 子系统认证 → AuthCoordinator → API 服务 → Provider。
/// 显式构造，保持与 Dart 版相同的依赖图与初始化顺序。
@MainActor
final class AppEnvironment: ObservableObject {

    let config: AppConfig
    let authBus: AuthBus
    let database: DatabaseService
    let authLogger: AuthLogger

    // L3 根认证
    let scuAuth: ScuAuth
    // L2 子系统
    let zhjwAuth: SsoRelayAuth
    let wfwAuth: WfwAuth
    let payappAuth: SsoRelayAuth
    let fitnessAuth: SsoRelayAuth
    let ccylAuth: CcylAuth
    let zhhqAuth: ZhhqAuth
    let serviceAuth: SsoRelayAuth
    let newserviceAuth: SsoRelayAuth
    let authCoordinator: AuthCoordinator

    /// 启动错误（构造/恢复失败时降级页展示）
    @Published var startupError: String?
    /// bootstrap 是否已执行（幂等保护：init 触发 + RootView task 兑底不双跑）
    private var didBootstrap = false

    func clearStartupError() {
        startupError = nil
    }

    init() {
        let logger = AuthLogger.shared
        logger.i("App", "boot: AppEnvironment.init")
        let bus = AuthBus()
        let defaults = UserDefaultsStore()
        let secure = KeychainStore()

        let ocr: @Sendable ([UInt8]) async -> String? = { bytes in
            // ddddocr CoreML 优先，旧质心模型回退
            if let r = DdddOcrRecognizer.recognize(imageData: Data(bytes)), !r.isEmpty {
                return r
            }
            guard let model = ScuOcrLite.loadBundledModel() else { return nil }
            var result: String?
            do {
                result = try ScuOcrLite.recognize(imageData: Data(bytes), model: model)
            } catch {
                result = nil
            }
            return result
        }

        let scuAuth = ScuAuth(
            secure: secure,
            defaults: defaults,
            log: logger,
            ocr: ocr,
            bus: bus
        )
        let zhjwAuth = SubsystemAuthFactory.zhjw(scuAuth: scuAuth, bus: bus)
        let wfwAuth = WfwAuth(scuAuth: scuAuth, bus: bus)
        let payappAuth = SubsystemAuthFactory.payapp(scuAuth: scuAuth, wfwAuth: wfwAuth, bus: bus)
        let fitnessAuth = SubsystemAuthFactory.fitness(scuAuth: scuAuth, bus: bus)
        let ccylAuth = CcylAuth(scuAuth: scuAuth, secure: secure, bus: bus)
        let zhhqAuth = ZhhqAuth(scuAuth: scuAuth, secure: secure, bus: bus)
        let serviceAuth = SubsystemAuthFactory.service(scuAuth: scuAuth, bus: bus)
        let newserviceAuth = SubsystemAuthFactory.newservice(scuAuth: scuAuth, bus: bus)
        let coordinator = AuthCoordinator(
            modules: [zhjwAuth, wfwAuth, payappAuth, fitnessAuth, ccylAuth, zhhqAuth, serviceAuth, newserviceAuth],
            log: logger
        )

        self.config = AppConfig()
        self.authBus = bus
        self.database = DatabaseService(log: logger)
        self.authLogger = logger
        self.scuAuth = scuAuth
        self.zhjwAuth = zhjwAuth
        self.wfwAuth = wfwAuth
        self.payappAuth = payappAuth
        self.fitnessAuth = fitnessAuth
        self.ccylAuth = ccylAuth
        self.zhhqAuth = zhhqAuth
        self.serviceAuth = serviceAuth
        self.newserviceAuth = newserviceAuth
        self.authCoordinator = coordinator

        // 会话过期 → AuthBus 供根视图弹提示
        Task {
            await scuAuth.setOnSessionExpired { [weak bus] in
                await MainActor.run { bus?.sessionExpiredTrigger += 1 }
            }
        }

        // 启动序列尽早起跑：与首帧渲染/场景建立重叠执行（DB 打开 + 认证恢复
        // 均为 IO 型等待，不占主线程）；依赖构造顺序不变，仅前移触发时机。
        // RootView.task 仍兑底调用（幂等，见 didBootstrap）。
        Task { await self.bootstrap() }
    }

    /// 启动序列（DB 打开 + 认证恢复）；失败降级。幂等：重复调用直接返回。
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        authLogger.i("App", "boot: bootstrap start")
        do {
            try await database.open()
            authLogger.i("App", "boot: db opened")
            await scuAuth.restoreFromStorage()
            await ccylAuth.restoreFromStorage()
            await zhhqAuth.restoreFromStorage()
            authLogger.i("App", "boot: auth restored")
            if await scuAuth.isReady {
                // 冷启动恢复后：预热子系统 + 拉取用户资料
                authCoordinator.warmUpAllInBackground()
                Task { await self.fetchUserInfo() }
            } else if await scuAuth.isAutoLoginEnabled {
                // token 过期/缺失 → 自动登录重建会话（对应 Dart HomePage._attemptAutoLogin：
                // 未登录即尝试 autoLogin，其内部自检开关与凭据），否则整个 app 静默未登录。
                // OCR 模型预热与验证码网络请求并行，模型首次加载不叠加在登录路径上。
                Task.detached(priority: .utility) { DdddOcrRecognizer.warmUp() }
                Task {
                    do {
                        if try await self.scuAuth.autoLogin() {
                            self.authCoordinator.warmUpAllInBackground()
                            await self.fetchUserInfo()
                        }
                    } catch {
                        self.authLogger.w("App", "cold-start autoLogin failed: \(error)")
                    }
                }
            }
        } catch {
            didBootstrap = false   // 允许降级页重试
            startupError = "启动失败：\(error.localizedDescription)"
            authLogger.e("App", "bootstrap failed: \(error)")
        }
    }

    /// 登出：清全部子系统 + UI 缓存
    func logout() async {
        await authCoordinator.invalidateAll()
        await ccylAuth.logout()
        await scuAuth.logout()
    }

    /// wfw 资料抓取 → AuthBus.realname/username + UserDefaults 缓存（冷启动立即可显示）
    func fetchUserInfo() async {
        guard await scuAuth.isReady else { return }
        let defaults = UserDefaults.standard
        // 冷启动先回填缓存
        if authBus.realname == nil {
            authBus.realname = defaults.string(forKey: StorageKeys.scuUserRealname)
        }
        let service = WfwApiService(auth: wfwAuth, log: authLogger)
        do {
            let profile = try await service.fetchUserProfile()
            authBus.realname = profile.realname.isEmpty ? authBus.realname : profile.realname
            if !profile.number.isEmpty {
                defaults.set(profile.number, forKey: StorageKeys.scuUserNumber)
                if authBus.username == nil {
                    authBus.username = profile.number
                }
            }
            if !profile.realname.isEmpty {
                defaults.set(profile.realname, forKey: StorageKeys.scuUserRealname)
            }
        } catch {
            authLogger.d("App", "fetchUserInfo failed: \(error)")
        }
    }
}
