import Foundation

/// newservice（后勤智慧线上服务平台）API（对应 new_service_api_service.dart）。
/// passpoint 无感认证接口；会话 cookie `process_uid`/`process_number` 由
/// SsoRelayAuth(newservice) 维护，请求经 CookieClient 自动携带。
///
/// 响应约定：与 zhjw/wfw 的数字 e 不同，newservice 成功码是字符串 `e == "OK"`；
/// `d` 内 `errorCode`（0 成功）/`errorMessage` 才是具体业务结果。
struct NewServiceApiService {

    let auth: SsoRelayAuth
    let log: AuthLogger

    init(auth: SsoRelayAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    static let base = URL(string: "https://service.scu.edu.cn")!
    static let basePath = "/newservice"

    private var jsonHeaders: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": Self.base.absoluteString,
            "Referer": "\(Self.base.absoluteString)\(Self.basePath)/fe/site/m_passpoint",
            "User-Agent": Constants.userAgent,
        ]
    }

    private static func formHeaders(refererPath: String) -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": base.absoluteString,
            "Referer": "\(base.absoluteString)\(basePath)\(refererPath)",
            "User-Agent": Constants.userAgent,
        ]
    }

    // MARK: - 过期与业务校验

    static func checkSessionExpiry(body: String, statusCode: Int) throws {
        // 会话失效时后端返回 302/401/403 或空 body（参照 wfw 判定）
        if statusCode == 302 || statusCode == 401 || statusCode == 403 {
            throw SCUError.unauthenticated()
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
        // 登录页强特征判断，不做裸 login 子串匹配（issue #282）
        if LoginPageDetector.looksLikeLoginPage(body) {
            throw SCUError.unauthenticated()
        }
    }

    private func decodeResponse(_ body: String, statusCode: Int) throws -> [String: Any] {
        try Self.checkSessionExpiry(body: body, statusCode: statusCode)
        let json = try SafeJSON.parseObject(body, api: "newservice")
        let code = SafeJSON.string(json["e"])
        guard code == "OK" else {
            if code == "UN_AUTH" {
                throw SCUError.unauthenticated("newservice 登录已失效")
            }
            let message = SafeJSON.string(json["m"])
            throw SCUError.service(message.isEmpty ? "服务暂不可用" : message)
        }
        return json
    }

    /// `d` 内业务错误码（0 成功；非 0 记日志并抛具体文案）
    private func checkData(_ json: [String: Any]) throws -> [String: Any] {
        let d = json["d"] as? [String: Any] ?? [:]
        let errorCode = SafeJSON.string(d["errorCode"])
        if !errorCode.isEmpty && errorCode != "0" {
            var message = SafeJSON.string(d["errorMessage"])
            if message.isEmpty { message = "操作失败" }
            log.w("NEWSERVICE", "passpoint 业务错误 errorCode=\(errorCode): \(message)")
            throw SCUError.service(message)
        }
        return d
    }

    // MARK: - 接口

    /// 无感设备列表：GET /newservice/site/passpoint/query-user-mab-info?limit=100
    func fetchDevices(limit: Int = 100) async throws -> [PasspointDevice] {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            var components = URLComponents(
                string: "\(Self.base.absoluteString)\(Self.basePath)/site/passpoint/query-user-mab-info"
            )!
            components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            let resp = try await $0.send(HTTPRequest(method: "GET", url: components.url!, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        let d = try checkData(json)
        let list = d["data"] as? [[String: Any]] ?? []
        return list.map(PasspointDevice.fromJson)
    }

    /// 校园网账户信息：GET /newservice/site/passpoint/query-user
    func fetchUserInfo() async throws -> PasspointUserInfo? {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Self.base.absoluteString)\(Self.basePath)/site/passpoint/query-user")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        let d = try checkData(json)
        let result = d["queryUserResult"] as? [String: Any]
        guard let data = result?["data"] as? [String: Any] else { return nil }
        return PasspointUserInfo.fromJson(data)
    }

    /// 添加无感设备。defaultServiceName 空串 = 校园网出口；macExpireTime 0-365 天，0 = 最长约 6 年。
    func addDevice(userMac: String, macExpireTime: Int, defaultServiceName: String = "") async throws {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Self.base.absoluteString)\(Self.basePath)/site/passpoint/add-user-mab-info")!
            let form = [
                "userMac=\(FormEncoding.encode(userMac))",
                "macExpireTime=\(macExpireTime)",
                "defaultServiceName=\(FormEncoding.encode(defaultServiceName))",
            ].joined(separator: "&")
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: Self.formHeaders(refererPath: "/fe/site/m_passpoint"),
                body: Data(form.utf8)
            ))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        _ = try checkData(json)
    }

    /// 取消指定设备的无感认证。
    func cancelDevice(userMac: String, userId: String? = nil) async throws {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Self.base.absoluteString)\(Self.basePath)/site/passpoint/cancel-user-mab-info")!
            var parts = ["userMac=\(FormEncoding.encode(userMac))"]
            if let userId, !userId.isEmpty {
                parts.append("userId=\(FormEncoding.encode(userId))")
            }
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: Self.formHeaders(refererPath: "/fe/site/m_passpoint"),
                body: Data(parts.joined(separator: "&").utf8)
            ))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        _ = try checkData(json)
    }
}
