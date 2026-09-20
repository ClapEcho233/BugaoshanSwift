import Foundation

enum AuthState: Equatable, Sendable {
    case unknown   // 尚未认证
    case ready     // 可用
    case expired   // 需要刷新
    case error     // 非过期类失败

    var name: String {
        switch self {
        case .unknown: return "unknown"
        case .ready: return "ready"
        case .expired: return "expired"
        case .error: return "error"
        }
    }
}

/// 验证码结果
struct CaptchaResult: Sendable {
    var code: String
    var captchaBase64: String
}

/// SCU 统一身份认证（第 3 层，对应 lib/services/auth/scu_auth.dart）。
///
/// actor 隔离全部可变状态；保留 Dart 版全部不变量：
/// - bindSession / refresh 的 single-flight（Task 缓存 + UUID 令牌清除）
/// - 登出代次 authEpoch（飞行中的刷新不写回，防止登出被撤销）
/// - 1 小时 TTL；refresh = 重新 session/save，失败则凭据 + OCR 自动登录
/// - onSessionExpired 回调（UI 弹提示）
actor ScuAuth {

    static let base = "https://id.scu.edu.cn"
    static let clientId = "1371cbeda563697537f28d99b4744a973uDKtgYqL5B"
    static let enterpriseId = "scdx"
    static let sessionDurationSeconds = 3600

    static let defaultHeaders: [String: String] = [
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json;charset=UTF-8",
        "Origin": base,
        "Referer": "\(base)/frontend/login",
        "User-Agent": Constants.userAgent,
    ]

    private let transport: HTTPTransport
    private let secure: SecureStore
    private let defaults: DefaultsStore
    private let log: AuthLogger
    private let cookieClientFactory: @Sendable () -> CookieClient
    /// 自动登录的验证码 OCR（AppEnvironment 注入 ScuOcrLite + 模型）
    private let ocr: @Sendable ([UInt8]) async -> String?
    /// UI 状态桥（弱引用，避免循环持有）
    private weak var bus: AuthBus?

    private(set) var accessToken: String?
    private var principalStorage: String?
    private var loginTimestampStorage: Int?
    private var cachedClient: CookieClient?
    private var bindSessionTask: Task<CookieClient, Error>?
    private var bindSessionToken: UUID?
    private var refreshTask: Task<Bool, Error>?
    private var refreshToken: UUID?

    private var stateStorage: AuthState = .unknown
    /// 登出代次：logout() 自增，飞行中的刷新据此放弃写回
    private var authEpoch: UInt64 = 0

    /// session 过期且自动刷新失败时调用（UI 显示提示）
    var onSessionExpired: (@Sendable () async -> Void)?

    func setOnSessionExpired(_ callback: (@Sendable () async -> Void)?) {
        onSessionExpired = callback
    }

    init(
        transport: HTTPTransport = URLSessionTransport(),
        secure: SecureStore = KeychainStore(),
        defaults: DefaultsStore = UserDefaultsStore(),
        log: AuthLogger = .shared,
        cookieClientFactory: @escaping @Sendable () -> CookieClient = { CookieClient() },
        ocr: @escaping @Sendable ([UInt8]) async -> String? = { _ in nil },
        bus: AuthBus? = nil
    ) {
        self.transport = transport
        self.secure = secure
        self.defaults = defaults
        self.log = log
        self.cookieClientFactory = cookieClientFactory
        self.ocr = ocr
        self.bus = bus
    }

    // MARK: - 状态

    var state: AuthState { stateStorage }
    var isReady: Bool { stateStorage == .ready }
    var principal: String? { principalStorage }
    var loginTimestamp: Int? { loginTimestampStorage }

    var isExpired: Bool {
        guard let loginTimestampStorage else { return true }
        let now = Int(Date().timeIntervalSince1970)
        return now - loginTimestampStorage > Self.sessionDurationSeconds
    }

    private func setState(_ value: AuthState) {
        guard stateStorage != value else { return }
        let prev = stateStorage
        stateStorage = value
        log.i("ScuAuth", "state \(prev.name) -> \(value.name)")
        if let bus {
            Task { @MainActor in bus.scuState = value }
        }
    }

    // MARK: - 初始化（冷启动恢复）

    func restoreFromStorage() async {
        do {
            accessToken = (try? await secure.read(StorageKeys.scuAccessToken)) ?? nil
            principalStorage = await restorePrincipal(accessToken)
            loginTimestampStorage = await defaults.int(StorageKeys.scuLoginTimestamp)

            if accessToken != nil && !isExpired {
                log.i("ScuAuth", "init: token restored, ts=\(loginTimestampStorage ?? 0)")
                setState(.ready)
            } else if accessToken != nil {
                log.w("ScuAuth", "init: token restored but expired")
            } else {
                log.d("ScuAuth", "init: no saved token")
            }
        } catch {
            log.w("ScuAuth", "init: failed to restore session: \(error)")
        }
    }

    private func restorePrincipal(_ token: String?) async -> String? {
        guard let token else { return nil }
        guard let raw = await secure.read(StorageKeys.scuPrincipalBinding) else { return nil }
        guard let data = raw.data(using: .utf8),
              let binding = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await secure.delete(StorageKeys.scuPrincipalBinding)
            return nil
        }
        let principal = binding["principal"] as? String
        let fingerprint = binding["tokenFingerprint"] as? String
        guard let principal, !principal.isEmpty, fingerprint == tokenFingerprint(token) else {
            await secure.delete(StorageKeys.scuPrincipalBinding)
            return nil
        }
        return principal
    }

    // MARK: - 验证码

    func fetchCaptcha() async throws -> CaptchaResult {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "\(Self.base)/api/public/bff/v1.2/one_time_login/captcha?_enterprise_id=\(Self.enterpriseId)&timestamp=\(ts)")!
        let request = HTTPRequest(method: "GET", url: url, headers: Self.defaultHeaders)
        // 传输错误（超时等）直接向上传播；仅解析失败转为登录错误
        let resp = try await transport.request(request)
        let body: [String: Any]
        do {
            body = try SafeJSON.parseObject(resp.bodyString, api: "captcha") { SCUError.login($0) }
        } catch {
            // 网关 5xx/维护页等非 JSON 响应，抛简洁错误并附状态码
            log.w("ScuAuth", "fetchCaptcha: HTTP \(resp.statusCode), 非 JSON 响应")
            throw SCUError.login("验证码接口请求失败(HTTP \(resp.statusCode))")
        }
        guard let data = body["data"] as? [String: Any] else {
            log.w("ScuAuth", "fetchCaptcha: missing data field")
            throw SCUError.login("验证码接口返回异常，缺少 data 字段")
        }
        let captchaImg = (data["captcha"] ?? data["image"] ?? data["img"] ?? data["captchaImage"]).map { SafeJSON.string($0) }
        let code = data["code"].map { SafeJSON.string($0) }
        guard let captchaImg, let code else {
            log.w("ScuAuth", "fetchCaptcha: missing captcha/code fields")
            throw SCUError.login("验证码字段解析失败")
        }
        log.d("ScuAuth", "fetchCaptcha: ok (\(captchaImg.count)B)")
        return CaptchaResult(code: code, captchaBase64: captchaImg)
    }

    // MARK: - 登录

    func login(username: String, password: String, captchaCode: String, captchaText: String) async throws {
        log.i("ScuAuth", "login: start")

        // 1. SM2 公钥（服务端偶发 500，3 次重试）
        var sm2Data: [String: Any]?
        for attempt in 0..<3 {
            do {
                let request = HTTPRequest(
                    method: "POST",
                    url: URL(string: "\(Self.base)/api/public/bff/v1.2/sm2_key")!,
                    headers: Self.defaultHeaders,
                    body: Data("{}".utf8)
                )
                let resp = try await transport.request(request)
                let json = try SafeJSON.parseObject(resp.bodyString, api: "sm2_key") { SCUError.login($0) }
                if let data = json["data"] as? [String: Any],
                   data["publicKey"] != nil, data["code"] != nil {
                    sm2Data = data
                    break
                }
            } catch {
                log.w("ScuAuth", "login: sm2_key attempt \(attempt + 1) failed: \(error)")
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard let sm2Data else {
            log.w("ScuAuth", "login: sm2_key failed after 3 attempts")
            throw SCUError.login("SM2 公钥接口返回异常")
        }
        guard let publicKey = sm2Data["publicKey"].map({ SafeJSON.string($0) }),
              let sm2Code = sm2Data["code"].map({ SafeJSON.string($0) }) else {
            log.w("ScuAuth", "login: sm2_key missing publicKey/code fields")
            throw SCUError.login("SM2 公钥字段缺失")
        }
        log.d("ScuAuth", "login: sm2 key acquired")

        // 2. SM2 C1C2C3 加密密码
        let encryptedPassword = try SM2Crypto.encryptWithBase64Key(password, publicKeyBase64: publicKey)

        // 3. 请求 token
        let payload: [String: Any] = [
            "client_id": Self.clientId,
            "grant_type": "password",
            "scope": "read",
            "username": username,
            "password": encryptedPassword,
            "_enterprise_id": Self.enterpriseId,
            "sm2_code": sm2Code,
            "cap_code": captchaCode,
            "cap_text": captchaText,
        ]
        let tokenRequest = HTTPRequest(
            method: "POST",
            url: URL(string: "\(Self.base)/api/public/bff/v1.2/rest_token")!,
            headers: Self.defaultHeaders,
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let tokenResp = try await transport.request(tokenRequest)

        if !(200..<300).contains(tokenResp.statusCode) {
            let detail = Self.extractTokenErrorMessage(tokenResp.bodyString)
            log.w("ScuAuth", "login: rest_token HTTP \(tokenResp.statusCode): \(detail ?? "")")
            if let detail {
                throw SCUError.login(detail)
            }
            throw SCUError.login("登录请求失败(HTTP \(tokenResp.statusCode))")
        }

        let result = try SafeJSON.parseObject(tokenResp.bodyString, api: "rest_token") { SCUError.login($0) }
        if result["success"] as? Bool != true {
            let msg = result["message"].map { SafeJSON.string($0) } ?? result["msg"].map { SafeJSON.string($0) } ?? "登录失败"
            log.w("ScuAuth", "login: rejected: \(msg)")
            throw SCUError.login(msg)
        }
        guard let tokenData = result["data"] as? [String: Any],
              let token = tokenData["access_token"].map({ SafeJSON.string($0) }) else {
            log.w("ScuAuth", "login: missing access_token in response")
            throw SCUError.login("Token 字段缺失")
        }

        // 登录成功
        accessToken = token
        principalStorage = username
        cachedClient = nil
        bindSessionTask = nil
        bindSessionToken = nil
        loginTimestampStorage = Int(Date().timeIntervalSince1970)
        await secure.write(StorageKeys.scuAccessToken, token)
        let binding: [String: Any] = [
            "principal": username,
            "tokenFingerprint": tokenFingerprint(token),
        ]
        if let bindingData = try? JSONSerialization.data(withJSONObject: binding),
           let bindingJson = String(data: bindingData, encoding: .utf8) {
            await secure.write(StorageKeys.scuPrincipalBinding, bindingJson)
        }
        await defaults.setInt(StorageKeys.scuLoginTimestamp, loginTimestampStorage)
        log.i("ScuAuth", "login: ok, token len=\(token.count)")
        if let bus {
            let name = username
            Task { @MainActor in bus.username = name }
        }
        setState(.ready)
    }

    /// 从 rest_token 失败响应体提取错误信息；兼容业务格式与 OAuth 格式。纯函数，供测试。
    static func extractTokenErrorMessage(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["message", "msg", "error_description", "description", "error"] {
            if let value = decoded[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Session 绑定

    func bindSession() async throws -> CookieClient {
        guard accessToken != nil else {
            throw SCUError.unauthenticated("未登录")
        }
        if let cached = cachedClient {
            log.d("ScuAuth", "bindSession: cache hit")
            return cached
        }
        // single-flight：并发调用只执行一次握手
        if let task = bindSessionTask {
            return try await task.value
        }
        log.i("ScuAuth", "bindSession: starting SSO handshake")
        let task = Task { try await self.doBindSession() }
        let token = UUID()
        bindSessionTask = task
        bindSessionToken = token
        defer {
            if bindSessionToken == token {
                bindSessionTask = nil
                bindSessionToken = nil
            }
        }
        return try await task.value
    }

    private func doBindSession() async throws -> CookieClient {
        let client = cookieClientFactory()

        // Step 1: 保存 token 到服务端 session（必须成功）
        var headers = Self.defaultHeaders
        headers["Authorization"] = "Bearer \(accessToken!)"
        let request = HTTPRequest(
            method: "POST",
            url: URL(string: "\(Self.base)/api/bff/v1.2/commons/session/save")!,
            headers: headers,
            body: Data("{}".utf8)
        )
        let resp = try await client.send(request)
        if resp.statusCode == 401 || resp.statusCode == 403 {
            log.w("ScuAuth", "bindSession: token rejected (\(resp.statusCode))")
            throw SCUError.unauthenticated("统一认证 token 已失效")
        }
        if !(200..<300).contains(resp.statusCode) {
            log.w("ScuAuth", "bindSession: session/save HTTP \(resp.statusCode)")
            throw SCUError.service("session/save 请求失败", statusCode: resp.statusCode)
        }
        let result = try SafeJSON.parseObject(resp.bodyString, api: "session/save")
        if (result["error"] as? String)?.lowercased() == "invalid_token" {
            log.w("ScuAuth", "bindSession: invalid_token response")
            throw SCUError.unauthenticated("统一认证 token 已失效")
        }
        if result["success"] as? Bool != true {
            log.w("ScuAuth", "bindSession: session/save rejected")
            throw SCUError.service("session/save 失败: \(resp.bodyString)", statusCode: resp.statusCode)
        }

        await client.markReusable()
        cachedClient = client
        log.i("ScuAuth", "bindSession: ok")
        return client
    }

    /// 清除缓存 client，下次 bindSession 重新握手
    func invalidateCachedClient() {
        if cachedClient != nil {
            log.d("ScuAuth", "invalidateCachedClient")
        }
        cachedClient = nil
    }

    // MARK: - 获取已认证 Client（核心）

    func getClient() async throws -> CookieClient {
        if isExpired {
            log.w("ScuAuth", "getClient: token expired, refreshing")
            let refreshed = try await synchronizedRefresh()
            if !refreshed {
                log.e("ScuAuth", "getClient: refresh failed, session expired")
                await onSessionExpired?()
                throw SCUError.unauthenticated()
            }
            return try await bindSession()
        }

        guard accessToken != nil else {
            throw SCUError.unauthenticated("未登录")
        }

        do {
            return try await bindSession()
        } catch let error as SCUError {
            // token 被拒 或 session/save 瞬时失败：刷新一次自愈后重试
            log.w("ScuAuth", "getClient: bindSession failed (\(error.localizedDescription)), refreshing")
            let refreshed = try await synchronizedRefresh()
            if !refreshed {
                log.e("ScuAuth", "getClient: refresh failed, session expired")
                await onSessionExpired?()
                throw SCUError.unauthenticated()
            }
            return try await bindSession()
        }
    }

    func getAccessToken() async throws -> String {
        if isExpired {
            log.w("ScuAuth", "getAccessToken: token expired, refreshing")
            let refreshed = try await synchronizedRefresh()
            if !refreshed {
                log.e("ScuAuth", "getAccessToken: refresh failed, session expired")
                await onSessionExpired?()
                throw SCUError.unauthenticated()
            }
        }
        guard let accessToken else {
            throw SCUError.unauthenticated("未登录")
        }
        return accessToken
    }

    // MARK: - 续期（single-flight + 代次）

    private func synchronizedRefresh() async throws -> Bool {
        if let task = refreshTask {
            log.d("ScuAuth", "refresh: awaiting existing refresh")
            return try await task.value
        }
        log.i("ScuAuth", "refresh: starting (single-flight)")
        let epoch = authEpoch
        let task = Task { try await self.doRefresh() }
        let token = UUID()
        refreshTask = task
        refreshToken = token
        defer {
            if refreshToken == token {
                refreshTask = nil
                refreshToken = nil
            }
        }
        do {
            let result = try await task.value
            log.i("ScuAuth", "refresh: \(result ? "ok" : "failed")")
            return result
        } catch {
            // 已登出时不覆盖状态
            if authEpoch == epoch {
                setState(.error)
            }
            log.e("ScuAuth", "refresh: threw \(error)")
            throw error
        }
    }

    private func doRefresh() async throws -> Bool {
        guard accessToken != nil else {
            log.w("ScuAuth", "_doRefresh: no token, giving up")
            setState(.expired)
            return false
        }
        let epoch = authEpoch

        // 1. 清缓存，用现有 token 重新绑定
        invalidateCachedClient()
        do {
            let client = try await bindSession()
            if authEpoch != epoch {
                log.w("ScuAuth", "_doRefresh: logged out during refresh")
                return false
            }
            loginTimestampStorage = Int(Date().timeIntervalSince1970)
            await defaults.setInt(StorageKeys.scuLoginTimestamp, loginTimestampStorage)
            setState(.ready)
            return true
        } catch {
            log.w("ScuAuth", "refresh: bindSession failed (\(error)), trying autoLogin")
        }

        // 2. 凭据 + OCR 自动登录
        do {
            if try await autoLogin() {
                if authEpoch != epoch {
                    log.w("ScuAuth", "_doRefresh: logged out during autoLogin")
                    return false
                }
                setState(.ready)
                return true
            }
        } catch {
            log.e("ScuAuth", "refresh: autoLogin threw \(error)")
        }

        setState(.expired)
        return false
    }

    /// 强制刷新（外部入口）
    func refresh() async throws -> Bool {
        try await synchronizedRefresh()
    }

    // MARK: - 登出

    func logout() async {
        log.i("ScuAuth", "logout: clearing session")
        // 登出代次 +1，飞行中的刷新据此放弃写回
        authEpoch += 1
        // 等待者：Swift Task 必然完成，无需显式唤醒（Dart 版 completer.complete(false) 的等价保障）
        await cachedClient?.closeForce()
        cachedClient = nil
        accessToken = nil
        principalStorage = nil
        bindSessionTask = nil
        bindSessionToken = nil
        refreshTask = nil
        refreshToken = nil
        loginTimestampStorage = nil
        await secure.delete(StorageKeys.scuAccessToken)
        await secure.delete(StorageKeys.scuPrincipalBinding)
        await defaults.setInt(StorageKeys.scuLoginTimestamp, nil)
        if let bus {
            Task { @MainActor in
                bus.username = nil
                bus.realname = nil
            }
        }
        setState(.unknown)
    }

    // MARK: - 凭据管理（自动登录）

    func saveCredentials(username: String, password: String) async {
        await secure.write(StorageKeys.scuRememberPassword, "true")
        await secure.write(StorageKeys.scuSavedUsername, username)
        await secure.write(StorageKeys.scuSavedPassword, password)
    }

    func getSavedCredentials() async -> (username: String, password: String)? {
        let remember = await secure.read(StorageKeys.scuRememberPassword)
        guard remember == "true" else { return nil }
        let username = await secure.read(StorageKeys.scuSavedUsername)
        let password = await secure.read(StorageKeys.scuSavedPassword)
        if let username, let password {
            return (username, password)
        }
        return nil
    }

    func clearCredentials() async {
        await secure.delete(StorageKeys.scuRememberPassword)
        await secure.delete(StorageKeys.scuSavedUsername)
        await secure.delete(StorageKeys.scuSavedPassword)
    }

    /// UI 级自动登录开关（kScuAutoLogin = 'true'/'false'）
    func setAutoLoginEnabled(_ enabled: Bool) async {
        await secure.write(StorageKeys.scuAutoLogin, enabled ? "true" : "false")
    }

    var isAutoLoginEnabled: Bool {
        get async {
            await secure.read(StorageKeys.scuAutoLogin) == "true"
        }
    }

    /// 自动登录：凭据 + OCR 验证码，最多 3 次尝试（仅 invalid_captcha / OCR 失败换新验证码重试；
    /// 其他错误如密码错/网络异常直接失败）。全部失败后经 AuthBus 触发 UI 警告。
    func autoLogin() async throws -> Bool {
        guard let credentials = await getSavedCredentials() else {
            log.d("ScuAuth", "autoLogin: no saved credentials")
            return false
        }
        log.i("ScuAuth", "autoLogin: starting")
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let captcha = try await fetchCaptcha()
                let captchaText: String
                do {
                    let base64 = captcha.captchaBase64
                    let stripped: String
                    if let comma = base64.firstIndex(of: ",") {
                        stripped = String(base64[base64.index(after: comma)...])
                    } else {
                        stripped = base64
                    }
                    guard let imageBytes = Data(base64Encoded: stripped) else {
                        throw SCUError.login("验证码图片解码失败")
                    }
                    guard let text = await ocr([UInt8](imageBytes)) else {
                        throw SCUError.login("OCR 识别失败")
                    }
                    captchaText = text
                } catch {
                    // OCR/解码失败：换一张新验证码再试（除非已是最后一次）
                    log.w("ScuAuth", "autoLogin: OCR error (attempt \(attempt)/\(maxAttempts)): \(error)")
                    if attempt < maxAttempts { continue }
                    break
                }
                try await login(
                    username: credentials.username,
                    password: credentials.password,
                    captchaCode: captcha.code,
                    captchaText: captchaText
                )
                log.i("ScuAuth", "autoLogin: ok (attempt \(attempt))")
                return true
            } catch SCUError.login(let message) where message == "invalid_captcha" {
                // 仅验证码错误换新重试；其他登录错误（密码错等）不重试
                log.w("ScuAuth", "autoLogin: invalid captcha (attempt \(attempt)/\(maxAttempts))")
                if attempt == maxAttempts { break }
            } catch {
                log.w("ScuAuth", "autoLogin: failed: \(error)")
                return false
            }
        }
        log.e("ScuAuth", "autoLogin: all \(maxAttempts) attempts failed")
        // 三次全败 → UI 弹警告（重新登录引导）
        let bus = self.bus
        Task { @MainActor in bus?.autoLoginFailedTrigger += 1 }
        return false
    }
}
