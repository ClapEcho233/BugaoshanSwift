import Foundation

// MARK: - CcylService 数据端点（ccyl_service.dart 数据 API 部分）

extension CcylService {

    private static var transport: HTTPTransport { URLSessionTransport() }

    private static func authHeaders(_ token: String) -> [String: String] {
        var headers = baseHeaders
        headers["token"] = token
        return headers
    }

    private static func httpPost(
        _ api: String, path: String, token: String, body: [String: Any]
    ) async throws -> [String: Any] {
        let url = URL(string: "\(apiBase)\(path)")!
        let request = HTTPRequest(
            method: "POST", url: url, headers: authHeaders(token),
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try await execute(api, request)
    }

    private static func httpGet(
        _ api: String, path: String, token: String
    ) async throws -> [String: Any] {
        let url = URL(string: "\(apiBase)\(path)")!
        let request = HTTPRequest(method: "GET", url: url, headers: authHeaders(token))
        return try await execute(api, request)
    }

    private static func execute(_ api: String, _ request: HTTPRequest) async throws -> [String: Any] {
        let resp: HTTPResponse
        do {
            resp = try await transport.request(request)
        } catch {
            throw CcylError.general("[\(api)] 网络请求失败: \(error.localizedDescription)")
        }
        guard resp.statusCode == 200 else {
            throw CcylError.general("[\(api)] HTTP 错误: \(resp.statusCode)")
        }
        let json: [String: Any]
        if let parsed = try? SafeJSON.parseObject(resp.bodyString, api: api) {
            json = parsed
        } else {
            throw CcylError.general("[\(api)] 响应解析失败")
        }
        // HTTP 200 + 业务码 401 = token 失效
        if SafeJSON.string(json["code"]) == "401" || SafeJSON.int(json["code"]) == 401 {
            throw CcylError.authExpired
        }
        return json
    }

    private static func checkCode(_ json: [String: Any], _ fallback: String) throws {
        guard SafeJSON.int(json["code"]) == 0 else {
            throw CcylError.general(SafeJSON.string(json["msg"], fallback: fallback))
        }
    }

    // MARK: 端点

    static func searchActivities(
        token: String, pageNum: Int = 1, pageSize: Int = 10,
        name: String = "", level: String = "", scoreType: String = "",
        org: String = "", order: String = "", status: String = "", quality: String = ""
    ) async throws -> [CyclActivity] {
        let json = try await httpPost(
            "list-activity-library",
            path: "/app/activity/list-activity-library",
            token: token,
            body: [
                "pn": pageNum,
                "time": String(Int(Date().timeIntervalSince1970 * 1000)),
                "ps": pageSize,
                "name": name, "level": level, "scoreType": scoreType,
                "org": org, "order": order, "status": status, "quality": quality,
            ]
        )
        try checkCode(json, "获取活动列表失败")
        return SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclActivity.fromJson)
    }

    static func getMyActivities(token: String, pageNum: Int = 1, pageSize: Int = 10) async throws -> [CyclActivity] {
        let json = try await httpPost(
            "list-mine", path: "/app/activity/list-mine", token: token,
            body: [
                "pn": pageNum,
                "time": String(Int(Date().timeIntervalSince1970 * 1000)),
                "ps": pageSize,
            ]
        )
        try checkCode(json, "获取我参与的活动失败")
        return SafeJSON.objectList(json["content"] as? [Any] ?? []).map(CyclActivity.fromJson)
    }

