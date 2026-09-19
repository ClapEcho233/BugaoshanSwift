import Foundation

/// 教务扩展端点：空闲教室 + 培养方案（zhjw_api_service.dart 对应部分）
extension ZhjwApiService {

    private static func attrValue(_ html: String, id: String) -> String? {
        let pattern = #"<input[^>]+id="\#(id)"[^>]+value='([^']+)'""#
        guard let match = html.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let sub = String(html[match])
        guard let firstQuote = sub.firstIndex(of: "'"),
              let lastQuote = sub.lastIndex(of: "'"), firstQuote < lastQuote else {
            return nil
        }
        return String(sub[sub.index(after: firstQuote)..<lastQuote])
    }

    // MARK: - 空闲教室

    struct ClassroomIndex {
        var campuses: [ClassroomCampus]
        var buildings: [ClassroomBuilding]
    }

    /// index 页隐藏 input（单引号 attr）内是 JSON 数组
    func fetchClassroomIndex() async throws -> ClassroomIndex {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/teachingResources/classroomUseStatus/index")
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)

            var campuses: [ClassroomCampus] = []
            var buildings: [ClassroomBuilding] = []
            if let campusJson = Self.attrValue(body, id: "xqList"),
               let data = campusJson.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                campuses = list.map {
                    ClassroomCampus(
                        campusName: SafeJSON.string($0["campusName"] ?? $0["name"]),
                        campusNumber: SafeJSON.string($0["campusNumber"] ?? $0["code"]))
                }
            }
            if let buildingJson = Self.attrValue(body, id: "jxlList"),
               let data = buildingJson.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                buildings = list.map { item in
                    let id = item["id"] as? [String: Any] ?? [:]
                    return ClassroomBuilding(
                        campusNumber: SafeJSON.string(id["campusNumber"]),
                        teachingBuildingNumber: SafeJSON.string(id["teachingBuildingNumber"]),
                        teachingBuildingName: SafeJSON.string(item["teachingBuildingName"]))
                }
            }
            guard !campuses.isEmpty || !buildings.isEmpty else {
                throw SCUError.service("空闲教室索引解析失败", statusCode: resp.statusCode)
            }
            return ClassroomIndex(campuses: campuses, buildings: buildings)
        }
    }

    func fetchClassroomTypes(
        campusNumber: String, buildingNumber: String,
        campusName: String, buildingName: String
    ) async throws -> [ClassroomType] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let path = "student/teachingResources/classroomUseStatus/\(campusNumber)/\(buildingNumber)/\(FormEncoding.encodeComponent(campusName))/\(FormEncoding.encodeComponent(buildingName))"
            let url = URL(string: "\(Constants.zhjwBase)/\(path)")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            guard let raw = Self.attrValue(body, id: "classroomTypes"),
                  let data = raw.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return list.map {
                ClassroomType(
                    code: SafeJSON.string($0["classroomtypecode"] ?? $0["code"]),
                    name: SafeJSON.string($0["classroomtypename"] ?? $0["name"]))
            }
        }
    }

    struct ClassroomQuery {
        var campusNumber: String
        var buildingNumber: String
        var typeCode: String
        var sectionFrom: Int
        var sectionTo: Int
        var date: String
    }

    func fetchClassroomAvailability(_ query: ClassroomQuery) async throws -> ClassroomQueryResult {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/teachingResources/classroomUseStatus/jasInfo")
            let form = [
                "xqh=\(query.campusNumber)",
                "jxlh=\(query.buildingNumber)",
                "jslx=\(query.typeCode)",
                "jasm=",
                "zwFrom=\(query.sectionFrom)",
                "zwTo=\(query.sectionTo)",
                "searchDate=\(query.date)",
            ].joined(separator: "&")
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/teachingResources/classroomUseStatus/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let json = try SafeJSON.parseObject(body, api: "jasInfo")
            return ClassroomQueryResult.fromJson(json)
        }
    }

    // MARK: - 培养方案

    func fetchTrainProgramFilters() async throws -> (colleges: [College], grades: [Grade]) {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/comprehensiveQuery/search/trainProgram/index")
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let colleges = Self.parseSelectOptions(html: body, selectId: "xsh").map {
                College(value: $0.value, name: $0.label)
            }
            let grades = Self.parseSelectOptions(html: body, selectId: "nj").map {
                Grade(value: $0.value, label: $0.label)
            }
            return (colleges, grades)
        }
    }

    func searchTrainPrograms(college: String, grade: String) async throws -> [TrainProgram] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/comprehensiveQuery/search/trainProgram/load")
            let form = [
                "famc=", "jhmc=", "nj=\(grade)", "xw=",
                "xzlx=", "xdlx=00001", "xsh=\(college)",
                "pageNum=1", "pageSize=100",
            ].joined(separator: "&")
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/comprehensiveQuery/search/trainProgram/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let json = try SafeJSON.parseObject(body, api: "trainProgram-load")
            let data = json["data"] as? [String: Any]
            let records = (data?["records"] as? [[String: Any]]) ?? []
            return records.map(TrainProgram.fromJson)
        }
    }

    func fetchTrainProgramDetail(id: String) async throws -> [TrainProgramCourse] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/comprehensiveQuery/search/trainProgram/detail")
            let form = "fajhh=\(FormEncoding.encode(id))&lx=1"
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/comprehensiveQuery/search/trainProgram/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let json = try SafeJSON.parseObject(body, api: "trainProgram-detail")
            // 课程清单在 data.records 或 data 里直接展开
            let data = json["data"] as? [String: Any]
            let list = (data?["records"] as? [[String: Any]])
                ?? (json["data"] as? [[String: Any]])
                ?? []
            return list.map(TrainProgramCourse.fromJson)
        }
    }
}
