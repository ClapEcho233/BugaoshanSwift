import Foundation

/// 计划完成度（方案修读）扩展（zhjw_api_service.dart fetchPlanCompletion +
/// zhjw_html_parsers.dart 对应部分）。
///
/// 教务系统行为：单方案用户 index 页直接含 zNodes 数据；多方案用户 index 页
/// 是方案选择页，树数据在 `/getPyfaIndex/<方案ID>` 详情页。详情页连续请求
/// 会触发「请勿频繁刷新」限流，需按 planDetailRequestGap 间隔。
extension ZhjwApiService {

    /// 详情页请求间隔（毫秒）
    static let planDetailRequestGapMs = 600

    struct PlanLink: Equatable, Sendable {
        var id: String
        var name: String
        var path: String
    }

    // MARK: - zNodes 解析

    /// 尝试从 HTML 提取 zNodes：正则未匹配返回 nil（可能是选择页），
    /// 匹配但 JSON/字段解析失败抛 service（可诊断）。
    static func tryParseZNodes(_ html: String) throws -> [PlanCompletionNode]? {
        guard let m = RegexHelper.firstMatch(#"var\s+zNodes\s*=\s*(\[.*?\]);"#, in: html, dotAll: true) else {
            return nil
        }
        return try decodeZNodes(m[1])
    }

    /// 解析 zNodes：未匹配/解析失败均抛 service。
    static func parseZNodes(_ html: String) throws -> [PlanCompletionNode] {
        guard let m = RegexHelper.firstMatch(#"var\s+zNodes\s*=\s*(\[.*?\]);"#, in: html, dotAll: true) else {
            throw SCUError.service("方案修读数据格式异常：未找到 zNodes 数据")
        }
        return try decodeZNodes(m[1])
    }

