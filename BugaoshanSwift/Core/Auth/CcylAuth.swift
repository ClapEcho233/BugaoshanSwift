import Foundation

// MARK: - CCYL（第二课堂）服务层最小集（登录用）

/// CCYL 用户
struct CcylUser: Equatable, Sendable, Codable {
    var id: String
    var userName: String
    var realname: String
    var orgName: String

    var isEmptyStub: Bool { id.isEmpty && userName.isEmpty && realname.isEmpty }
}

/// CcylService 静态 HTTP 层（对应 lib/services/ccyl/ccyl_service.dart 的登录部分）
struct CcylService {
    static let base = "https://dekt.scu.edu.cn"
    static let apiBase = "https://dekt.scu.edu.cn/ccyl-api"

    static let baseHeaders: [String: String] = [
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json;charset=UTF-8",
        "Origin": base,
        "Referer": base,
        "User-Agent": Constants.userAgent,
    ]

    struct LoginResult: Sendable {
        var token: String
        var user: CcylUser
    }

    /// POST /app/auth/loginByUc {"code": <oauth code>}
    /// 业务 code==401 → CcylError.authExpired；其他 code!=0 → CcylError.general(msg)
    static func login(code: String, transport: HTTPTransport) async throws -> LoginResult {
        let request = HTTPRequest(
            method: "POST",
            url: URL(string: "\(apiBase)/app/auth/loginByUc")!,
            headers: baseHeaders,
            body: try JSONSerialization.data(withJSONObject: ["code": code])
        )
        let resp: HTTPResponse
        do {
            resp = try await transport.request(request)
        } catch {
            throw CcylError.general("[loginByUc] 网络请求失败: \(error.localizedDescription)")
        }
        guard resp.statusCode == 200 else {
            throw CcylError.general("[loginByUc] HTTP 错误: \(resp.statusCode)")
        }
        let json = try? SafeJSON.parseObject(resp.bodyString, api: "loginByUc")
        guard let json else {
            throw CcylError.general("[loginByUc] 响应解析失败")
        }
        let code2 = SafeJSON.int(json["code"])
        if code2 == 401 {
            throw CcylError.authExpired
        }
        guard code2 == 0 else {
            throw CcylError.general(SafeJSON.string(json["msg"], fallback: "登录失败"))
        }
        let token = SafeJSON.string(json["token"])
        guard !token.isEmpty else {
            throw CcylError.general("登录响应缺少 token")
        }
        let userMap = json["user"] as? [String: Any]
        let user = CcylUser(
            id: SafeJSON.string(userMap?["id"]),
            userName: SafeJSON.string(userMap?["userName"]),
            realname: SafeJSON.string(userMap?["realname"]),
            orgName: SafeJSON.string(userMap?["orgName"])
        )
        return LoginResult(token: token, user: user)
    }
}

// MARK: - OAuth code 获取

/// 经 id.scu.edu.cn sp_logged 中继拿 CCYL OAuth code（对应 ccyl_oauth_service.dart）
struct CcylOAuthService {

    private static let reMetaRefresh = try! NSRegularExpression(
        pattern: #"<meta[^>]+http-equiv=["']refresh["'][^>]+content=["'][^;]+;\s*url=([^"'>\s]+)"#,
        options: [.caseInsensitive]
    )
    private static let reJsLocation = try! NSRegularExpression(
        pattern: #"window\.location(?:\.href)?\s*=\s*["']([^"']+)["']"#
    )

