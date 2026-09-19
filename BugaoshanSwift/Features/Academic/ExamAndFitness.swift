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

    struct FitnessScoreItem: Equatable, Sendable {
        var rawScore: String
        var gradedScore: String
        var grade: String
        var isFail: Bool

        init(rawScore: String = "-", gradedScore: String = "-", grade: String = "-", isFail: Bool = false) {
            self.rawScore = rawScore
            self.gradedScore = gradedScore
            self.grade = grade
            self.isFail = isFail
        }
    }

    /// 体测总成绩（字段与 Dart 版 FitnessScore.fromJson 一一对应）
    struct FitnessScore: Equatable, Sendable {
        var totalScore: String       // 已格式化（"54.4" / "60"）
        var totalGrade: String
        var studentName: String
        var studentNum: String
        var sex: String
        var studentYear: String
        var reportType: String
        var reportStatus: String
        var bmi: FitnessScoreItem
        var vitalCapacity: FitnessScoreItem
        var jump: FitnessScoreItem
        var sitAndReach: FitnessScoreItem
        var pullAndSit: FitnessScoreItem
        var fiftyM: FitnessScoreItem
        var run: FitnessScoreItem

        static func fromJson(_ data: [String: Any]) -> FitnessScore {
            func field(_ key: String) -> String {
                SafeJSON.string(data[key], fallback: "-")
            }
            func item(_ key: String) -> FitnessScoreItem {
                FitnessScoreItem(
                    rawScore: field("\(key)_score"),
                    gradedScore: field("\(key)_score2"),
                    grade: field("\(key)_grade"),
                    isFail: field("\(key)_class") == "red"
                )
            }
            let scoreValue = SafeJSON.double(data["total_score"], fallback: .nan)
            return FitnessScore(
                totalScore: scoreValue.isNaN ? "-" : formatScore(scoreValue),
                totalGrade: field("total_grade"),
                studentName: field("student_name"),
                studentNum: field("student_num"),
                sex: field("sex"),
                studentYear: field("studentYear"),
                reportType: field("report_type"),
                reportStatus: field("report_status"),
                bmi: item("bmi"),
                vitalCapacity: item("vc"),
                jump: item("jump"),
                sitAndReach: item("sit_and_reach"),
                pullAndSit: item("pull_and_sit"),
                fiftyM: item("50m"),
                run: item("run")
            )
        }

        /// 54.399999… → "54.4"；整数 → "60"
        static func formatScore(_ value: Double) -> String {
            let rounded = (value * 10).rounded() / 10
            if rounded == rounded.rounded() { return String(Int(rounded)) }
            return String(format: "%.1f", rounded)
        }
    }

    struct FitnessNotice: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var content: String
        var plainContent: String
        var time: String
        var readNum: Int
        var isSticky: Bool

        static func fromJson(_ json: [String: Any]) -> FitnessNotice {
            let content = SafeJSON.string(json["content"])
            return FitnessNotice(
                id: SafeJSON.string(json["id"]),
                title: SafeJSON.string(json["title"]),
                content: content,
                plainContent: stripHtml(content),
                time: SafeJSON.string(json["create_time"] ?? json["createtime"]),
                readNum: SafeJSON.int(json["read_num"]),
                isSticky: SafeJSON.string(json["is_stick"]) == "1"
            )
        }

        /// 通知 HTML → 纯文本（对应 Dart stripFitnessHtml）
        static func stripHtml(_ html: String) -> String {
            var text = html
            func replace(_ pattern: String, _ template: String) {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                text = regex.stringByReplacingMatches(
                    in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template
                )
            }
            replace(#"<br\s*/?>"#, "\n")
            replace(#"<p>|<p\s[^>]*>"#, "")
            replace(#"</p>"#, "\n")
            replace(#"<[^>]+>"#, "")
            text = text
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
            replace(#"\n{3,}"#, "\n\n")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