    static func getOrderedActivities(token: String, pageNum: Int = 1, pageSize: Int = 10, name: String = "") async throws -> [CyclActivity] {
        let json = try await httpPost(
            "list-ordered-activity-library",
            path: "/app/activity/list-ordered-activity-library",
            token: token,
            body: [
                "pn": pageNum,
                "time": String(Int(Date().timeIntervalSince1970 * 1000)),
                "ps": pageSize,
                "name": name,
            ]
        )
        try checkCode(json, "获取预约的活动失败")
        return SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclActivity.fromJson)
    }

    static func getAllOrgs(token: String) async throws -> [CyclOrg] {
        let json = try await httpPost("list-all", path: "/app/org/list-all", token: token, body: [:])
        try checkCode(json, "获取组织列表失败")
        return SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclOrg.fromJson)
    }

    struct LibDetail {
        var activityLib: CyclActivityLib
        var activities: [CyclActivity]
        var subscribed: Bool
    }

    static func getActivityLibDetail(token: String, activityLibraryId: String) async throws -> LibDetail {
        let json = try await httpGet(
            "get-lib-detail",
            path: "/app/activity/get-lib-detail/\(activityLibraryId)",
            token: token
        )
        try checkCode(json, "获取活动系列详情失败")
        guard let libJson = json["activityLib"] as? [String: Any] else {
            throw CcylError.general("活动系列数据缺失")
        }
        return LibDetail(
            activityLib: CyclActivityLib.fromJson(libJson),
            activities: SafeJSON.objectList(json["activities"] as? [Any] ?? []).map(CyclActivity.fromJson),
            subscribed: json["subscribed"] as? Bool == true
        )
    }

    static func subscribeActivity(token: String, activityLibraryId: String) async throws {
        let json = try await httpPost(
            "subscribe-act",
            path: "/app/activity/subscribe-act/\(activityLibraryId)",
            token: token, body: [:]
        )
        try checkCode(json, "预约活动失败")
    }

    static func cancelSubscribe(token: String, activityLibraryId: String) async throws {
        let json = try await httpPost(
            "cancel-subscribe",
            path: "/app/activity/cancel-subscribe/\(activityLibraryId)",
            token: token, body: [:]
        )
        try checkCode(json, "取消预约失败")
    }

    static func getActivityScoreTypes(token: String, activityLibraryId: String) async throws -> [CyclScoreType] {
        let json = try await httpPost(
            "list-activity-score",
            path: "/app/activity/list-activity-score/\(activityLibraryId)",
            token: token, body: [:]
        )
        try checkCode(json, "获取能力类型失败")
        return SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclScoreType.fromJson)
    }

    static func signUpActivity(token: String, activityId: String, scoreType: String) async throws {
        let json = try await httpPost(
            "sign-up-act", path: "/app/activity/sign-up-act", token: token,
            body: ["activityId": activityId, "scoreType": scoreType]
        )
        try checkCode(json, "报名失败")
    }

    static func cancelSignUp(token: String, activityId: String, userId: String) async throws {
        let json = try await httpPost(
            "cancel", path: "/app/activity/cancel", token: token,
            body: ["activityId": activityId, "userId": userId]
        )
        try checkCode(json, "取消报名失败")
    }

    struct ActivityDetail {
        var activity: CyclActivity
        var activityLib: CyclActivityLib?
        var isXtwRole: Bool
        var signUp: Bool
    }

    static func getActivityDetail(token: String, activityId: String) async throws -> ActivityDetail {
        let json = try await httpPost(
            "get-detail", path: "/app/activity/get-detail", token: token,
            body: ["activityId": activityId]
        )
        try checkCode(json, "获取活动详情失败")
        guard let activityJson = json["activity"] as? [String: Any] else {
            throw CcylError.general("活动数据缺失")
        }
        return ActivityDetail(
            activity: CyclActivity.fromJson(activityJson),
            activityLib: (json["activityLib"] as? [String: Any]).map(CyclActivityLib.fromJson),
            isXtwRole: json["isXtwRole"] as? Bool == true,
            signUp: json["signUp"] as? Bool == true
        )
    }

    static func getCreditList(token: String, pageNum: Int = 1, pageSize: Int = 10) async throws -> [CyclCredit] {
        let json = try await httpPost(
            "list-credit", path: "/app/credit/list", token: token,
            body: ["pn": pageNum, "ps": pageSize]
        )
        try checkCode(json, "获取成绩单失败")
        return SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclCredit.fromJson)
    }

    static func exportCreditsToEmail(token: String, creditIds: [String], email: String) async throws -> String {
        let json = try await httpPost(
            "export-pdf", path: "/app/credit/exportPdfV2", token: token,
            body: ["creditIds": creditIds.joined(separator: ","), "qqEmail": email]
        )
        try checkCode(json, "导出失败")
        return SafeJSON.string(json["msg"], fallback: "成绩单已发送至邮箱")
    }

    /// 逐 groupCode 拉字典；单个失败吞掉（authExpired 除外）
    static func getDicts(token: String, groupCodes: [String]) async throws -> [String: [CyclDict]] {
        var results: [String: [CyclDict]] = [:]
        for code in groupCodes {
            do {
                let json = try await httpPost(
                    "dict/\(code)", path: "/app/dict/query-by-group-code", token: token,
                    body: ["groupCode": code]
                )
                if SafeJSON.int(json["code"]) == 0 {
                    results[code] = SafeJSON.objectList(json["list"] as? [Any] ?? []).map(CyclDict.fromJson)
                }
            } catch let error as CcylError {
                if case .authExpired = error { throw error }
            } catch { /* 单个字典失败忽略 */ }
        }
        return results
    }
}

