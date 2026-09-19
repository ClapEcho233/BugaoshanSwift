import Foundation
import SwiftSoup

/// 教务 API（对应 lib/services/api/zhjw_api_service.dart 核心 + zhjw_html_parsers.dart）。
/// zhjw 为 HTTP 站点（ATS 已豁免）；HTML 正则解析 + AJAX callback JSON 混合。
struct ZhjwApiService {

    let auth: SsoRelayAuth
    let log: AuthLogger

    init(auth: SsoRelayAuth, log: AuthLogger = .shared) {
        self.auth = auth
        self.log = log
    }

    private var base: URL { URL(string: Constants.zhjwBase)! }

    private var htmlHeaders: [String: String] {
        [
            "Accept": "text/html,*/*",
            "Referer": "\(Constants.zhjwBase)/",
            "User-Agent": Constants.userAgent,
        ]
    }

    // MARK: - 过期与限流检测

    static func checkSessionExpiry(body: String, statusCode: Int) throws {
        if statusCode == 302 {
            throw SCUError.unauthenticated()
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SCUError.unauthenticated()
        }
        if LoginPageDetector.looksLikeLoginPage(body) {
            throw SCUError.unauthenticated()
        }
    }

    static func checkRateLimit(_ body: String) throws {
        if body.contains("请勿频繁刷新") {
            throw SCUError.rateLimited
        }
    }

    // MARK: - 当前教学周

    /// GET / → 第N周；假期返回 nil
    func fetchCurrentWeek() async throws -> Int? {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let resp = try await $0.send(
                HTTPRequest(method: "GET", url: self.base, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            if body.contains("当前处于假期时间") {
                return nil
            }
            guard let match = body.range(of: #"第(\d+)周"#, options: .regularExpression) else {
                throw SCUError.service("无法获取当前周数", statusCode: resp.statusCode)
            }
            let weekString = body[match].replacingOccurrences(of: "第", with: "")
                .replacingOccurrences(of: "周", with: "")
            guard let week = Int(weekString), week >= 1 else {
                throw SCUError.service("无法获取当前周数（解析失败）")
            }
            return week
        }
    }

    // MARK: - 学期列表

    /// GET calendarSemesterCurriculum/index → [(value, label)]
    func fetchSemesters() async throws -> [(value: String, label: String)] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/courseSelect/calendarSemesterCurriculum/index")
            let resp = try await $0.send(HTTPRequest(method: "GET", url: url, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)

            // <option value="...">label</option>（dotAll；label 剥内层标签）
            let regex = try NSRegularExpression(pattern: #"<option[^>]+value="([^"]+)"[^>]*>(.*?)</option>"#, options: [.dotMatchesLineSeparators])
            let range = NSRange(body.startIndex..., in: body)
            var result: [(String, String)] = []
            for match in regex.matches(in: body, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: body),
                      let labelRange = Range(match.range(at: 2), in: body) else { continue }
                let value = String(body[valueRange])
                let label = stripTags(String(body[labelRange]))
                if !value.isEmpty {
                    result.append((value, label))
                }
            }
            guard !result.isEmpty else {
                throw SCUError.service("学期列表解析失败", statusCode: resp.statusCode)
            }
            return result
        }
    }

    private func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 课表拉取（jwxt JSON，喂给 JwxtParser）

    /// POST thisSemesterCurriculum/ajaxStudentSchedule/callback form planCode=<>
    func fetchJwxtSchedule(planCode: String) async throws -> String {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let url = self.base.appendingPathComponent("student/courseSelect/thisSemesterCurriculum/ajaxStudentSchedule/callback")
            let form = "planCode=\(FormEncoding.encode(planCode))"
            let resp = try await $0.send(HTTPRequest(
                method: "POST", url: url,
                headers: [
                    "Accept": "application/json, text/javascript, */*; q=0.01",
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer": "\(Constants.zhjwBase)/student/courseSelect/calendarSemesterCurriculum/index",
                    "User-Agent": Constants.userAgent,
                    "X-Requested-With": "XMLHttpRequest",
                ],
                body: Data(form.utf8)
            ))
            let body = resp.bodyString
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)
            guard body.contains("xkxx") else {
                throw SCUError.service("教务课表数据异常（缺少 xkxx）", statusCode: resp.statusCode)
            }
            return body
        }
    }

    // MARK: - 成绩（两步：index HTML 提取 callback URL → GET JSON）

    func fetchScores(kind: ScoreKind) async throws -> [String: Any] {
        try await withAuthRetry({ try await self.auth.getClient() }) {
            let index = kind == .passing
                ? "student/integratedQuery/scoreQuery/allPassingScores/index"
                : "student/integratedQuery/scoreQuery/schemeScores/index"
            let callbackPattern = kind == .passing
                ? #"var\s+url\s*=\s*"(/student/integratedQuery/scoreQuery/[^/]+/allPassingScores/callback)""#
                : #"var\s+url\s*=\s*"(/student/integratedQuery/scoreQuery/[^/]+/schemeScores/callback)""#
            let indexUrl = self.base.appendingPathComponent(index)
            let indexResp = try await $0.send(HTTPRequest(method: "GET", url: indexUrl, headers: self.htmlHeaders))
            let indexBody = indexResp.bodyString
            try Self.checkRateLimit(indexBody)
            try Self.checkSessionExpiry(body: indexBody, statusCode: indexResp.statusCode)

            guard let match = indexBody.range(of: callbackPattern, options: .regularExpression) else {
                throw SCUError.service("无法从页面提取 \(kind.rawValue) callback URL")
            }
            let callbackPath = indexBody[match]
                .replacingOccurrences(of: #"var\s+url\s*=\s*""#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\"", with: "")
            let callbackUrl = URL(string: "\(Constants.zhjwBase)\(callbackPath)")!
            let resp = try await $0.send(HTTPRequest(method: "GET", url: callbackUrl, headers: self.htmlHeaders))
            try Self.checkSessionExpiry(body: resp.bodyString, statusCode: resp.statusCode)
            return try SafeJSON.parseObject(resp.bodyString, api: "scores")
        }
    }

    enum ScoreKind: String {
        case passing = "allPassingScores"
        case scheme = "schemeScores"
    }

    // MARK: - 通用选项解析（select 下拉，供培养方案/班级课表/课程课表用）

    static func parseSelectOptions(html: String, selectId: String) -> [(value: String, label: String)] {
        // <select name="id">…</select> 块内 <option value="v">label</option>
        guard let selectMatch = html.range(
            of: #"<select[^>]*name="\#(selectId)"[^>]*>([\s\S]*?)</select>"#,
            options: .regularExpression
        ) else { return [] }
        let block = String(html[selectMatch])
        let optionRegex = try! NSRegularExpression(
            pattern: #"<option[^>]*value="([^"]*)"[^>]*>([\s\S]*?)</option>"#)
        let range = NSRange(block.startIndex..., in: block)
        var result: [(String, String)] = []
        for match in optionRegex.matches(in: block, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: block),
                  let labelRange = Range(match.range(at: 2), in: block) else { continue }
            let value = String(block[valueRange])
            let label = String(block[labelRange])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result.append((value, label))
            }
        }
        return result
    }
}
