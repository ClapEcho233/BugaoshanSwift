import Foundation

/// 考表条目（对应 exam_info.dart + _parseExamCards）
struct ExamInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(courseName)-\(date)-\(timeRange)" }
    var courseName: String
    var week: String
    var date: String          // yyyy-MM-dd
    var weekday: String       // 星期X
    var timeRange: String     // HH:mm-HH:mm
    var location: String
    var seatNumber: String
    var ticketNumber: String
    var tip: String

    var isPast: Bool {
        // 按结束时间判断
        let parts = timeRange.split(separator: "-")
        guard parts.count == 2,
              let day = ScheduleConfig.parseDate(date),
              let endHM = parts[1].split(separator: ":") as? [Substring],
              endHM.count == 2,
              let hour = Int(endHM[0]), let minute = Int(endHM[1]) else {
            return false
        }
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        guard let end = comps.date else { return false }
        return end < Date()
    }
}

extension ZhjwApiService {

    /// 考表 HTML 解析（widget-box 块 + 逐字段 first-match）
    static func parseExamCards(_ html: String) -> [ExamInfo] {
        let blockRegex = try! NSRegularExpression(
            pattern: #"<div class="widget-box widget-color-\w+(?: collapsed)?">(.*?)</div>\s*</div>\s*</div>\s*</div>"#,
            options: [.dotMatchesLineSeparators]
        )
        let full = NSRange(html.startIndex..., in: html)
        var results: [ExamInfo] = []
        for match in blockRegex.matches(in: html, range: full) {
            guard let blockRange = Range(match.range(at: 1), in: html) else { continue }
            let block = String(html[blockRange])

            func field(_ pattern: String, group: Int = 1) -> String? {
                firstMatch(block, pattern: pattern, group: group)
            }

            let courseName = (field(#"<h5 class="widget-title smaller">\s*(.*?)\s*</h5>"#) ?? "未知")
                .replacingOccurrences(of: "（已结束）", with: "")
                .replacingOccurrences(of: "(已结束)", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard courseName != "未知" || field(#"(\d+)周"#) != nil else { continue }

            results.append(ExamInfo(
                courseName: courseName,
                week: field(#"(\d+)周"#) ?? "",
                date: field(#"(\d{4}-\d{2}-\d{2})\s*&nbsp;"#) ?? "未知",
                weekday: field(#"(星期[一二三四五六日])"#) ?? "未知",
                timeRange: field(#"&nbsp;(\d{2}:\d{2}-\d{2}:\d{2})"#) ?? "未知",
                location: (field(#"地点:&nbsp;(.+?)</br>"#) ?? "未知")
                    .replacingOccurrences(of: "&nbsp;", with: " "),
                seatNumber: field(#"座位号:&nbsp;(\d+)"#) ?? "未知",
                ticketNumber: field(#"准考证号:&nbsp;(.*?)</br>"#) ?? "",
                tip: field(#"考试提示信息：&nbsp;(.*?)</span>"#) ?? "无"
            ))
        }
        return results
    }

    /// 拉取考表页并解析
    func fetchExamPlan() async throws -> [ExamInfo] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/examinationManagement/examPlan/index")
            let resp = try await $0.send(HTTPRequest(
                method: "GET", url: url, headers: self.htmlHeaders
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            try Self.checkRateLimit(body)
            return Self.parseExamCards(body)
        }
    }

    private static func firstMatch(_ text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges > group,
               let r = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[r])
    }
}

// MARK: - 体测 API（对应 fitness_api_service.dart）

struct FitnessApiService {

    let auth: SsoRelayAuth
    let log: AuthLogger

    init(auth: SsoRelayAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    static let base = URL(string: "https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php")!

    static let headers: [String: String] = [
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
        "Cache-Control": "no-cache",
        "Content-Type": "application/x-www-form-urlencoded",
        "Origin": "https://pead.scu.edu.cn",
        "Pragma": "no-cache",
        "Referer": "https://pead.scu.edu.cn/bdlp_h5_fitness_test/public/index.php/index/index",
        "User-Agent": Constants.userAgent,
        "X-Requested-With": "XMLHttpRequest",
        "sec-ch-ua": #""Microsoft Edge";v="147", "Not.A Brand";v="8", "Chromium";v="147""#,
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": #""Windows""#,
    ]

    struct FitnessScore: Equatable, Sendable {
        var raw: [String: String]

        static func fromJson(_ data: [String: Any]) -> FitnessScore {
            var raw: [String: String] = [:]
            for (key, value) in data {
                raw[key] = SafeJSON.string(value)
            }
            return FitnessScore(raw: raw)
        }
    }

    struct FitnessNotice: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var content: String
        var time: String

        static func fromJson(_ json: [String: Any]) -> FitnessNotice {
            FitnessNotice(
                id: SafeJSON.string(json["id"]),
                title: SafeJSON.string(json["title"]),
                content: SafeJSON.string(json["content"]),
                time: SafeJSON.string(json["create_time"] ?? json["createtime"])
            )
        }
    }

    private static func decode(_ resp: HTTPResponse, api: String) throws -> [String: Any] {
        guard let json = try? SafeJSON.parseObject(resp.bodyString, api: api) else {
            throw SCUError.service("[\(api)] JSON 解析失败")
        }
        let status = SafeJSON.string(json["status"])
        if status == "1" {
            return json
        }
        let message = SafeJSON.string(json["info"], fallback: "体测服务请求失败")
        if message.contains("登录信息失效") || message.contains("请重新登录") {
            throw SCUError.unauthenticated(message)
        }
        throw SCUError.service(message)
    }

    func fetchNotices() async throws -> [FitnessNotice] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(HTTPRequest(
                method: "POST",
                url: Self.base.appendingPathComponent("index/News/getSchoolNoticeList"),
                headers: Self.headers
            ))
            let json = try Self.decode(resp, api: "fitness-notice")
            let list = json["data"] as? [[String: Any]] ?? []
            return list.map(FitnessNotice.fromJson)
        }
    }

    func fetchScore(year: String) async throws -> FitnessScore? {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let body = "year_num=\(FormEncoding.encode(year))"
            let resp = try await $0.send(HTTPRequest(
                method: "POST",
                url: Self.base.appendingPathComponent("index/Report/getStudentScore"),
                headers: Self.headers,
                body: Data(body.utf8)
            ))
            let json = try Self.decode(resp, api: "fitness-score")
            guard let data = json["data"] as? [String: Any] else { return nil }
            return FitnessScore.fromJson(data)
        }
    }
}
