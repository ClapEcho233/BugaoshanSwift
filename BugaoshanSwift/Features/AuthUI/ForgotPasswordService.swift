import Foundation

/// 忘记密码服务（forgot_password_service.dart）。无需登录态；
/// 三步流：verify_user（验证码）→ obtain_code / verify_code（短信/邮箱）→ submit。
struct ForgotPasswordService {

    static let base = URL(string: "https://id.scu.edu.cn")!
    static let enterpriseId = "scdx"
    static let captchaPath = "/api/public/bff/v1.2/one_time_login/captcha"
    static let apiPrefix = "/api/public/bff/v1.2/forgot_password"

    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    private var headers: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "Origin": "\(Self.base.absoluteString)/frontend/login",
            "Referer": "\(Self.base.absoluteString)/frontend/login",
            "User-Agent": Constants.userAgent,
        ]
    }

    // MARK: - 响应解析

    /// ok ⇔ success == true（键存在时）或 code 为 null/200/'200'；
    /// 错误信息依次尝试 message / msg / error_description
    static func parseResponse(_ body: [String: Any]) throws -> [String: Any] {
        if let success = body["success"] as? Bool {
            if success {
                return (body["data"] as? [String: Any]) ?? [:]
            }
            throw SCUError.forgotPassword(Self.errorMessage(body), businessCode: Self.businessCode(body))
        }
        let code: String? = (body["code"] as? Int).map(String.init) ?? body["code"] as? String
        if code == nil || code == "200" {
            return (body["data"] as? [String: Any]) ?? [:]
        }
        throw SCUError.forgotPassword(Self.errorMessage(body), businessCode: Int(code ?? ""))
    }

    private static func errorMessage(_ body: [String: Any]) -> String {
        for key in ["message", "msg", "error_description"] {
            let value = SafeJSON.string(body[key])
            if !value.isEmpty {
                return value
            }
        }
        return "操作失败"
    }

    private static func businessCode(_ body: [String: Any]) -> Int? {
        Int(SafeJSON.string(body["code"]))
    }

    // MARK: - 接口

    /// 验证码（注意参数名是 time 而非 timestamp）→ (图片 base64, code)
    func fetchCaptcha() async throws -> (captchaBase64: String, code: String) {
        let time = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "\(Self.base.absoluteString)\(Self.captchaPath)?_enterprise_id=\(Self.enterpriseId)&time=\(time)")!
        let resp = try await transport.request(HTTPRequest(method: "GET", url: url, headers: headers))
        let body = try SafeJSON.parseObject(resp.bodyString, api: "forgot-captcha") { _ in
            SCUError.forgotPassword("验证码接口请求失败(HTTP \(resp.statusCode))")
        }
        let data = try Self.parseResponse(body)
        let image = SafeJSON.string(data["captcha"] ?? data["image"] ?? data["img"] ?? data["captchaImage"])
        let code = SafeJSON.string(data["code"])
        guard !image.isEmpty, !code.isEmpty else {
            throw SCUError.forgotPassword("验证码字段解析失败")
        }
        return (image, code)
    }

    /// 第 1 步：校验用户 → 手机/邮箱（服务端原文，展示需打码）+ sToken
    func verifyUser(username: String, captchaText: String, captchaCode: String) async throws -> VerifyUserResult {
        let body = try await post("verify_user", [
            "_enterprise_id": Self.enterpriseId,
            "username": username,
            "phoneRegion": "",
            "captcha": captchaText,
            "captchaCode": captchaCode,
        ])
        return VerifyUserResult(
            phone: SafeJSON.string(body["phone"]),
            email: SafeJSON.string(body["email"]),
            sToken: SafeJSON.string(body["sToken"])
        )
    }

    /// 第 2a 步：发送验证码（type = phone / email）
    func obtainCode(username: String, type: String, sToken: String) async throws {
        _ = try await post("obtain_code", [
            "_enterprise_id": Self.enterpriseId,
            "username": username,
            "type": type,
            "sToken": sToken,
        ])
    }

    /// 第 2b 步：校验验证码 → 重置 token
    func verifyCode(username: String, type: String, code: String, sToken: String) async throws -> String {
        let body = try await post("verify_code", [
            "_enterprise_id": Self.enterpriseId,
            "username": username,
            "type": type,
            "code": code,
            "sToken": sToken,
        ])
        let token = SafeJSON.string(body["token"])
        guard !token.isEmpty else {
            throw SCUError.forgotPassword("重置令牌获取失败")
        }
        return token
    }

    /// 第 3 步：提交新密码（HTTPS 明文 JSON，与原版一致不走 SM2）
    func submit(token: String, password: String, username: String, channel: String) async throws {
        _ = try await post("submit", [
            "_enterprise_id": Self.enterpriseId,
            "token": token,
            "password": password,
            "rePassword": password,
            channel: username,
        ])
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: "\(Self.base.absoluteString)\(Self.apiPrefix)/\(path)?_enterprise_id=\(Self.enterpriseId)")!
        let resp = try await transport.request(HTTPRequest(
            method: "POST", url: url, headers: headers,
            body: try JSONSerialization.data(withJSONObject: body)
        ))
        let json = try SafeJSON.parseObject(resp.bodyString, api: "forgot-\(path)") { _ in
            SCUError.forgotPassword("请求失败(HTTP \(resp.statusCode))")
        }
        return try Self.parseResponse(json)
    }

    struct VerifyUserResult {
        var phone: String
        var email: String
        var sToken: String
    }

    // MARK: - 脱敏展示

    /// 手机号 3+4：123****7890
    static func maskedPhone(_ phone: String) -> String {
        guard phone.count >= 7 else { return String(repeating: "*", count: phone.count) }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }

    /// 邮箱：本地部分保留前 2 位 + 域名
    static func maskedEmail(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@"), at > email.startIndex else { return email }
        let local = email[..<at]
        let domain = email[at...]
        let keep = local.prefix(2)
        let masked = String(repeating: "*", count: max(0, local.count - 2))
        return "\(keep)\(masked)\(domain)"
    }
}