    /// 任何失败返回 nil
    static func getOAuthCode(scuAuth: ScuAuth) async -> String? {
        do {
            let token = try await scuAuth.getAccessToken()
            let client = try await scuAuth.getClient()
            let url = URL(string: "\(ScuAuth.base)/api/bff/v1.2/commons/sp_logged?access_token=\(token)&sp_code=\(Constants.ccylSpCode)&application_key=scdxplugin_cas_apereo17")!
            let resp = try await client.followRedirects(
                to: url,
                headers: [
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*",
                    "User-Agent": Constants.userAgent,
                ]
            )
            if resp.statusCode == 483 {
                AuthLogger.shared.w("CcylAuth", "sp_logged: 防火墙拦截 (483)")
                return nil
            }
            // (a) 最终 URL 的 code= 参数
            if let code = resp.queryItems["code"], !code.isEmpty {
                return code
            }
            // (b) 响应体中的跳转 URI（meta refresh / JS location）
            let body = resp.bodyString
            let range = NSRange(body.startIndex..., in: body)
            for regex in [reMetaRefresh, reJsLocation] {
                if let match = regex.firstMatch(in: body, range: range),
                   let r = Range(match.range(at: 1), in: body) {
                    let redirect = String(body[r])
                    if let comps = URLComponents(string: redirect),
                       let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                       !code.isEmpty {
                        return code
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - CcylAuth

/// CCYL 子系统认证（对应 lib/services/auth/ccyl_auth.dart）。
/// 独立 OAuth token 体系（无共享 cookie）；token 与 SCU principal 绑定，
/// 每次读取都校验绑定——不跨账号。
actor CcylAuth: SubsystemAuth {

    let moduleId = "ccyl"
    let dependencies: [any SubsystemAuth] = []

    private let scuAuth: ScuAuth
    private let secure: SecureStore
    private let transport: HTTPTransport
    private let log: AuthLogger
    private weak var bus: AuthBus?

    private var token: String?
    private var currentUserStorage: CcylUser?
    private var boundScuPrincipal: String?
    private var reLoginTask: Task<Void, Error>?
    private var reLoginToken: UUID?
    /// 代次（同 ScuAuth.authEpoch 语义）
    private var authGeneration = 0

    /// OAuth code 提供者（测试可注入）
    private let oauthCodeProvider: @Sendable () async -> String?

    init(
        scuAuth: ScuAuth,
        secure: SecureStore = KeychainStore(),
        transport: HTTPTransport = URLSessionTransport(),
        log: AuthLogger = .shared,
        bus: AuthBus? = nil,
        oauthCodeProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.scuAuth = scuAuth
        self.secure = secure
        self.transport = transport
        self.log = log
        self.bus = bus
        self.oauthCodeProvider = oauthCodeProvider ?? { await CcylOAuthService.getOAuthCode(scuAuth: scuAuth) }
    }

    // MARK: - 绑定校验（所有读取的门卫）

    private func boundToken() async -> String? {
        let principal = await scuAuth.principal
        guard let token, let boundScuPrincipal, boundScuPrincipal == principal else {
            return nil
        }
        return token
    }

    func tokenIfBound() async -> String? { await boundToken() }
    func isLoggedIn() async -> Bool { await boundToken() != nil }
    func user() async -> CcylUser? {
        guard await boundToken() != nil else { return nil }
        return currentUserStorage
    }

    // MARK: - 恢复

    /// 删除遗留键；ccyl_session_v2 仅在持久化 principal 与当前 SCU principal 一致时恢复
    func restoreFromStorage() async {
        await secure.delete(StorageKeys.ccylTokenLegacy)
        await secure.delete(StorageKeys.ccylUserIdLegacy)
        guard let raw = await secure.read(StorageKeys.ccylSession),
              let data = raw.data(using: .utf8),
              let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let persistedPrincipal = SafeJSON.string(session["scuPrincipal"])
        let principal = await scuAuth.principal
        if let principal, !persistedPrincipal.isEmpty, persistedPrincipal == principal {
            token = SafeJSON.string(session["token"])
            boundScuPrincipal = persistedPrincipal
            let userId = SafeJSON.string(session["userId"])
            // 恢复的是占位用户（userName 等字段下次真实登录时填充）
            currentUserStorage = CcylUser(id: userId, userName: "", realname: "", orgName: "")
            log.d("CcylAuth", "init: session restored")
        } else {
            log.d("CcylAuth", "init: principal mismatch, wiping session")
            await secure.delete(StorageKeys.ccylSession)
        }
    }

    // MARK: - 登录

    /// 手动授权码路径
    func loginWithCode(code: String) async throws {
        authGeneration += 1
        let generation = authGeneration
        let principal = await scuAuth.principal
        guard let principal else {
            throw SCUError.unauthenticated("无法确认当前校园账号，请重新登录")
        }
        let result = try await CcylService.login(code: code, transport: transport)
        try await commit(result: result, generation: generation, principal: principal)
    }

    /// 静默重绑（single-flight）
    func reLogin() async throws {
        if await boundToken() != nil { return }
        // 陈旧状态先清
        if token != nil || boundScuPrincipal != nil {
            await invalidateSession()
        }
        if let task = reLoginTask {
            try await task.value
            return
        }
        let task = Task { try await self.doReLogin(generation: authGeneration) }
        let token = UUID()
        reLoginTask = task
        reLoginToken = token
        defer {
            if reLoginToken == token {
                reLoginTask = nil
                reLoginToken = nil
            }
        }
        try await task.value
    }

    private func doReLogin(generation: Int) async throws {
        let principal = await scuAuth.principal
        guard let principal else {
            throw SCUError.unauthenticated("无法确认当前校园账号，请重新登录")
        }
        guard let code = await oauthCodeProvider() else {
            throw SCUError.unauthenticated("第二课堂授权失败")
        }
        let result = try await CcylService.login(code: code, transport: transport)
        try await commit(result: result, generation: generation, principal: principal)
    }

    /// 过期恢复（并发共享；废弃当前尝试后重登）
    func recoverExpiredSession() async -> Bool {
        authGeneration += 1
        let generation = authGeneration
        await secure.delete(StorageKeys.ccylSession)
        token = nil
        currentUserStorage = nil
        boundScuPrincipal = nil
        do {
            try await doReLogin(generation: generation)
            return true
        } catch {
            log.w("CcylAuth", "recoverExpiredSession failed: \(error)")
            return false
        }
    }

    /// 仅当代次与 principal 均未变化时提交
    private func commit(result: CcylService.LoginResult, generation: Int, principal: String) async throws {
        guard authGeneration == generation else {
            log.w("CcylAuth", "commit skipped: generation changed")
            return
        }
        let currentPrincipal = await scuAuth.principal
        guard currentPrincipal == principal else {
            log.w("CcylAuth", "commit skipped: principal changed")
            return
        }
        // 持久化（token/用户名等信息序列化写入）
        let session: [String: Any] = [
            "token": result.token,
            "userId": result.user.id,
            "scuPrincipal": principal,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: session),
           let json = String(data: data, encoding: .utf8) {
            await secure.write(StorageKeys.ccylSession, json)
        }
        await secure.delete(StorageKeys.ccylTokenLegacy)
        await secure.delete(StorageKeys.ccylUserIdLegacy)
        token = result.token
        currentUserStorage = result.user
        boundScuPrincipal = principal
        if let bus {
            Task { @MainActor in bus.subsystemReady["ccyl"] = true }
        }
        log.i("CcylAuth", "login committed")
    }

    // MARK: - SubsystemAuth

    func ensureAuthenticated() async throws {
        if await boundToken() != nil { return }
        do {
            try await reLogin()
        } catch {
            throw SCUError.unauthenticated("第二课堂未登录")
        }
    }

    func invalidate() async {
        authGeneration += 1
        token = nil
        currentUserStorage = nil
        boundScuPrincipal = nil
        if let bus {
            Task { @MainActor in bus.subsystemReady["ccyl"] = false }
        }
    }

    /// 清内存 + 清持久化（不通知）
    func invalidateSession() async {
        await invalidate()
        await secure.delete(StorageKeys.ccylSession)
    }

    func logout() async {
        await invalidateSession()
    }
}
