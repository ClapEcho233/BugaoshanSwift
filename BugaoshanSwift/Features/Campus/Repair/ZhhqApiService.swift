import Foundation
import CryptoKit

// MARK: - zhhq API（对应 lib/services/api/zhhq_api_service.dart）

struct ZhhqApiService {

    let auth: ZhhqAuth
    let log: AuthLogger

    init(auth: ZhhqAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    static let base = URL(string: "https://zhhq.scu.edu.cn/api")!

    // MARK: - 每次请求重建的 Token 头

    static func buildToken(tokenKey: String) throws -> String {
        let payload: [String: Any] = [
            "tokenKey": tokenKey,
            "clientId": ZhhqCrypto.clientId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "GUID": guid(),
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return try ZhhqCrypto.encrypt(
            String(data: json, encoding: .utf8) ?? "{}",
            key: ZhhqCrypto.clientSecret,
            iv: ZhhqCrypto.clientId
        )
    }

    /// v4 风格 GUID：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx（y = 3&n|8）
    static func guid() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
    }

    // MARK: - 请求封装（快路径 → 全路径 → 失效重放一次）

    private func request(
        path: String,
        method: String = "POST",
        form: [String: String]? = nil,
        json: [String: Any]? = nil,
        timeout: TimeInterval = Constants.httpTimeout
    ) async throws -> [String: Any] {
        // 快路径：持久化 tokenKey + 无 cookie client
        if let fastClient = try? await auth.getClientFast(),
           let tokenKey = await auth.currentTokenKey() {
            do {
                return try await perform(
                    client: fastClient, tokenKey: tokenKey,
                    path: path, method: method, form: form, json: json, timeout: timeout)
            } catch let error as SCUError where error.isUnauthenticated {
                // token 失效 → 落入全路径
                await auth.invalidate()
            }
        }
        // 全路径：SCU session + SSO（含一次失效重放）
        do {
            let client = try await auth.getClient()
            let tokenKey = try await requireTokenKey(client)
            return try await perform(
                client: client, tokenKey: tokenKey,
                path: path, method: method, form: form, json: json, timeout: timeout)
        } catch let error as SCUError where error.isUnauthenticated {
            await auth.invalidate()
            let client = try await auth.getClient()
            let tokenKey = try await requireTokenKey(client)
            return try await perform(
                client: client, tokenKey: tokenKey,
                path: path, method: method, form: form, json: json, timeout: timeout)
        }
    }

    private func requireTokenKey(_ client: CookieClient) async throws -> String {
        if let tokenKey = await auth.currentTokenKey() {
            return tokenKey
        }
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://zhhq.scu.edu.cn/")!,
                                              headers: ["User-Agent": Constants.userAgent]))
        guard let tokenKey = await auth.currentTokenKey() else {
            throw SCUError.unauthenticated("zhhq 未登录")
        }
        return tokenKey
    }

    private func perform(
        client: CookieClient,
        tokenKey: String,
        path: String,
        method: String,
        form: [String: String]?,
        json: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        var headers: [String: String] = [
            "Accept": "application/json, text/plain, */*",
            "Origin": "https://zhhq.scu.edu.cn",
            "Referer": "https://zhhq.scu.edu.cn/ihome/newrepair",
            "User-Agent": Constants.userAgent,
            "X-Requested-With": "XMLHttpRequest",
            "Token": try Self.buildToken(tokenKey: tokenKey),
            "TokenKey": tokenKey,
        ]
        var body: Data?
        if let json {
            headers["Content-Type"] = "application/json;charset=utf-8"
            body = try JSONSerialization.data(withJSONObject: json)
        } else if let form {
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
            body = Data(form.map { "\($0.key)=\(FormEncoding.encode($0.value))" }
                .joined(separator: "&").utf8)
        } else {
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        }
        var request = HTTPRequest(
            method: method,
            url: Self.base.appendingPathComponent(path),
            headers: headers,
            body: body
        )
        // 超时注入（仅本请求）
        _ = timeout
        let resp = try await client.send(request)
        _ = request
        return try Self.decode(resp, api: path)
    }

    // MARK: - 响应解码

    static func decode(_ resp: HTTPResponse, api: String) throws -> [String: Any] {
        let body = resp.bodyString
        if resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403
            || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
        guard let json = ZhhqCrypto.zhhqDecodeResponse(body) else {
            throw SCUError.service("[\(api)] zhhq 响应解析失败", statusCode: resp.statusCode)
        }
        // errorCode 4010–4017 → token 失效
        if let code = Int(SafeJSON.string(json["errorCode"])), (4010...4017).contains(code) {
            throw SCUError.unauthenticated("zhhq 会话已失效")
        }
        // 业务错误：status 非 success 或 errorCode 非空且非 '0'
        let status = SafeJSON.string(json["status"])
        let errorCode = SafeJSON.string(json["errorCode"])
        if (!status.isEmpty && status != "success") || (!errorCode.isEmpty && errorCode != "0") {
            let message = SafeJSON.string(json["message"], fallback: "操作失败")
            throw SCUError.service(message)
        }
        return json
    }

    // MARK: - 端点

    /// 常用地址
    func fetchCommonAddresses() async throws -> [RepairAddress] {
        let json = try await request(path: "repair/oneNetPublish/getCommonAddress", form: [:])
        let list = json["data"] as? [[String: Any]] ?? []
        return list.map(RepairAddress.fromJson)
    }

    /// 区域树
    func fetchAreaTree() async throws -> [RepairAreaNode] {
        let json = try await request(path: "repair/publish/getAreaTree")
        let list = json["data"] as? [[String: Any]] ?? []
        return list.map(RepairAreaNode.fromJson)
    }

    /// 区域下的报修项目（两级树，叶子 value 用于提交）
    func fetchProjects(areaId: String) async throws -> [RepairProject] {
        let json = try await request(path: "repair/publish/getProjectByAreaId", form: ["areaId": areaId])
        let list = json["data"] as? [[String: Any]] ?? []
        return list.map(RepairProject.fromJson)
    }

    func fetchBookDates() async throws -> [String] {
        let json = try await request(path: "repair/publish/getBookDate")
        return (json["data"] as? [String]) ?? []
    }

    func fetchBookTimes(bookDate: String) async throws -> [String] {
        let json = try await request(path: "repair/publish/getBookTime", form: ["bookDate": bookDate])
        return (json["data"] as? [String]) ?? []
    }

    /// 受理部门预取（供 publish 的 acceptDept 字段）
    func fetchAcceptDept(areaId: String, projectId: String) async throws -> RepairAcceptDept? {
        let json = try await request(
            path: "repair/publish/getAcceptUserByAreaIdAndProjectId",
            form: ["areaId": areaId, "projectId": projectId]
        )
        guard let data = json["data"] as? [String: Any] else { return nil }
        if let dept = data["dept"] as? [String: Any] {
            return RepairAcceptDept.fromJson(dept)
        }
        if let users = data["users"] as? [[String: Any]], let first = users.first {
            return RepairAcceptDept.fromJson(first)
        }
        return nil
    }

    /// 我的工单（manager/activeTemplateData/list，search 为 JSON 数组字符串）
    func fetchMyTickets(userId: String) async throws -> [RepairTicket] {
        let search: [[String: String]] = [
            ["andOr": "and", "searchField": "createUser", "operator": "=", "searchValue": userId],
            ["andOr": "and", "searchField": "systemCode", "operator": "=", "searchValue": "newRepair"],
        ]
        let searchData = try JSONSerialization.data(withJSONObject: search)
        let json = try await request(
            path: "manager/activeTemplateData/list",
            form: [
                "search": String(data: searchData, encoding: .utf8) ?? "[]",
                "order": "createTime desc",
            ]
        )
        let list = json["data"] as? [[String: Any]] ?? []
        return list.map(RepairTicket.fromJson)
            .sorted { $0.sortKey > $1.sortKey }
    }

    func fetchTicketDetail(id: String) async throws -> RepairTicketDetail {
        let json = try await request(path: "repair/repairInfo/get", form: ["id": id])
        guard let data = json["data"] as? [String: Any] else {
            throw SCUError.service("工单详情解析失败")
        }
        return RepairTicketDetail.fromJson(data)
    }

    func fetchWithdrawAllowed(id: String) async throws -> Bool {
        let json = try await request(path: "repair/myRepair/ifAllowWithdrawMyRepair", form: ["id": id])
        return SafeJSON.bool(json["data"])
    }

    func withdrawTicket(id: String) async throws {
        _ = try await request(path: "repair/myRepair/withdrawMyRepair", form: ["id": id])
    }

    func fetchEvaluateProjects() async throws -> [RepairEvaluateProject] {
        let json = try await request(path: "repair/commontProject/getProject")
        let list = json["data"] as? [[String: Any]] ?? []
        return list.map(RepairEvaluateProject.fromJson)
    }

    func submitEvaluation(projects: [RepairEvaluateProject], content: String, repairId: String) async throws {
        var common: [[String: Any]] = []
        for project in projects {
            common.append([
                "id": project.id,
                "name": project.name,
                "weight": project.weight,
                "star": project.star,
            ])
        }
        _ = try await request(
            path: "repair/visitEvaluateUser/save",
            json: [
                "common": common,
                "content": content,
                "repairId": repairId,
                "source": "0",
                "label": projects.map(\.name).joined(separator: ","),
            ]
        )
    }

    func saveCommonAddress(_ address: RepairAddress) async throws {
        _ = try await request(
            path: "repair/userCommonAddress/save",
            json: [
                "areaId": address.areaId,
                "areaName": address.areaName,
                "addressDetail": address.addressDetail,
                "phone": address.phone,
                "userName": "",
                "ifCommon": address.isCommon ? "1" : "0",
                "id": "",
            ]
        )
    }

    /// 提交工单（payload 由页面组装）
    func submitTicket(payload: [String: Any]) async throws {
        _ = try await request(path: "repair/publish/publish", json: payload)
    }

    /// 图片上传（30s 超时；响应为明文 JSON，不做 AES）
    func uploadImage(data: Data, mimeType: String, fileName: String) async throws -> String {
        let client = try await auth.getClient()
        let tokenKey = try await requireTokenKey(client)
        let boundary = "bugaoshan-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"system\"\r\n\r\nmanager\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let resp = try await client.send(HTTPRequest(
            method: "POST",
            url: URL(string: "https://zhhq.scu.edu.cn/api/file/upload")!,
            headers: [
                "Accept": "application/json, text/plain, */*",
                "Content-Type": "multipart/form-data; boundary=\(boundary)",
                "Origin": "https://zhhq.scu.edu.cn",
                "Referer": "https://zhhq.scu.edu.cn/ihome/newrepair",
                "User-Agent": Constants.userAgent,
                "X-Requested-With": "XMLHttpRequest",
                "Token": try Self.buildToken(tokenKey: tokenKey),
                "TokenKey": tokenKey,
            ],
            body: body
        ))
        if resp.statusCode == 302 || resp.statusCode == 401 || resp.statusCode == 403 {
            throw SCUError.unauthenticated()
        }
        guard let json = try? SafeJSON.parseObject(resp.bodyString, api: "upload"),
              let path = (json["data"] as? [String: Any])?["path"] as? String, !path.isEmpty else {
            throw SCUError.service("图片上传失败")
        }
        return path
    }
}
