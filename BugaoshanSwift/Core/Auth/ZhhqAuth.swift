import Foundation

/// zhhq（智慧后勤）子系统认证（对应 lib/services/auth/zhhq_auth.dart）。
/// 登录态 = zhhq 域 tokenKey（ITSOFT-WILLAB-SESSION 值），持久化 `zhhq_token_key`。
///
/// 认证链（抓包确认）：
/// 1. 跟随 CAS 中继（scdxplugin_jwt31）→ 回跳 `/account/login?userinfo=<加密串>`
/// 2. userinfo 调 `POST /api/auth/login/auto` 换 tokenKey（响应体 AES 加密 JSON）
/// 3. 业务请求头带每次新生成的 Token + TokenKey
///
/// 快路径：tokenKey 持久化后冷启动直接复用，跳过 5–8s 的 SSO 链；
/// 陈旧 tokenKey 由 API 层 4010–4017 处理自愈。
actor ZhhqAuth: SubsystemAuth {

    let moduleId = "zhhq"
    let dependencies: [any SubsystemAuth] = []

    static let casUrl = URL(string: "https://id.scu.edu.cn/enduser/sp/sso/scdxplugin_jwt31?enterpriseId=scdx")!
    static let loginAutoUrl = URL(string: "https://zhhq.scu.edu.cn/api/auth/login/auto")!

    private let scuAuth: ScuAuth
    private let secure: SecureStore
    private let log: AuthLogger
    private weak var bus: AuthBus?

    private var tokenKey: String?
    private var warmUpTask: Task<Void, Error>?
    private var warmUpToken: UUID?
    private var authFailed = false
    private var ready = false

    private let cookieClientFactory: @Sendable () -> CookieClient

    init(
        scuAuth: ScuAuth,
        secure: SecureStore = KeychainStore(),
        log: AuthLogger = .shared,
        bus: AuthBus? = nil,
        cookieClientFactory: @escaping @Sendable () -> CookieClient = { CookieClient() }
    ) {
        self.scuAuth = scuAuth
        self.secure = secure
        self.log = log
        self.bus = bus
        self.cookieClientFactory = cookieClientFactory
    }

    var isReady: Bool { ready }

    /// 冷启动恢复（不等 SCU；tokenKey 是 zhhq 域独立状态）
    func restoreFromStorage() async {
        tokenKey = await secure.read(StorageKeys.zhhqTokenKey)
        if tokenKey != nil {
            log.d("ZHhq", "init: tokenKey restored")
        }
    }

    /// 供 API 层构造 Token/TokenKey 头
    func currentTokenKey() async -> String? { tokenKey }

    // MARK: - 核心流程

    /// 快路径：tokenKey 存在时返回全新无 cookie client（zhhq 业务请求不带 cookie）
    func getClientFast() async throws -> CookieClient {
        guard let tokenKey else {
            throw SCUError.unauthenticated("zhhq 未登录")
        }
        _ = tokenKey
        return cookieClientFactory()
    }

    /// 完整路径：根 client + SSO + tokenKey（single-flight；失败置 authFailed 供页面重试提示）
    func getClient() async throws -> CookieClient {
        let client = try await scuAuth.getClient()
        try await ensureTokenKey(client)
        return client
    }

    private func ensureTokenKey(_ client: CookieClient) async throws {
        if tokenKey != nil { return }
        if let task = warmUpTask {
            try await task.value
            return
        }
        let task = Task { try await self.doLogin(client) }
        let token = UUID()
        warmUpTask = task
        warmUpToken = token
        defer {
            if warmUpToken == token {
                warmUpTask = nil
                warmUpToken = nil
            }
        }
        do {
            try await task.value
        } catch {
            authFailed = true
            if let bus {
                Task { @MainActor in bus.subsystemReady["zhhq"] = false }
            }
            throw error
        }
    }

    private func doLogin(_ client: CookieClient) async throws {
        let auth = try await scuAuth.getAccessToken()
        let response = try await client.followRedirects(
            to: Self.casUrl,
            headers: [
                "Accept": "text/html,application/xhtml+xml,*/*",
                "User-Agent": Constants.userAgent,
                "Authorization": "Bearer \(auth)",
            ]
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SCUError.unauthenticated()
        }
        if response.statusCode < 200 || response.statusCode >= 400 {
            throw SCUError.service("zhhq SSO 中继失败", statusCode: response.statusCode)
        }

        // 回跳 URL 携带 userinfo（日志只记录长度，不打印 URL/内容）
        let finalUrl = response.finalURL
        let userinfo = response.queryItems["userinfo"] ?? ""
        log.i("ZHhq", "SSO 回跳: path=\(finalUrl.path) hasUserinfo=\(!userinfo.isEmpty) userinfoLen=\(userinfo.count)")
        guard !userinfo.isEmpty else {
            log.e("ZHhq", "SSO 回跳缺少 userinfo")
            throw SCUError.unauthenticated("zhhq 认证回跳缺少 userinfo")
        }

        let key = try await exchangeTokenKey(client, userinfo: userinfo)
        await applyTokenKey(key)
    }

    /// userinfo 换 tokenKey。timestamp 用默认 key/iv 加密；userInfo 双层 URL 编码
    /// （外层由表单编码完成，等价 Dart http.post(body: Map) 的再编码行为）。
    private func exchangeTokenKey(_ client: CookieClient, userinfo: String) async throws -> String {
        let timestamp = try ZhhqCrypto.encrypt(String(Int(Date().timeIntervalSince1970 * 1000)))
        // Dart: userInfo = Uri.encodeComponent(userinfo)，随后 http 包按表单再次编码
        let form = [
            "userInfo": FormEncoding.encode(FormEncoding.encodeComponent(userinfo)),
            "clientId": FormEncoding.encode(ZhhqCrypto.clientId),
            "timestamp": FormEncoding.encode(timestamp),
            "schoolCode": FormEncoding.encode("10610"),
            "schoolName": FormEncoding.encode("四川大学"),
        ].map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")

        let request = HTTPRequest(
            method: "POST",
            url: Self.loginAutoUrl,
            headers: [
                "Accept": "application/json, text/plain, */*",
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "Origin": "https://zhhq.scu.edu.cn",
                "Referer": "https://zhhq.scu.edu.cn/account/login",
                "User-Agent": Constants.userAgent,
                "X-Requested-With": "XMLHttpRequest",
            ],
            body: Data(form.utf8)
        )
        let resp = try await client.send(request)
        return try parseLoginAutoResponse(resp)
    }

    private func parseLoginAutoResponse(_ resp: HTTPResponse) throws -> String {
        if resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403
            || resp.bodyString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
        guard let json = ZhhqCrypto.zhhqDecodeResponse(resp.bodyString) else {
            log.e("ZHhq", "login/auto 响应解密失败")
            throw SCUError.unauthenticated("zhhq tokenKey 获取失败")
        }
        let code = json["errorCode"].map { SafeJSON.string($0) } ?? ""
        let status = json["status"].map { SafeJSON.string($0) } ?? ""
        if code != "0" && !code.isEmpty && status == "error" {
            log.e("ZHhq", "login/auto 失败: \(SafeJSON.string(json["message"] ?? nil))")
            throw SCUError.unauthenticated("zhhq 登录失败: \(SafeJSON.string(json["message"] ?? nil))")
        }
        let tokenKey = SafeJSON.string(json["data"] ?? nil)
        guard tokenKey.count >= 16 else {
            log.e("ZHhq", "login/auto 未返回有效 tokenKey")
            throw SCUError.unauthenticated("zhhq tokenKey 获取失败")
        }
        log.i("ZHhq", "tokenKey acquired")
        return tokenKey
    }

    private func applyTokenKey(_ value: String) async {
        tokenKey = value
        await secure.write(StorageKeys.zhhqTokenKey, value)
        if authFailed {
            authFailed = false
            log.i("ZHhq", "auth recovered, clearing failure flag")
        }
        if !ready {
            ready = true
            if let bus {
                Task { @MainActor in bus.subsystemReady["zhhq"] = true }
            }
        }
    }

    // MARK: - SubsystemAuth

    /// 快路径：tokenKey 存在直接返回（不等 SCU——SSO 链可能 5–8s）
    func ensureAuthenticated() async throws {
        guard tokenKey != nil else {
            _ = try await getClient()
            return
        }
    }

    /// 会话失效（API 层收到 errorCode 4010–4017 时调用）
    func invalidate() async {
        if ready { log.d("ZHhq", "invalidate") }
        ready = false
        tokenKey = nil
        warmUpTask = nil
        warmUpToken = nil
        authFailed = false
        await secure.delete(StorageKeys.zhhqTokenKey)
    }
}

// MARK: - 表单编码（对齐 Dart Uri.encodeQueryComponent / encodeComponent 语义）

enum FormEncoding {
    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))

    /// Uri.encodeQueryComponent：非保留字符全编码，空格 → '+'
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            let scalar = UnicodeScalar(byte)
            if byte == 0x20 {
                out.append("+")
            } else if scalar.isASCII && unreserved.contains(scalar) {
                out.append(Character(scalar))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Uri.encodeComponent：与 encode 的区别仅在空格（%20 而非 +）
    static func encodeComponent(_ value: String) -> String {
        encode(value).replacingOccurrences(of: "+", with: "%20")
    }
}