// MARK: - CcylApiService（token 管理 + 过期重试包装）

/// retryOnCcylAuthError：ensureAuthenticated → fn → authExpired →
/// recoverExpiredSession → fn（重试一次）；普通错误原样上抛
/// （保护报名/取消等非幂等操作不被盲目重放）。
struct CcylApiService {
    let auth: CcylAuth

    init(auth: CcylAuth) {
        self.auth = auth
    }

    private func run<T: Sendable>(_ fn: @Sendable (_ token: String) async throws -> T) async throws -> T {
        try await auth.ensureAuthenticated()
        guard let token = await auth.tokenIfBound() else {
            throw SCUError.unauthenticated("第二课堂未登录")
        }
        do {
            return try await fn(token)
        } catch CcylError.authExpired {
            let ok = await auth.recoverExpiredSession()
            guard ok else {
                throw SCUError.unauthenticated("第二课堂 token 过期，重新登录失败")
            }
            guard let newToken = await auth.tokenIfBound() else {
                throw SCUError.unauthenticated("第二课堂未登录")
            }
            return try await fn(newToken)
        }
    }

    // MARK: - API 表面（转发到 CcylService 静态方法）

    func searchActivities(pageNum: Int = 1, pageSize: Int = 10, name: String = "") async throws -> [CyclActivity] {
        try await run { try await CcylService.searchActivities(token: $0, pageNum: pageNum, pageSize: pageSize, name: name) }
    }

    func getMyActivities(pageNum: Int = 1, pageSize: Int = 10) async throws -> [CyclActivity] {
        try await run { try await CcylService.getMyActivities(token: $0, pageNum: pageNum, pageSize: pageSize) }
    }

    func getOrderedActivities(pageNum: Int = 1, pageSize: Int = 10, name: String = "") async throws -> [CyclActivity] {
        try await run { try await CcylService.getOrderedActivities(token: $0, pageNum: pageNum, pageSize: pageSize, name: name) }
    }

    func getAllOrgs() async throws -> [CyclOrg] {
        try await run { try await CcylService.getAllOrgs(token: $0) }
    }

    func getActivityLibDetail(activityLibraryId: String) async throws -> CcylService.LibDetail {
        try await run { try await CcylService.getActivityLibDetail(token: $0, activityLibraryId: activityLibraryId) }
    }

    func subscribeActivity(activityLibraryId: String) async throws {
        try await run { try await CcylService.subscribeActivity(token: $0, activityLibraryId: activityLibraryId) }
    }

    func cancelSubscribe(activityLibraryId: String) async throws {
        try await run { try await CcylService.cancelSubscribe(token: $0, activityLibraryId: activityLibraryId) }
    }

    func getActivityScoreTypes(activityLibraryId: String) async throws -> [CyclScoreType] {
        try await run { try await CcylService.getActivityScoreTypes(token: $0, activityLibraryId: activityLibraryId) }
    }

    func signUpActivity(activityId: String, scoreType: String) async throws {
        try await run { try await CcylService.signUpActivity(token: $0, activityId: activityId, scoreType: scoreType) }
    }

    func cancelSignUp(activityId: String) async throws {
        let userId = await auth.user()?.id ?? ""
        try await run { try await CcylService.cancelSignUp(token: $0, activityId: activityId, userId: userId) }
    }

    func getActivityDetail(activityId: String) async throws -> CcylService.ActivityDetail {
        try await run { try await CcylService.getActivityDetail(token: $0, activityId: activityId) }
    }

    func getCreditList(pageNum: Int = 1, pageSize: Int = 10) async throws -> [CyclCredit] {
        try await run { try await CcylService.getCreditList(token: $0, pageNum: pageNum, pageSize: pageSize) }
    }

    func exportCreditsToEmail(creditIds: [String], email: String) async throws -> String {
        try await run { try await CcylService.exportCreditsToEmail(token: $0, creditIds: creditIds, email: email) }
    }

    func getDicts(groupCodes: [String]) async throws -> [String: [CyclDict]] {
        try await run { try await CcylService.getDicts(token: $0, groupCodes: groupCodes) }
    }

    // MARK: - 绑定

    /// OAuth code 手动绑定（CcylBindPage 用）
    func loginWithOAuthCode(_ code: String) async throws {
        try await auth.loginWithCode(code: code)
    }
}
