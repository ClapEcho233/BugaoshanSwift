import Foundation

// MARK: - 方案修读模型（对应 plan_completion.dart）

/// 一份培养方案的修读数据。
/// 多方案用户（主修+辅修等）index 页是选择页，树数据在 getPyfaIndex/<ID> 详情页；
/// 单方案用户 index 页直接返回。id 为空串表示数据直接来自 index 页。
struct PlanCompletionPlan: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var nodes: [PlanCompletionNode]

    /// 单方案（id 为空）与多方案详情共用 uid 命名空间时的稳定标识
    var uid: String { id.isEmpty ? "plan-index" : "plan-\(id)" }
}

struct PlanCompletionNode: Equatable, Sendable {
    var id: String
    var pId: String
    var flagId: String
    var flagType: String   // "001" 大类 / "002" 课程组 / "kch" 课程
    var name: String       // 纯文本（HTML 已剥）
    var rawName: String    // 原始 HTML
    var completed: Bool    // sfwc == "是"
    var earnedCredits: String   // yxxf
    var requiredCredits: String // zsxf
    // 课程节点（flagType == "kch"）专有
    var courseCode: String
    var courseName: String
    var courseCredits: String
    var academicTerm: String
    var gradeInfo: String

    var isCategory: Bool { flagType == "001" }
    var isSubCategory: Bool { flagType == "002" }
    var isCourse: Bool { flagType == "kch" }

    static func fromJson(_ json: [String: Any]) -> PlanCompletionNode {
        let rawName = SafeJSON.string(json["name"])
        let plainName = stripHtml(rawName)
        let flagType = SafeJSON.string(json["flagType"])

        var courseCode = ""
        var courseName = ""
        var courseCredits = ""
        var academicTerm = ""
        var gradeInfo = ""

        if flagType == "kch" {
            // 形如 [304112010]新生研讨课[1学分,2023-2024学年秋](必修,96.0(20240107))
            if let m = RegexHelper.firstMatch(#"\[([^\]]+)\](.*?)\[([^\]]+)\](.*)"#, in: plainName) {
                courseCode = m[1]
                courseName = m[2]
                let creditsTerm = m[3]
                gradeInfo = m[4].trimmingCharacters(in: .whitespacesAndNewlines)
                if let cm = RegexHelper.firstMatch(#"([\d.]+)学分"#, in: creditsTerm) {
                    courseCredits = cm[1]
                }
                if let tm = RegexHelper.firstMatch(#"学分,(.+)"#, in: creditsTerm) {
                    academicTerm = tm[1]
                }
            }
        }

        return PlanCompletionNode(
            id: SafeJSON.string(json["id"]),
            pId: SafeJSON.string(json["pId"]),
            flagId: SafeJSON.string(json["flagId"]),
            flagType: flagType,
            name: plainName,
            rawName: rawName,
            completed: SafeJSON.string(json["sfwc"]) == "是",
            earnedCredits: SafeJSON.string(json["yxxf"]),
            requiredCredits: SafeJSON.string(json["zsxf"]),
            courseCode: courseCode,
            courseName: courseName,
            courseCredits: courseCredits,
            academicTerm: academicTerm,
            gradeInfo: gradeInfo
        )
    }

    /// 剥 HTML 标签 + 常见实体 + 折叠空白
    static func stripHtml(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 摘要统计

/// 摘要卡统计：只统计根级模块（pId == "-1" 的大类 001 与课程组 002），
/// 已获学分取各根级模块自身 yxxf 之和（与教务处方案层级一致）。
struct PlanCompletionSummaryStats: Equatable, Sendable {
    var totalEarned: Double
    var completedCount: Int
    var moduleCount: Int

    static func compute(_ nodes: [PlanCompletionNode]) -> PlanCompletionSummaryStats {
        let roots = nodes.filter { $0.pId == "-1" && ($0.isCategory || $0.isSubCategory) }
        let earned = roots.reduce(0.0) { $0 + (Double($1.earnedCredits) ?? 0) }
        return PlanCompletionSummaryStats(
            totalEarned: earned,
            completedCount: roots.filter(\.completed).count,
            moduleCount: roots.count
        )
    }
}
