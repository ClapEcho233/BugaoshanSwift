import Foundation

/// 微服务 API（对应 lib/services/api/wfw_api_service.dart）。
/// 响应封套 {e, m, d}；过期判定 302/401/403/空体/login页/e==10013。
struct WfwApiService {

    let auth: WfwAuth
    let log: AuthLogger

    init(auth: WfwAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    private static let base = URL(string: "https://wfw.scu.edu.cn")!

    // MARK: - 解码

    static func decodeResponse(_ resp: HTTPResponse, api: String) throws -> [String: Any] {
        let body = resp.bodyString
        if resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403
            || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
        if LoginPageDetector.looksLikeLoginPage(body) {
            throw SCUError.unauthenticated()
        }
        let json = try SafeJSON.parseObject(body, api: api)
        if SafeJSON.int(json["e"]) == 10013 {
            throw SCUError.unauthenticated("微服务登录已失效")
        }
        return json
    }

    static func isSuccess(_ json: [String: Any]) -> Bool {
        SafeJSON.int(json["e"]) == 0
    }

    // MARK: - 用户信息

    struct UserProfile {
        var realname: String
        var number: String
        var raw: [String: Any]
    }

    /// GET /uc/wap/user/get-info → d.base
    func fetchUserProfile() async throws -> UserProfile {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(HTTPRequest(
                method: "GET",
                url: Self.base.appendingPathComponent("uc/wap/user/get-info"),
                headers: ["User-Agent": Constants.userAgent]
            ))
            let json = try Self.decodeResponse(resp, api: "get-info")
            guard let data = json["d"] as? [String: Any],
                  let base = data["base"] as? [String: Any] else {
                throw SCUError.service("[get-info] 响应缺少 d.base")
            }
            let role = base["role"] as? [String: Any]
            return UserProfile(
                realname: SafeJSON.string(base["realname"]),
                number: SafeJSON.string(role?["number"]),
                raw: base
            )
        }
    }

    /// GET /mashupapp/wap/real/user → d.labels
    func fetchProfileLabels() async throws -> [[String: Any]] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(HTTPRequest(
                method: "GET",
                url: Self.base.appendingPathComponent("mashupapp/wap/real/user"),
                headers: [
                    "Accept": "application/json, text/plain, */*",
                    "X-Requested-With": "XMLHttpRequest",
                    "Referer": "https://wfw.scu.edu.cn",
                    "User-Agent": Constants.userAgent,
                ]
            ))
            let json = try Self.decodeResponse(resp, api: "real/user")
            let data = json["d"] as? [String: Any]
            return (data?["labels"] as? [[String: Any]]) ?? []
        }
    }

    // MARK: - 校园网设备

    struct NetworkDevice: Identifiable {
        var id: String
        /// 下线接口用的设备 id（区别于 Identifiable 的合成 id）
        var deviceId: String
        var ip: String
        var mac: String
        var location: String
        var loginTime: String
        var raw: [String: Any]

        static func fromJson(_ json: [String: Any]) -> NetworkDevice {
            NetworkDevice(
                id: SafeJSON.string(json["id"]) + "_" + SafeJSON.string(json["ip"]),
                deviceId: SafeJSON.string(json["id"]),
                ip: SafeJSON.string(json["ip"]),
                mac: SafeJSON.string(json["mac"]),
                location: SafeJSON.string(json["userLocation"]),
                loginTime: SafeJSON.string(json["loginTime"]) + SafeJSON.string(json["onlineTime"]),
                raw: json
            )
        }
    }

    /// POST /netclient/wap/default/get-index（空 JSON POST）
    func fetchNetworkDevices() async throws -> [NetworkDevice] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(HTTPRequest(
                method: "POST",
                url: Self.base.appendingPathComponent("netclient/wap/default/get-index"),
                headers: [
                    "Accept": "application/json, text/plain, */*",
                    "Content-Type": "application/json; charset=UTF-8",
                    "Origin": "https://wfw.scu.edu.cn",
                    "Referer": "https://wfw.scu.edu.cn",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ]
            ))
            let json = try Self.decodeResponse(resp, api: "netclient-index")
            let data = json["d"] as? [String: Any]
            let list = (data?["list"] as? [[String: Any]]) ?? []
            return list.map(NetworkDevice.fromJson)
        }
    }

    /// POST /netclient/wap/default/offline（form device_id / ip）
    func offlineDevice(deviceId: String, ip: String) async throws {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let form = "device_id=\(FormEncoding.encode(deviceId))&ip=\(FormEncoding.encode(ip))"
            let resp = try await $0.send(HTTPRequest(
                method: "POST",
                url: Self.base.appendingPathComponent("netclient/wap/default/offline"),
                headers: [
                    "Accept": "application/json, text/plain, */*",
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Origin": "https://wfw.scu.edu.cn",
                    "Referer": "https://wfw.scu.edu.cn",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let json = try Self.decodeResponse(resp, api: "netclient-offline")
            guard Self.isSuccess(json) else {
                throw SCUError.service(SafeJSON.string(json["m"], fallback: "下线失败"))
            }
        }
    }
}
