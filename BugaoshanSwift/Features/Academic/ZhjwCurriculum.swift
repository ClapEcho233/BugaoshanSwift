import Foundation

/// 班级课表 + 课程课表 API（zhjw_api_service.dart 对应部分）。
/// 两者共用 ClassScheduleInquiryItem 课表结构；列表端点均分页（默认 30/页）。
extension ZhjwApiService {

    private static var ajaxHeaders: [String: String] {
        [
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "Referer": "\(Constants.zhjwBase)/student/teachingResources/classCurriculum/index",
            "User-Agent": Constants.userAgent,
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    private static func ajaxHeaders(referer: String) -> [String: String] {
        [
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "Referer": referer,
            "User-Agent": Constants.userAgent,
            "X-Requested-With": "XMLHttpRequest",
        ]
    }

    // MARK: - 班级课表

    struct ClassScheduleIndex {
        var semesters: [CurriculumSemesterOption]
        var grades: [String]
        var departments: [DepartmentOption]
    }

    /// 首页筛选选项（executiveEducationPlanNum / yearNum / departmentNum 三个下拉）
    func fetchClassScheduleInquiryIndex() async throws -> ClassScheduleIndex {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/classCurriculum/index")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)

            let semesters = Self.parseSelectOptions(html: body, selectId: "executiveEducationPlanNum")
                .filter { !$0.value.isEmpty }
                .map { CurriculumSemesterOption(value: $0.value, label: $0.label) }
            let grades = Self.parseSelectOptions(html: body, selectId: "yearNum")
                .filter { !$0.value.isEmpty }
                .map(\.value)
            let departments = Self.parseSelectOptions(html: body, selectId: "departmentNum")
                .filter { !$0.value.isEmpty }
                .map { DepartmentOption(value: $0.value, name: $0.label) }
            return ClassScheduleIndex(semesters: semesters, grades: grades, departments: departments)
        }
    }

    /// 院系 → 专业列表（subjectJson）
    func fetchSubjectsByDepartment(_ departmentNum: String) async throws -> [SubjectOption] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/gradeAndClassCurriculum/subjectJson?departmentNum=\(FormEncoding.encodeComponent(departmentNum))")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: Self.ajaxHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let list = try SafeJSON.parseAnyArray(body, api: "subjectJson")
            return SafeJSON.objectList(list).map(SubjectOption.fromJson)
        }
    }

    /// 年级 + 院系（+专业）→ 班级筛选选项（classJson）
    func fetchClassOptions(yearNum: String, departmentNum: String, subjectNum: String = "") async throws -> [ClassOption] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/gradeAndClassCurriculum/classJson?departmentNum=\(FormEncoding.encodeComponent(departmentNum))&subjectNum=\(FormEncoding.encodeComponent(subjectNum))&yearNum=\(FormEncoding.encodeComponent(yearNum))")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: Self.ajaxHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let list = try SafeJSON.parseAnyArray(body, api: "classJson")
            return SafeJSON.objectList(list).map(ClassOption.fromJson)
        }
    }

    struct ClassListResult {
        var classes: [ClassInfo]
        var totalCount: Int
    }

    /// 班级列表搜索（POST search；响应是 JSON 数组，取 json[0]）
    func fetchClassList(
        pageNum: Int = 1,
        pageSize: Int = 30,
        executiveEducationPlanNum: String = "",
        yearNum: String = "",
        departmentNum: String = "",
        subjectNum: String = "",
        classNum: String = ""
    ) async throws -> ClassListResult {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/classCurriculum/search")!
            let form = [
                "executiveEducationPlanNum=\(FormEncoding.encode(executiveEducationPlanNum))",
                "yearNum=\(FormEncoding.encode(yearNum))",
                "departmentNum=\(FormEncoding.encode(departmentNum))",
                "subjectNum=\(FormEncoding.encode(subjectNum))",
                "classNum=\(FormEncoding.encode(classNum))",
                "pageNum=\(pageNum)",
                "pageSize=\(pageSize)",
            ].joined(separator: "&")
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/teachingResources/classCurriculum/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let array = try SafeJSON.parseAnyArray(body, api: "classCurriculum-search")
            let first = (array.first as? [String: Any]) ?? [:]
            let records = first["records"] as? [[String: Any]] ?? []
            let pageContext = first["pageContext"] as? [String: Any] ?? [:]
            let totalCount = SafeJSON.int(pageContext["totalCount"])
            return ClassListResult(classes: records.map(ClassInfo.fromJson), totalCount: totalCount)
        }
    }

    /// 指定班级的课表（GET callback；响应 json[0] 本身是条目数组）
    func fetchClassSchedule(planCode: String, classCode: String) async throws -> [ClassScheduleInquiryItem] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/classCurriculum/searchCurriculumInfo/callback?planCode=\(FormEncoding.encodeComponent(planCode))&classCode=\(FormEncoding.encodeComponent(classCode))")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: Self.ajaxHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let array = try SafeJSON.parseAnyArray(body, api: "classCurriculum-callback")
            let list = SafeJSON.objectList((array.first as? [Any]) ?? [])
            return list.map(ClassScheduleInquiryItem.fromJson)
        }
    }

    // MARK: - 课程课表

    struct CourseCurriculumIndex {
        var semesters: [CurriculumSemesterOption]
        var departments: [DepartmentOption]
        var categories: [CourseCategoryOption]
    }

    /// 首页筛选选项（zxjxjhh / kkxsh / kclb 三个下拉）
    func fetchCourseCurriculumIndex() async throws -> CourseCurriculumIndex {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/courseCurriculum/index")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)

            let semesters = Self.parseSelectOptions(html: body, selectId: "zxjxjhh")
                .filter { !$0.value.isEmpty }
                .map { CurriculumSemesterOption(value: $0.value, label: $0.label) }
            let departments = Self.parseSelectOptions(html: body, selectId: "kkxsh")
                .filter { !$0.value.isEmpty }
                .map { DepartmentOption(value: $0.value, name: $0.label) }
            let categories = Self.parseSelectOptions(html: body, selectId: "kclb")
                .filter { !$0.value.isEmpty }
                .map { CourseCategoryOption(code: $0.value, name: $0.label) }
            return CourseCurriculumIndex(semesters: semesters, departments: departments, categories: categories)
        }
    }

    struct CourseListResult {
        var courses: [CourseSectionInfo]
        var totalCount: Int
    }

    /// 课程列表搜索（POST search；响应为对象 json.records + json.pageContext.totalCount）
    func fetchCourseList(
        pageNum: Int = 1,
        pageSize: Int = 30,
        semester: String = "",
        department: String = "",
        courseName: String = "",
        courseCode: String = "",
        courseSeq: String = "",
        category: String = ""
    ) async throws -> CourseListResult {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/courseCurriculum/search")!
            let form = [
                "zxjxjhh=\(FormEncoding.encode(semester))",
                "kkxsh=\(FormEncoding.encode(department))",
                "kcm=\(FormEncoding.encode(courseName))",
                "kch=\(FormEncoding.encode(courseCode))",
                "kxh=\(FormEncoding.encode(courseSeq))",
                "kclb=\(FormEncoding.encode(category))",
                "pageNum=\(pageNum)",
                "pageSize=\(pageSize)",
            ].joined(separator: "&")
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/teachingResources/courseCurriculum/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            // 网关异常时可能返回非 JSON 文本（如 502 页面）
            let json = try SafeJSON.parseObject(body, api: "courseCurriculum-search")
            let records = json["records"] as? [[String: Any]] ?? []
            let pageContext = json["pageContext"] as? [String: Any] ?? [:]
            let totalCount = SafeJSON.int(pageContext["totalCount"])
            return CourseListResult(courses: records.map(CourseSectionInfo.fromJson), totalCount: totalCount)
        }
    }

    /// 指定教学班的课表（响应结构 [[item, …]]：外层数组首元素才是条目列表）
    func fetchCourseSchedule(planCode: String, courseCode: String, courseSequenceCode: String) async throws -> [ClassScheduleInquiryItem] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = URL(string: "\(Constants.zhjwBase)/student/teachingResources/courseCurriculum/searchCurriculum/callback?planCode=\(FormEncoding.encodeComponent(planCode))&courseCode=\(FormEncoding.encodeComponent(courseCode))&courseSequenceCode=\(FormEncoding.encodeComponent(courseSequenceCode))")!
            let resp = try await $0.send(HTTPRequest(
                method: "GET", url: url,
                headers: Self.ajaxHeaders(referer: "\(Constants.zhjwBase)/student/teachingResources/courseCurriculum/index")
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            let outer = try SafeJSON.parseAnyArray(body, api: "courseCurriculum-searchCurriculum")
            guard let first = outer.first else { return [] }
            guard let inner = first as? [Any] else {
                throw SCUError.service("课程课表数据格式异常：外层元素不是数组")
            }
            return SafeJSON.objectList(inner).map(ClassScheduleInquiryItem.fromJson)
        }
    }
}
