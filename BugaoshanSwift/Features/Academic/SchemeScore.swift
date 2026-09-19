import Foundation

/// 成绩单模型（对应 lib/models/scheme_score.dart）
struct SchemeScoreItem: Identifiable, Equatable, Sendable {
    var id: String { "\(academicYearCode)-\(termName)-\(courseName)-\(startSectionKey)" }
    var courseName: String
    var englishCourseName: String?
    var courseAttributeName: String   // 必修/选修/任选
    var credit: String
    var cj: String                    // 原始成绩
    var courseScore: Double
    var gradePointScore: Double
    var gradeName: String             // A/B+/F…
    var academicYearCode: String
    var termName: String              // 秋/春
    var startSectionKey: String = ""

    var passed: Bool { !gradeName.isEmpty && gradeName != "F" }
    var hasEffectiveScore: Bool { courseScore >= 0 && gradePointScore >= 0 }

    static func fromJson(_ json: [String: Any]) -> SchemeScoreItem {
        // 2026-09 起 schemeScores 接口把百分制成绩挪进复合主键：
        // json['id']['courseScore']，顶层 json['courseScore'] 仅为 allPassingScores 回退兼容
        let idMap = json["id"] as? [String: Any]
        let compositeScore = idMap?["courseScore"] as? Double
        let courseNameFromId = idMap?["courseName"] as? String
        return SchemeScoreItem(
            courseName: SafeJSON.string(json["courseName"] ?? courseNameFromId),
            englishCourseName: (json["englishCourseName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            courseAttributeName: SafeJSON.string(json["courseAttributeName"]),
            credit: SafeJSON.string(json["credit"]),
            cj: SafeJSON.string(json["cj"]),
            courseScore: compositeScore ?? SafeJSON.double(json["courseScore"], fallback: -1),
            gradePointScore: SafeJSON.double(json["gradePointScore"], fallback: -1),
            gradeName: SafeJSON.string(json["gradeName"]),
            academicYearCode: SafeJSON.string(json["academicYearCode"]),
            termName: SafeJSON.string(json["termName"])
        )
    }
}

/// 方案成绩汇总（lnList 每个方案）
struct SchemeScoreSummary: Equatable, Sendable {
    var planName: String
    var items: [SchemeScoreItem]

    /// 分母仅计 passed && hasEffectiveScore && credit>0
    var gpa: Double {
        var creditSum = 0.0
        var pointSum = 0.0
        for item in effectiveItems {
            let credit = Double(item.credit) ?? 0
            creditSum += credit
            pointSum += credit * item.gradePointScore
        }
        return creditSum > 0 ? pointSum / creditSum : 0
    }

    var weightedAvgScore: Double {
        var creditSum = 0.0
        var scoreSum = 0.0
        for item in effectiveItems {
            let credit = Double(item.credit) ?? 0
            creditSum += credit
            scoreSum += credit * item.courseScore
        }
        return creditSum > 0 ? scoreSum / creditSum : 0
    }

    var requiredGpa: Double {
        var creditSum = 0.0
        var pointSum = 0.0
        for item in effectiveItems where item.courseAttributeName.contains("必修") {
            let credit = Double(item.credit) ?? 0
            creditSum += credit
            pointSum += credit * item.gradePointScore
        }
        return creditSum > 0 ? pointSum / creditSum : 0
    }

    var earnedCredits: Double {
        effectiveItems.reduce(0) { $0 + (Double($1.credit) ?? 0) }
    }

    var requiredCredits: Double {
        effectiveItems.filter { $0.courseAttributeName.contains("必修") }.reduce(0) { $0 + (Double($1.credit) ?? 0) }
    }

    var electiveCredits: Double {
        effectiveItems.filter { $0.courseAttributeName.contains("选修") }.reduce(0) { $0 + (Double($1.credit) ?? 0) }
    }

    var optionalCredits: Double {
        effectiveItems.filter { $0.courseAttributeName.contains("任选") }.reduce(0) { $0 + (Double($1.credit) ?? 0) }
    }

    var passedCount: Int { items.filter(\.passed).count }
    var failedCount: Int { items.count - passedCount }

    private var effectiveItems: [SchemeScoreItem] {
        items.filter { $0.passed && $0.hasEffectiveScore && (Double($0.credit) ?? 0) > 0 }
    }

    /// schemeScores 响应解析：{lnList: [{cjlx, cjList: [...]}]}
    /// defaultScheme 取第一个非辅助方案（微专业/辅修/第二专业），否则首个
    static func parseSummaries(_ json: [String: Any]) -> [SchemeScoreSummary] {
        let lnList = json["lnList"] as? [[String: Any]] ?? []
        let summaries: [SchemeScoreSummary] = lnList.map { ln in
            let planName = SafeJSON.string(ln["cjlx"])
            let cjList = ln["cjList"] as? [[String: Any]] ?? []
            return SchemeScoreSummary(planName: planName, items: cjList.map(SchemeScoreItem.fromJson))
        }
        return summaries
    }

    static func defaultScheme(_ summaries: [SchemeScoreSummary]) -> SchemeScoreSummary? {
        let keywords = ["微专业", "辅修", "第二专业"]
        return summaries.first { summary in
            !keywords.contains { summary.planName.contains($0) }
        } ?? summaries.first
    }
}

/// 及格成绩按学期分组；学年倒序、同学年春在前秋在后
struct PassingScoreGroup: Identifiable, Equatable, Sendable {
    var label: String
    var items: [SchemeScoreItem]

    var id: String { label }

    /// allPassingScores callback 响应：顶层 lnList，每组 {cjlx: 学期标签, cjList: [...]}
    static func parse(_ json: [String: Any]) -> [PassingScoreGroup] {
        let entries = SafeJSON.objectList(json["lnList"] as? [Any] ?? [])
        let groups = entries.map { entry -> PassingScoreGroup in
            PassingScoreGroup(
                label: SafeJSON.string(entry["cjlx"]),
                items: ((entry["cjList"] as? [[String: Any]]) ?? [])
                    .map(SchemeScoreItem.fromJson)
                    .filter { !$0.courseName.isEmpty })
        }
        .filter { !$0.items.isEmpty && !$0.label.isEmpty }
        return sortedByTerm(groups)
    }

    /// 学年倒序；同学年春在前秋在后（label 前缀为学年）
    static func sortedByTerm(_ groups: [PassingScoreGroup]) -> [PassingScoreGroup] {
        groups.sorted { lhs, rhs in
            let lhsYear = String(lhs.label.prefix(9))
            let rhsYear = String(rhs.label.prefix(9))
            if lhsYear != rhsYear {
                return lhsYear > rhsYear
            }
            let lhsSpring = lhs.label.contains("春")
            let rhsSpring = rhs.label.contains("春")
            return lhsSpring && !rhsSpring
        }
    }

    static func group(_ items: [SchemeScoreItem]) -> [PassingScoreGroup] {
        var dict: [String: [SchemeScoreItem]] = [:]
        var order: [String] = []
        for item in items {
            let label = "\(item.academicYearCode)学年\(item.termName)"
            if dict[label] == nil { order.append(label) }
            dict[label, default: []].append(item)
        }
        let groups = order.map { PassingScoreGroup(label: $0, items: dict[$0]!) }
        return sortedByTerm(groups)
    }
}