    private static func decodeZNodes(_ jsonStr: String) throws -> [PlanCompletionNode] {
        guard let data = jsonStr.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SCUError.service("方案修读数据解析失败")
        }
        return list.map(PlanCompletionNode.fromJson)
    }

    /// 单方案场景的方案名（index 页 echarts 雷达图 legend：`data: ['…']`），
    /// 提取不到返回空串由 UI 兜底；超 60 字符截断。
    static func extractPlanName(_ html: String) -> String {
        guard let m = RegexHelper.firstMatch(#"data:\s*\[\s*'([^']+)'\s*\]"#, in: html, dotAll: true) else {
            return ""
        }
        let name = m[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(name.prefix(60))
    }

    /// 方案选择页提取 getPyfaIndex 入口，三级兜底（按钮 → 链接 → 裸 ID），按 id 去重。
    static func extractPlanLinks(_ html: String) -> [PlanLink] {
        var links: [PlanLink] = []
        var seen = Set<String>()

        func addPlan(_ id: String, _ name: String) {
            guard seen.insert(id).inserted else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            links.append(PlanLink(
                id: id,
                name: trimmed.isEmpty ? "方案\(id)" : trimmed,
                path: "/student/integratedQuery/planCompletion/getPyfaIndex/\(id)"
            ))
        }

        // 1) 按钮形态：onclick="getPyfaIndex('ID');"（真机抓包确认引号是 &#39; 实体）
        for (id, matchRange) in buttonMatchRanges(html) {
            // 按钮标签的 title 属性含方案名（如 广播电视编导培养方案(10692)）：
            // tagStart = lastIndexOf('<button', m.start)，tagEnd = indexOf('>', m.start)
            var name = ""
            if let buttonStart = html.range(of: "<button", options: .backwards, range: html.startIndex..<matchRange.lowerBound)?.lowerBound,
               let gtIdx = html[matchRange.lowerBound...].firstIndex(of: ">") {
                let tag = String(html[buttonStart...gtIdx])
                if let tm = RegexHelper.firstMatch(#"title=["']([^"']*)["']"#, in: tag) {
                    name = tm[1]
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"\(\d+\)\s*$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            addPlan(id, name)
        }

        // 2) 链接形态：<a href="...getPyfaIndex/123...">名称</a>
        if links.isEmpty {
            for m in RegexHelper.allMatches(
                #"<a[^>]*href=["'][^"']*getPyfaIndex/(\d+)[^"']*["'][^>]*>(.*?)</a>"#,
                in: html, dotAll: true
            ) {
                let rawName = m[2]
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                addPlan(m[1], rawName)
            }
        }

        // 3) 兜底：非按钮/链接形态（如 JS 字符串）
        if links.isEmpty {
            for m in RegexHelper.allMatches(#"getPyfaIndex/(\d+)"#, in: html) {
                addPlan(m[1], "方案\(m[1])")
            }
        }
        return links
    }

    /// 按钮形态匹配（返回 id + 匹配整体区间，供 title 回溯）
    private static func buttonMatchRanges(_ html: String) -> [(String, Range<String.Index>)] {
        let pattern = #"onclick=["'][^"']*getPyfaIndex\(\s*(?:&#39;|&quot;|['"])?(\d+)(?:&#39;|&quot;|['"])?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let full = Range(match.range, in: html),
                  let idRange = Range(match.range(at: 1), in: html) else { return nil }
            return (String(html[idRange]), full)
        }
    }

    // MARK: - 拉取

    /// 获取方案修读数据（多分支）：
    /// 1. index 页含非空 zNodes → 单方案直出；
    /// 2. 否则提取 getPyfaIndex 链接逐个请求详情页（间隔 600ms 防限流）；
    /// 3. zNodes 明确为空数组 → 账号无方案，返回 []；
    /// 4. 结构异常：登录页 → 重认证；其余抛 service（避免重 SSO 风暴触发限流）。
    func fetchPlanCompletion() async throws -> [PlanCompletionPlan] {
        try await withAuthRetry({ try await self.auth.getClient() }) { client in
            let indexUrl = URL(string: "\(Constants.zhjwBase)/student/integratedQuery/planCompletion/index")!
            let resp = try await client.send(HTTPRequest(method: "GET", url: indexUrl, headers: self.htmlHeaders))
            let body = resp.bodyString
            try Self.checkRateLimit(body)
            try Self.checkSessionExpiry(body: body, statusCode: resp.statusCode)

            let directNodes = try Self.tryParseZNodes(body)
            if let nodes = directNodes, !nodes.isEmpty {
                return [PlanCompletionPlan(id: "", name: Self.extractPlanName(body), nodes: nodes)]
            }

            let planLinks = Self.extractPlanLinks(body)
            if !planLinks.isEmpty {
                var plans: [PlanCompletionPlan] = []
                for link in planLinks {
                    // 连续请求限流防护：第 2 个起加间隔
                    if !plans.isEmpty {
                        try await Task.sleep(nanoseconds: UInt64(Self.planDetailRequestGapMs) * 1_000_000)
                    }
                    let detailUrl = URL(string: "\(Constants.zhjwBase)\(link.path)")!
                    let detailResp = try await client.send(HTTPRequest(method: "GET", url: detailUrl, headers: [
                        "Accept": "text/html,*/*",
                        "Referer": "\(Constants.zhjwBase)/student/integratedQuery/planCompletion/index",
                        "User-Agent": Constants.userAgent,
                    ]))
                    let detailBody = detailResp.bodyString
                    try Self.checkSessionExpiry(body: detailBody, statusCode: detailResp.statusCode)
                    try Self.checkRateLimit(detailBody)
                    let nodes = try Self.parseZNodes(detailBody)
                    plans.append(PlanCompletionPlan(id: link.id, name: link.name, nodes: nodes))
                }
                return plans
            }

            if directNodes != nil {
                return []
            }

            if LoginPageDetector.looksLikeLoginPage(body) {
                throw SCUError.unauthenticated()
            }
            throw SCUError.service("方案修读数据格式异常：页面无法解析")
        }
    }
}
