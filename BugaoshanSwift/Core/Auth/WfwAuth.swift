import Foundation

/// WFW（微服务 wfw.scu.edu.cn）子系统认证（对应 lib/services/auth/wfw_auth.dart）。
/// Session = 共享根 client jar 中的 wfw cookie（eai-sess 等）。
///
/// 预热陷阱（Dart 版注释原样保留语义）：
/// 必须用 get-info 匿名链路预热——首页只会返回 200 + 匿名 eai-sess cookie，
/// 永远不触发 SSO；仅凭状态码或「jar 里有 wfw cookie」判断就绪会把匿名会话
/// 误判为已就绪 → 无限 invalidate/重预热循环。唯一有效判据：get-info 返回 JSON e == 0。
actor WfwAuth: SubsystemAuth {

    let moduleId = "wfw"
    let dependencies: [any SubsystemAuth] = []

    static let warmUpUrl = URL(string: "https://wfw.scu.edu.cn/uc/wap/user/get-info")!

    private let scuAuth: ScuAuth
    private let log: AuthLogger
    private weak var bus: AuthBus?

    private var ready = false
    private var warmUpTask: Task<Void, Error>?
    private var warmUpToken: UUID?
    private var lastScuClient: CookieClient?

    init(scuAuth: ScuAuth, log: AuthLogger = .shared, bus: AuthBus? = nil) {
        self.scuAuth = scuAuth
        self.log = log
        self.bus = bus
    }

    var isReady: Bool { ready }

    // MARK: - 核心流程

    func getClient() async throws -> CookieClient {
        let client = try await scuAuth.getClient()
        try await ensureClientReady(client)
        return client
    }

    private func ensureClientReady(_ client: CookieClient) async throws {
        // 根 client 更换 → 复位就绪态
        if client !== lastScuClient {
            ready = false
            warmUpTask = nil
            warmUpToken = nil
            lastScuClient = client
        }
        if ready { return }
        if let task = warmUpTask {
            try await task.value
            return
        }
        let task = Task { try await self.warmUp(client) }
        let token = UUID()
        warmUpTask = task
        warmUpToken = token
        defer {
            if warmUpToken == token {
                warmUpTask = nil
                warmUpToken = nil
            }
        }
        try await task.value
    }

    private func warmUp(_ client: CookieClient) async throws {
        // 只带 UA，不带 AJAX 头；匿名链路 get-info → /uc/wap/login → CAS → 回跳，
        // 在共享 jar 中建立已绑定的会话 cookie；已绑定时直接返回 e==0 JSON
        let resp = try await client.followRedirects(
            to: Self.warmUpUrl,
            headers: ["User-Agent": Constants.userAgent]
        )
        if resp.statusCode == 401 || resp.statusCode == 403 {
            log.w("WfwAuth", "warm-up rejected (\(resp.statusCode))")
            throw SCUError.unauthenticated("微服务登录已失效")
        }
        if !(200..<300).contains(resp.statusCode) {
            log.w("WfwAuth", "warm-up HTTP \(resp.statusCode)")
            throw SCUError.service("微服务预热失败", statusCode: resp.statusCode)
        }
        guard let json = try? SafeJSON.parseObject(resp.bodyString, api: "wfw-warmup"),
              SafeJSON.int(json["e"]) == 0 else {
            log.w("WfwAuth", "warm-up: session not bound (non-JSON or e != 0)")
            throw SCUError.unauthenticated("微服务 session 未建立")
        }
        ready = true
        if let bus {
            Task { @MainActor in bus.subsystemReady["wfw"] = true }
        }
        log.i("WfwAuth", "warm-up: ok")
    }

    // MARK: - SubsystemAuth

    func ensureAuthenticated() async throws {
        _ = try await getClient()
    }

    func invalidate() async {
        ready = false
        warmUpTask = nil
        warmUpToken = nil
        lastScuClient = nil
        if let bus {
            Task { @MainActor in bus.subsystemReady["wfw"] = false }
        }
    }
}
