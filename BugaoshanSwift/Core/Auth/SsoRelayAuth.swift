import Foundation

/// SSO 中继子系统认证基座（对应 lib/services/auth/sso_relay_auth.dart）：
/// 「子站凭据 = 跟随带 Bearer 的 SCU SSO URL，cookie 落在共享根 client 的 jar」。
///
/// 覆盖：zhjw / payapp / fitness / service / newservice（各自仅 URL 与错误文案不同）。
/// 根 client 对象身份变化（登出/换号/刷新后重建）→ 清缓存重新 SSO。
/// single-flight；isReady 仅为 UI 提示，业务必须走 getClient()。
actor SsoRelayAuth: SubsystemAuth {

    let moduleId: String
    let dependencies: [any SubsystemAuth]
    let ssoUrl: URL
    /// 登录失败时的错误文案（如「教务 SSO 登录失败」）
    let failureMessage: String

    private let scuAuth: ScuAuth
    private let log: AuthLogger
    private weak var bus: AuthBus?

    private var cachedClient: CookieClient?
    private var lastScuClient: CookieClient?
    private var loginTask: Task<CookieClient, Error>?
    private var loginToken: UUID?
    private(set) var isReady = false

    init(
        moduleId: String,
        ssoUrl: URL,
        dependencies: [any SubsystemAuth] = [],
        scuAuth: ScuAuth,
        failureMessage: String? = nil,
        log: AuthLogger = .shared,
        bus: AuthBus? = nil
    ) {
        self.moduleId = moduleId
        self.ssoUrl = ssoUrl
        self.dependencies = dependencies
        self.scuAuth = scuAuth
        self.failureMessage = failureMessage ?? "\(moduleId) SSO 中继失败"
        self.log = log
        self.bus = bus
    }

    // MARK: - 核心流程

    func getClient() async throws -> CookieClient {
        try await ensureAuthDependencies(dependencies)
        let scuClient = try await scuAuth.getClient()

        // 根 client 更换 → 清缓存 + 重新 SSO
        if scuClient !== lastScuClient {
            cachedClient = nil
            loginTask = nil
            loginToken = nil
            lastScuClient = scuClient
        }
        if let cached = cachedClient {
            return cached
        }
        if let task = loginTask {
            return try await task.value
        }
        log.d(moduleId.uppercased(), "SSO relay: starting")
        let task = Task { try await self.doLogin(scuClient) }
        let token = UUID()
        loginTask = task
        loginToken = token
        defer {
            if loginToken == token {
                loginTask = nil
                loginToken = nil
            }
        }
        return try await task.value
    }

    private func doLogin(_ scuClient: CookieClient) async throws -> CookieClient {
        let token = try await scuAuth.getAccessToken()
        let resp = try await scuClient.followRedirects(
            to: ssoUrl,
            headers: [
                "Accept": "text/html,application/xhtml+xml,*/*",
                "User-Agent": Constants.userAgent,
                "Authorization": "Bearer \(token)",
            ]
        )
        if resp.statusCode == 401 || resp.statusCode == 403 {
            log.w(moduleId.uppercased(), "SSO relay: rejected (\(resp.statusCode))")
            throw SCUError.unauthenticated()
        }
        if resp.statusCode < 200 || resp.statusCode >= 400 {
            log.w(moduleId.uppercased(), "SSO relay: HTTP \(resp.statusCode)")
            throw SCUError.service(failureMessage, statusCode: resp.statusCode)
        }
        // 与 Dart 版一致：成功后缓存的即共享根 client（子站 cookie 已在其 jar 内）
        cachedClient = scuClient
        if !isReady {
            isReady = true
            if let bus {
                let id = moduleId
                Task { @MainActor in bus.subsystemReady[id] = true }
            }
        }
        log.i(moduleId.uppercased(), "SSO relay: ok")
        return scuClient
    }

    // MARK: - SubsystemAuth

    func ensureAuthenticated() async throws {
        _ = try await getClient()
    }

    func invalidate() async {
        cachedClient = nil
        loginTask = nil
        loginToken = nil
        lastScuClient = nil
        isReady = false
        if let bus {
            let id = moduleId
            Task { @MainActor in bus.subsystemReady[id] = false }
        }
    }
}

// MARK: - 各子系统配置（URL 与 Dart 版逐字一致）

enum SubsystemAuthFactory {

    static func zhjw(scuAuth: ScuAuth, log: AuthLogger = .shared, bus: AuthBus? = nil) -> SsoRelayAuth {
        SsoRelayAuth(
            moduleId: "zhjw",
            ssoUrl: URL(string: "https://id.scu.edu.cn/enduser/sp/sso/scdxplugin_jwt23?enterpriseId=scdx&target_url=index")!,
            scuAuth: scuAuth,
            failureMessage: "教务 SSO 登录失败",
            log: log, bus: bus
        )
    }

    static func payapp(
        scuAuth: ScuAuth, wfwAuth: WfwAuth,
        log: AuthLogger = .shared, bus: AuthBus? = nil
    ) -> SsoRelayAuth {
        SsoRelayAuth(
            moduleId: "payapp",
            ssoUrl: URL(string: "https://payapp.scu.edu.cn/eleFees/oauth/airWarrant")!,
            dependencies: [wfwAuth],
            scuAuth: scuAuth,
            log: log, bus: bus
        )
    }

    static func fitness(scuAuth: ScuAuth, log: AuthLogger = .shared, bus: AuthBus? = nil) -> SsoRelayAuth {
        SsoRelayAuth(
            moduleId: "fitness",
            ssoUrl: URL(string: "https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php/index/login/scuMsLogin")!,
            scuAuth: scuAuth,
            log: log, bus: bus
        )
    }

    static func service(scuAuth: ScuAuth, log: AuthLogger = .shared, bus: AuthBus? = nil) -> SsoRelayAuth {
        SsoRelayAuth(
            moduleId: "service",
            ssoUrl: URL(string: "https://service.scu.edu.cn/api/login/main?redirect_url=https%3A%2F%2Fservice.scu.edu.cn%2Fv2%2Fmatter%2F")!,
            scuAuth: scuAuth,
            log: log, bus: bus
        )
    }

    static func newservice(scuAuth: ScuAuth, log: AuthLogger = .shared, bus: AuthBus? = nil) -> SsoRelayAuth {
        // 注意：platform_id=31 出现两次是有意为之（对齐浏览器行为）
        SsoRelayAuth(
            moduleId: "newservice",
            ssoUrl: URL(string: "https://service.scu.edu.cn/newservice/api/login/cas?redirect_url=https%3A%2F%2Fservice.scu.edu.cn%2Fnewservice%2Ffe%2Fsite%2Fm_passpoint%3Fplatform_id%3D31%26platform_id%3D31")!,
            scuAuth: scuAuth,
            log: log, bus: bus
        )
    }
}
