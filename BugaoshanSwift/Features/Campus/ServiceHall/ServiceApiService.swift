import Foundation

/// 网上办事大厅 API（service_api_service.dart）。
/// service.scu.edu.cn 动态表单事项（350 离校请假 / 337 返校报备 /
/// 356 暑假离校 / 357 留校登记）共用同一套引擎；认证经 ServiceAuth（CAS vjuid）。
struct ServiceApiService {

    let auth: SsoRelayAuth
    let log: AuthLogger

    init(auth: SsoRelayAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    static let base = URL(string: "https://service.scu.edu.cn")!

    static let leaveAppId = "350"
    static let returnReportAppId = "337"
    static let summerLeaveAppId = "356"
    static let stayRegisterAppId = "357"

    /// 默认发起人部门 id（select-department 确认前的兜底）
    static let defaultStarterDepartId = "395876"

    /// DataSource_85（辅导员数据源）的配置 id
    static let tutorDataSourceId = "8"

    private static var paths: [String: String] {
        [
            "formStartData": "/site/form/start-data",
            "processStartInfo": "/site/process/start-info",
            "processVariables": "/site/process/variables",
            "selectDepartment": "/site/user/select-department",
            "dataSourceDetail": "/site/data-source/detail",
            "attachUpload": "/site/attach/auth-upload",
            "provinceDict": "/api/dictionary/province",
            "formPlugins": "/site/form/get-formv",
            "launch": "/site/apps/launch",
            "instList": "/site/process/inst-list",
        ]
    }

    private var formHeaders: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/x-www-form-urlencoded",
            "Origin": Self.base.absoluteString,
            "Referer": Self.base.absoluteString,
            "User-Agent": Constants.userAgent,
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    private var jsonHeaders: [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "Origin": Self.base.absoluteString,
            "Referer": Self.base.absoluteString,
            "User-Agent": Constants.userAgent,
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    // MARK: - 响应解码

    static func checkSessionExpiry(body: String, statusCode: Int) throws {
        if statusCode == 302 || statusCode == 401 || statusCode == 403
            || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
    }

    private func decodeResponse(_ body: String, statusCode: Int) throws -> [String: Any] {
        try Self.checkSessionExpiry(body: body, statusCode: statusCode)
        let json = try SafeJSON.parseObject(body, api: "service")
        let code = ServiceFormDefinition.anyToString(json["e"] ?? "")
        // e:10042 = vjuid 缺失/失效，交给认证层重试
        if code == "10042" {
            throw SCUError.unauthenticated("办事大厅会话已失效")
        }
        if code != "0" {
            log.w("SERVICE", "业务错误 e=\(json["e"] ?? "") m=\(json["m"] ?? "") status=\(statusCode)")
        }
        return json
    }

    private static func url(_ pathKey: String, query: [String: String]) -> URL {
        var components = URLComponents(
            string: Self.base.absoluteString + (paths[pathKey] ?? "")
        )!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    // MARK: - 表单定义 / 流程 / 插件

    /// 表单 schema（字段 key、权限、预填）：GET /site/form/start-data
    func fetchFormSchema(
        _ appId: String,
        starterDepartId: String = ServiceApiService.defaultStarterDepartId
    ) async throws -> ServiceFormDefinition {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("formStartData", query: [
                "app_id": appId, "node_id": "", "userview": "1",
                "agent_uid": "", "starter_depart_id": starterDepartId,
            ])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        if SafeJSON.int(json["e"]) == 0, let d = json["d"] as? [String: Any] {
            return ServiceFormDefinition.fromJson(d)
        }
        throw SCUError.service(SafeJSON.string(json["m"], fallback: "获取表单定义失败"))
    }

    /// 流程信息（含 bpmn_id 与 form 列表）：GET /site/process/start-info。返回原始 d。
    func fetchStartInfo(_ appId: String) async throws -> [String: Any] {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("processStartInfo", query: ["app_id": appId])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        if SafeJSON.int(json["e"]) == 0, let d = json["d"] as? [String: Any] {
            return d
        }
        throw SCUError.service(SafeJSON.string(json["m"], fallback: "获取流程信息失败"))
    }

    /// 表单插件定义（主来源）：GET /site/form/get-formv。返回原始 d。
    func fetchFormPlugins(
        bpmnId: String,
        formId: String,
        starterDepartId: String = ServiceApiService.defaultStarterDepartId
    ) async throws -> [String: Any] {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("formPlugins", query: [
                "id": formId, "bpmn_id": bpmnId, "sess_id": "0", "report_id": "0",
                "agent_uid": "", "starter_depart_id": starterDepartId,
            ])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        if SafeJSON.int(json["e"]) == 0, let d = json["d"] as? [String: Any] {
            return d
        }
        throw SCUError.service(SafeJSON.string(json["m"], fallback: "获取表单插件失败"))
    }

    // MARK: - 发起人部门

    /// 发起人部门 id：d.depart[] 中 select==1 项的 college；解析不出返回 nil。
    func fetchStarterDepartId(_ appId: String) async throws -> String? {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("selectDepartment", query: ["app_id": appId])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        guard SafeJSON.int(json["e"]) == 0, let d = json["d"] else { return nil }
        return Self.extractDepartId(d)
    }

    private static func extractDepartId(_ d: Any) -> String? {
        func pickCollege(_ item: Any) -> String? {
            guard let item = item as? [String: Any] else { return nil }
            for k in ["college", "depart_id", "department_id", "value", "id"] {
                if let v = item[k] {
                    let s = ServiceFormDefinition.anyToString(v)
                    if !s.isEmpty && s != "0" {
                        return s
                    }
                }
            }
            return nil
        }

        if let map = d as? [String: Any] {
            if let depart = map["depart"] as? [Any], !depart.isEmpty {
                for item in depart {
                    if let m = item as? [String: Any],
                       ServiceShowHideRule.toInt(m["select"], fallback: -1) == 1,
                       let id = pickCollege(item) {
                        return id
                    }
                }
                return pickCollege(depart[0])
            }
            if let direct = pickCollege(map) {
                return direct
            }
            let list = map["list"] ?? map["data"]
            if let list = list as? [Any], !list.isEmpty {
                return pickCollege(list[0])
            }
        } else if let list = d as? [Any], !list.isEmpty {
            return pickCollege(list[0])
        }
        return nil
    }

    // MARK: - DataSource 取数

    /// DataSource 字段原始结果（如辅导员）。失败返回 nil（不阻塞提交）。
    func fetchDataSourceValue(
        appId: String,
        ref: ServiceDataSourceRef,
        starterDepartId: String = ServiceApiService.defaultStarterDepartId
    ) async throws -> [String: Any]? {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            var parts = [
                "id=\(FormEncoding.encode(ref.id))",
                "inst_id=0",
                "app_id=\(FormEncoding.encode(appId))",
                "form_version_id=\(FormEncoding.encode(ref.formVersionId))",
                "component=\(FormEncoding.encode(ref.component))",
                "params[formId]=\(FormEncoding.encode(ref.formId))",
                "params[pluginKey]=\(FormEncoding.encode(ref.component))",
                "agent_uid=",
                "starter_depart_id=\(FormEncoding.encode(starterDepartId))",
            ]
            for (k, v) in ref.configure {
                parts.append("configure[\(FormEncoding.encode(k))]=\(FormEncoding.encode(v))")
            }
            let url = URL(string: "\(Self.base.absoluteString)/site/data-source/detail")!
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url, headers: self.formHeaders,
                body: Data(parts.joined(separator: "&").utf8)
            ))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        guard SafeJSON.int(json["e"]) == 0, let d = json["d"] else {
            log.w("SERVICE", "fetchDataSourceValue 失败 e=\(json["e"] ?? "") m=\(json["m"] ?? "")")
            return nil
        }
        return d as? [String: Any]
    }

    // MARK: - 省市区字典

    /// 省市区字典（Region 三级联动）：返回原始列表（d / d.list / d.children）。
    func fetchProvinces() async throws -> [Any] {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("provinceDict", query: [
                "agent_uid": "", "starter_depart_id": "395876",
            ])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        guard SafeJSON.int(json["e"]) == 0, let d = json["d"] else {
            log.w("SERVICE", "fetchProvinces 失败 e=\(json["e"] ?? "") m=\(json["m"] ?? "")")
            return []
        }
        if let list = d as? [Any] { return list }
        if let map = d as? [String: Any] {
            if let list = map["list"] as? [Any] { return list }
            if let children = map["children"] as? [Any] { return children }
        }
        log.w("SERVICE", "fetchProvinces 未知结构")
        return []
    }

    // MARK: - 附件上传

    /// 上传附件：POST /site/attach/auth-upload?category=all&inst_id=0，multipart 字段 upfile。
    /// 响应 {url,size,title,original,state,type,id}——**没有 e 字段**，可能双重编码。
    func uploadAttachment(
        fileData: Data,
        fileName: String,
        mimeType: String,
        appId: String = ServiceApiService.leaveAppId
    ) async throws -> ServiceAttachment {
        try await withAuthRetry({ try await self.auth.getClient() }) { client in
            let boundary = "bugaoshan-\(UUID().uuidString)"
            var body = Data()
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"upfile\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
            body.append(fileData)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            let url = URL(string: "\(Self.base.absoluteString)/site/attach/auth-upload?category=all&inst_id=0")!
            let resp = try await client.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/plain, */*",
                    "Content-Type": "multipart/form-data; boundary=\(boundary)",
                    "Origin": Self.base.absoluteString,
                    "Referer": "\(Self.base.absoluteString)/v2/matter/start?id=\(appId)",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: body
            ))
            let bodyText = resp.bodyString
            try Self.checkSessionExpiry(body: bodyText, statusCode: resp.statusCode)
            // 先解一层，若为 JSON 字符串再解一层
            guard let data = bodyText.data(using: .utf8) else {
                throw SCUError.service("上传失败")
            }
            var decoded: Any
            do {
                decoded = try JSONSerialization.jsonObject(with: data)
            } catch {
                log.w("SERVICE", "uploadAttachment 响应非 JSON: \(SafeJSON.preview(bodyText))")
                throw SCUError.service("上传失败")
            }
            if let s = decoded as? String, let inner = s.data(using: .utf8),
               let innerDecoded = try? JSONSerialization.jsonObject(with: inner) {
                decoded = innerDecoded
            }
            guard let json = decoded as? [String: Any] else {
                throw SCUError.service("上传失败")
            }
            let hasUrl = json["url"] != nil
            let state = ServiceFormDefinition.anyToString(json["state"] ?? "")
            let uploadOk = hasUrl || state == "SUCCESS"
            guard uploadOk, json["id"] != nil else {
                log.w("SERVICE", "uploadAttachment 失败: \(json)")
                throw SCUError.service("上传失败")
            }
            let id = ServiceFormDefinition.anyToString(json["id"] ?? "")
            let original = ServiceFormDefinition.anyToString(json["original"] ?? "")
            let attachment = ServiceAttachment(
                name: original.isEmpty ? fileName : original,
                url: "\(Self.base.absoluteString)/site/attach/auth-download?file_id=\(id)",
                id: id
            )
            log.i("SERVICE", "uploadAttachment -> id=\(id) name=\(original)")
            return attachment
        }
    }

    // MARK: - 提交 / 我的申请

    /// 提交事项：POST /site/apps/launch。formData 是 form_data 完整 Map（key 为表单 id）。
    func submitMatter(
        _ appId: String,
        formData: [String: Any],
        starterDepartId: String = ServiceApiService.defaultStarterDepartId
    ) async throws {
        let data: [String: Any] = [
            "app_id": appId,
            "node_id": "",
            "form_data": formData,
            "userview": 1,
        ]
        let dataJson: String
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.withoutEscapingSlashes]),
           let text = String(data: encoded, encoding: .utf8) {
            dataJson = text
        } else {
            throw SCUError.service("提交数据组装失败")
        }
        let body = [
            "data=\(FormEncoding.encode(dataJson))",
            "step=0",
            "agent_uid=",
            "starter_depart_id=\(FormEncoding.encode(starterDepartId))",
        ].joined(separator: "&")
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Self.base.absoluteString)/site/apps/launch")!
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url, headers: self.formHeaders,
                body: Data(body.utf8)
            ))
            let json = try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
            if SafeJSON.int(json["e"]) != 0 {
                throw SCUError.service(SafeJSON.string(json["m"], fallback: "提交失败"))
            }
        }
    }

    /// 我的申请：status 0=全部 / 1=进行中+草稿 / 3=已完成。行内实际 status=2、
    /// inst_status 为中文文本。
    func fetchMyApplications(status: Int = 0, page: Int = 1) async throws -> [[String: Any]] {
        let json = try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = Self.url("instList", query: [
                "p": String(page), "page_size": "20", "status": String(status),
                "keyword": "", "time_lower": "", "time_upper": "",
                "y": "", "task_name": "",
            ])
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.jsonHeaders))
            return try self.decodeResponse(resp.bodyString, statusCode: resp.statusCode)
        }
        guard SafeJSON.int(json["e"]) == 0, let d = json["d"] else { return [] }
        if let map = d as? [String: Any], let list = map["list"] as? [[String: Any]] {
            return list
        }
        if let list = d as? [[String: Any]] {
            return list
        }
        return []
    }
}
