import Foundation

/// 缴费平台 API（payapp）（对应 payapp_api_service.dart + balance_query_service.dart）
struct PayAppApiService {

    let auth: SsoRelayAuth
    let log: AuthLogger

    init(auth: SsoRelayAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    static let base = URL(string: "https://payapp.scu.edu.cn/eleFees")!

    struct Option: Identifiable, Equatable, Sendable {
        var id: String { code }
        var name: String
        var code: String
    }

    struct RoomInfo: Equatable, Sendable {
        var type: Int
        var cusNo: String
        var cusName: String
        var roomNo: String
        var schoolName: String
        var regName: String
        var unitName: String
        var price: Double
        var balance: Double
    }

    private var headers: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "Origin": "https://payapp.scu.edu.cn/eleFees",
            "Referer": "https://payapp.scu.edu.cn/eleFees",
            "User-Agent": Constants.userAgent,
        ]
    }

    // MARK: - 响应解码（含 payapp 特有的两种登录失效特征）

    static func decodeResponse(_ resp: HTTPResponse, api: String) throws -> [String: Any] {
        let body = resp.bodyString
        // 1. 重定向到已知认证目标
        if (300..<400).contains(resp.statusCode), let location = resp.header("location") {
            let resolved = URL(string: location, relativeTo: resp.finalURL)?.absoluteString.lowercased() ?? location.lowercased()
            if resolved.contains("payapp.scu.edu.cn"),
               ["/elefees/index.html", "/elefees/oauth/airwarrant", "/elefees/oauth/lightwarrant"]
                .contains(where: { resolved.contains($0) }) {
                throw SCUError.unauthenticated("缴费平台登录状态已失效")
            }
        }
        // 2. 登录超时 HTML 页
        let contentType = resp.header("content-type") ?? ""
        let lower = body.lowercased()
        let looksHtml = contentType.contains("text/html") || lower.contains("<html") || lower.contains("<!doctype html")
        if looksHtml && body.contains("登录超时")
            && (lower.contains("/elefees/oauth/airwarrant") || lower.contains("/elefees/oauth/lightwarrant")) {
            throw SCUError.unauthenticated("缴费平台登录状态已失效")
        }
        guard let json = try? SafeJSON.parseObject(body, api: api) else {
            throw SCUError.service("[\(api)] 响应解析失败", statusCode: resp.statusCode)
        }
        let respCode = SafeJSON.string(json["respCode"])
        guard respCode == "00" else {
            throw BalanceQueryError.general(SafeJSON.string(json["respDesc"], fallback: "查询失败(\(respCode))"))
        }
        return json
    }

    // MARK: - 端点

    private func request(path: String, body: [String: Any]) async throws -> [String: Any] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(HTTPRequest(
                method: "POST",
                url: Self.base.appendingPathComponent(path),
                headers: self.headers,
                body: try JSONSerialization.data(withJSONObject: body)
            ))
            return try Self.decodeResponse(resp, api: path)
        }
    }

    func fetchCampuses() async throws -> [Option] {
        let json = try await request(path: "electric/getCampus", body: [:])
        let datas = ((json["data"] as? [String: Any])?["datas"] as? [[String: Any]]) ?? []
        return datas.map { Option(name: SafeJSON.string($0["name"]), code: SafeJSON.string($0["code"])) }
    }

    func fetchBuildings(schoolCode: String) async throws -> [Option] {
        let json = try await request(path: "electric/getArchitecture", body: ["schoolCode": schoolCode])
        let datas = ((json["data"] as? [String: Any])?["datas"] as? [[String: Any]]) ?? []
        return datas.map { Option(name: SafeJSON.string($0["name"]), code: SafeJSON.string($0["code"])) }
    }

    func fetchUnits(schoolCode: String, regCode: String) async throws -> [Option] {
        let json = try await request(path: "electric/getUnit", body: ["schoolCode": schoolCode, "regCode": regCode])
        let datas = ((json["data"] as? [String: Any])?["datas"] as? [[String: Any]]) ?? []
        return datas.map { Option(name: SafeJSON.string($0["name"]), code: SafeJSON.string($0["code"])) }
    }

    func verifyRoom(
        cusNo: String, type: Int, cusName: String,
        schoolCode: String, regCode: String, unitCode: String, roomNo: String
    ) async throws -> Bool {
        let json = try await request(
            path: "electric/verificationRoom",
            body: [
                "cusNo": cusNo, "type": type, "cusName": cusName,
                "schoolCode": schoolCode, "regCode": regCode,
                "unitCode": unitCode, "roomNo": roomNo,
            ]
        )
        return SafeJSON.bool((json["data"] as? [String: Any])?["status"])
    }

    func queryRoomInfo(cusNo: String, type: Int, cusName: String) async throws -> RoomInfo {
        let json = try await request(
            path: "electric/queryRoomInfo",
            body: ["cusNo": cusNo, "type": type, "cusName": cusName]
        )
        guard let data = json["data"] as? [String: Any] else {
            throw BalanceQueryError.general("房间信息解析失败")
        }
        return RoomInfo(
            type: SafeJSON.int(data["type"]),
            cusNo: SafeJSON.string(data["cusNo"]),
            cusName: SafeJSON.string(data["cusName"]),
            roomNo: SafeJSON.string(data["roomNo"]),
            schoolName: SafeJSON.string(data["schoolName"]),
            regName: SafeJSON.string(data["regName"]),
            unitName: SafeJSON.string(data["unitName"]),
            price: SafeJSON.double(data["price"]),
            balance: SafeJSON.double(data["balance"])
        )
    }
}
