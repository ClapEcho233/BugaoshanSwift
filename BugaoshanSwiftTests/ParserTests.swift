import Foundation
import XCTest
@testable import BugaoshanSwift

/// 解析器与 ICS 测试（jwxt JSON / 压缩校历 / ICS 生成 / 响应解码）
final class ParserTests: XCTestCase {

    // MARK: - JwxtParser

    private static let jwxtFixture = """
    {"xkxx": [
      {"k1": {
        "courseName": "高等数学",
        "id": {"coureSequenceNumber": "01"},
        "attendClassTeacher": "张三",
        "timeAndPlaceList": [
          {
            "classDay": 1, "classSessions": 1, "continuingSession": 2,
            "teachingBuildingName": "一教", "classroomName": "A101",
            "campusName": "江安校区",
            "classWeek": "1010101010101010"
          },
          {
            "classDay": 3, "classSessions": 3, "continuingSession": 2,
            "jxlm": "综合楼", "jasm": "C407",
            "campusName": "江安校区",
            "classWeek": "1111111011111110"
          }
        ]
      }},
      {"k2": {
        "courseName": "大学英语",
        "id": {"coureSequenceNumber": "02"},
        "attendClassTeacher": "李四",
        "timeAndPlaceList": [
          {
            "classDay": 6, "classSessions": 5, "continuingSession": 2,
            "customPlace": "望江 东教 302",
            "campusName": "",
            "classWeek": "11111111111111111111"
          }
        ]
      }}
    ]}
    """

    /// xkxx 单个元素含多门课（真实数据形态）：全部解析，不能只取第一个 value
    func testJwxtParseMultiCourseEntry() throws {
        let json = """
        {"xkxx": [{"K1": {"courseName": "课程甲", "id": {"coureSequenceNumber": "01"},
          "attendClassTeacher": "教师A",
          "timeAndPlaceList": [{"classDay": 1, "classSessions": 1, "continuingSession": 2,
            "classWeek": "1-16周", "campusName": "江安校区", "teachingBuildingName": "一教", "classroomName": "A101"}]}},
        {"K2": {"courseName": "课程乙", "id": {"coureSequenceNumber": "02"},
          "attendClassTeacher": "教师B",
          "timeAndPlaceList": [{"classDay": 3, "classSessions": 3, "continuingSession": 2,
            "classWeek": "1-16周", "campusName": "江安校区", "teachingBuildingName": "二教", "classroomName": "B202"}]},
         "K3": {"courseName": "课程丙", "id": {"coureSequenceNumber": "03"},
          "attendClassTeacher": "教师C",
          "timeAndPlaceList": [{"classDay": 5, "classSessions": 6, "continuingSession": 2,
            "classWeek": "2-15周", "campusName": "江安校区", "teachingBuildingName": "综楼", "classroomName": "C303"}]}}]}
        """
        let result = try JwxtParser.parse(jsonString: json)
        // K2 与 K3 同属第二个 xkxx 元素 —— 三门都必须出现
        let names = result.courses.map(\.name).sorted()
        XCTAssertEqual(names, ["课程丙 (03)", "课程乙 (02)", "课程甲 (01)"])
    }

    func testJwxtParse() throws {
        let result = try JwxtParser.parse(jsonString: Self.jwxtFixture)
        // 高数：交替段 1 条 + 连续段 2 条；英语 1 条
        XCTAssertEqual(result.courses.count, 4)
        XCTAssertTrue(result.hasWeekend, "周六课程应触发 hasWeekend")

        let math = result.courses[0]
        XCTAssertEqual(math.name, "高等数学 (01)")
        XCTAssertEqual(math.teacher, "张三")
        XCTAssertEqual(math.location, "一教A101")
        XCTAssertEqual(math.campus, "江安校区")
        XCTAssertEqual(math.startSection, 1)
        XCTAssertEqual(math.endSection, 2)
        XCTAssertEqual(math.weekType, .odd)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 15)

        // jxlm/jasm 候选链
        let mathSecond = result.courses[1]
        XCTAssertEqual(mathSecond.location, "综合楼C407")
        XCTAssertEqual(mathSecond.dayOfWeek, 3)

        // customPlace 兜底链 + 周六
        let english = result.courses[3]
        XCTAssertEqual(english.name, "大学英语 (02)")
        XCTAssertEqual(english.location, "望江 东教 302")
        XCTAssertEqual(english.dayOfWeek, 6)

        // 颜色轮转：按课程（courseMap）计数
        XCTAssertEqual(result.courses[0].colorValue, JwxtParser.materialPrimaries[0])
        XCTAssertEqual(result.courses[3].colorValue, JwxtParser.materialPrimaries[1])
    }

    func testJwxtValidate() throws {
        let result = try JwxtParser.parse(jsonString: Self.jwxtFixture)
        XCTAssertNoThrow(try JwxtParser.validate(config: result.suggestedConfig, courses: result.courses))
        // endSection 超出 timeSlots 数 → 报错
        var bad = result.courses[0]
        bad.endSection = 99
        XCTAssertThrowsError(try JwxtParser.validate(config: result.suggestedConfig, courses: [bad]))
    }

    func testJwxtInvalidJson() {
        XCTAssertThrowsError(try JwxtParser.parse(jsonString: "{\"nope\":1}"))
        XCTAssertThrowsError(try JwxtParser.parse(jsonString: "not json"))
    }

    func testCleanSemesterLabel() {
        XCTAssertEqual(JwxtParser.cleanSemesterLabel("2025-2026-2（当前）"), "2025-2026-2")
        XCTAssertEqual(JwxtParser.cleanSemesterLabel("2025-2026-2(当前)"), "2025-2026-2")
    }

    // MARK: - ICS

    func testCourseIcs() throws {
        var config = ScheduleConfig()
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-14")!
        let course = Course(
            id: "c1", name: "高等数,学;", teacher: "张\\三", location: "一教A101",
            campus: "", startWeek: 1, endWeek: 2, dayOfWeek: 1,
            startSection: 1, endSection: 2, colorValue: 0, weekType: .every
        )
        let ics = IcsBuilder.courseScheduleIcs(config: config, courses: [course])
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR"))
        // 两个周两条 VEVENT，UID 带 week
        XCTAssertTrue(ics.contains("UID:c1_1@bugaoshan"))
        XCTAssertTrue(ics.contains("UID:c1_2@bugaoshan"))
        // 转义
        XCTAssertTrue(ics.contains(#"SUMMARY:高等数\,学\;"#))
        XCTAssertTrue(ics.contains(#"DESCRIPTION:教师: 张\\三"#))
        // 第 1 周周一 = 2026-09-14；默认时间表（通用推导）：第 1 节 08:00-08:45，第 2 节 08:55-09:40
        XCTAssertTrue(ics.contains("DTSTART;TZID=Asia/Shanghai:20260914T080000"))
        XCTAssertTrue(ics.contains("DTEND;TZID=Asia/Shanghai:20260914T094000"))
        // VTIMEZONE 固定 +0800
        XCTAssertTrue(ics.contains("TZOFFSETFROM:+0800"))
    }

    func testCourseIcsOddWeeks() throws {
        var config = ScheduleConfig()
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-14")!
        let odd = Course(
            id: "c2", name: "体育", teacher: "", location: "",
            campus: "", startWeek: 1, endWeek: 4, dayOfWeek: 5,
            startSection: 3, endSection: 4, colorValue: 0, weekType: .odd
        )
        let ics = IcsBuilder.courseScheduleIcs(config: config, courses: [odd])
        XCTAssertTrue(ics.contains("UID:c2_1@bugaoshan"))
        XCTAssertFalse(ics.contains("UID:c2_2@bugaoshan"))
        XCTAssertTrue(ics.contains("UID:c2_3@bugaoshan"))
        XCTAssertFalse(ics.contains("UID:c2_4@bugaoshan"))
    }

    func testSafeFileName() {
        XCTAssertEqual(IcsBuilder.safeFileName("2026-2027学年 秋季学期"), "2026_2027学年_秋季学期")
        XCTAssertEqual(IcsBuilder.safeFileName("///"), "___")
        XCTAssertEqual(IcsBuilder.safeFileName(""), "calendar")
    }

    // MARK: - 校历压缩格式展开

    func testExpandCompactCalendarJson() throws {
        let compact = """
        {"eventTypes": {
          "national": {"l": "国庆节假期", "t": "holiday"},
          "register": {"l": "报到注册", "t": "register"}
        },
        "semesters": [
          {"n": "2026-2027-1", "s": "2026-09-14", "w": 18,
           "e": {"national": ["2026-10-01", "2026-10-07"], "register": "2026-09-13"}}
        ]}
        """
        let data = try XCTUnwrap(AcademicCalendarService.expandCalendarJson(compact))
        XCTAssertEqual(data.semesters.count, 1)
        let semester = data.semesters[0]
        XCTAssertEqual(semester.name, "2026-2027-1")
        XCTAssertEqual(semester.totalWeeks, 18)
        XCTAssertEqual(semester.events.count, 2)
        let national = semester.events.first { $0.label == "国庆节假期" }
        XCTAssertNotNil(national)
        XCTAssertEqual(ScheduleConfig.formatDate(national!.date), "2026-10-01")
        XCTAssertEqual(ScheduleConfig.formatDate(national!.endDate!), "2026-10-07")
        XCTAssertEqual(national!.tag, "holiday")
    }

    func testBundledCalendarLoads() throws {
        // 主 bundle 的 academic_calendar.json（App target 资源）
        let bundled = AcademicCalendarService.loadBundled()
        // 测试宿主可能拿不到主 bundle 资源，允许 nil，但 App 内可用
        if let bundled {
            XCTAssertGreaterThanOrEqual(bundled.semesters.count, 10, "内置校历应覆盖 12 学期")
        }
    }

    // MARK: - zhjw 响应检测

    func testZhjwSessionExpiry() {
        XCTAssertThrowsError(try ZhjwApiService.checkSessionExpiry(body: "", statusCode: 200))
        XCTAssertThrowsError(try ZhjwApiService.checkSessionExpiry(body: "x", statusCode: 302))
        XCTAssertThrowsError(try ZhjwApiService.checkSessionExpiry(
            body: "<html><title>登录</title></html>", statusCode: 200))
        XCTAssertNoThrow(try ZhjwApiService.checkSessionExpiry(
            body: "<html>课表</html>", statusCode: 200))
    }

    func testZhjwRateLimit() {
        XCTAssertThrowsError(try ZhjwApiService.checkRateLimit("请勿频繁刷新，稍后再试")) { error in
            XCTAssertEqual(error as? SCUError, SCUError.rateLimited)
        }
        XCTAssertNoThrow(try ZhjwApiService.checkRateLimit("正常内容"))
    }

    func testParseSelectOptions() {
        let html = """
        <select name="xsh" id="xsh">
          <option value="">全部</option>
          <option value="01" selected>数学<b>学院</b></option>
          <option value="02">物理学院</option>
        </select>
        """
        let options = ZhjwApiService.parseSelectOptions(html: html, selectId: "xsh")
        XCTAssertEqual(options.count, 2, "空 value 跳过")
        XCTAssertEqual(options[0].value, "01")
        XCTAssertEqual(options[0].label, "数学学院", "内层标签剥离")
        XCTAssertEqual(options[1].value, "02")
    }

    func testSemesterRegex() {
        let html = """
        <select><option value="2025-2026-1-1">2025-2026学年秋季学期（当前）</option>
        <option value="2025-2026-2-1">春季学期</option></select>
        """
        // 与 fetchSemesters 相同的正则
        let regex = try! NSRegularExpression(pattern: #"<option[^>]+value="([^"]+)"[^>]*>(.*?)</option>"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        XCTAssertEqual(matches.count, 2)
    }

    // MARK: - wfw 响应解码

    private func makeResponse(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: [:],
            body: Data(body.utf8),
            finalURL: URL(string: "https://wfw.scu.edu.cn/api")!
        )
    }

    func testWfwDecode() throws {
        let ok = try WfwApiService.decodeResponse(
            makeResponse(#"{"e":0,"m":"","d":{"list":[]}}"#), api: "test")
        XCTAssertEqual(SafeJSON.int(ok["e"]), 0)
        // 10013 → 未认证
        XCTAssertThrowsError(
            try WfwApiService.decodeResponse(
                makeResponse(#"{"e":10013,"m":"未登录"}"#), api: "test")) { error in
            XCTAssertTrue((error as? SCUError)?.isUnauthenticated ?? false)
        }
        // 空体 → 未认证
        XCTAssertThrowsError(try WfwApiService.decodeResponse(makeResponse(""), api: "test"))
    }
}

// MARK: - 成绩解析

final class ScoreParsingTests: XCTestCase {

    func testSchemeScoreItemCompositeKey() {
        // 2026-09 起 schemeScores 把百分制成绩挪进复合主键 json.id.courseScore
        let item = SchemeScoreItem.fromJson([
            "courseName": "高等数学",
            "id": ["courseScore": 92.0, "courseName": "高等数学B"],
            "courseAttributeName": "必修",
            "credit": "5.0",
            "gradePointScore": 4.0,
            "gradeName": "A",
            "academicYearCode": "2025-2026",
            "termName": "秋",
        ])
        XCTAssertEqual(item.courseScore, 92.0)
        XCTAssertEqual(item.courseName, "高等数学")
        XCTAssertTrue(item.passed)
        XCTAssertTrue(item.hasEffectiveScore)
    }

    func testSchemeScoreItemTopLevelFallback() {
        // allPassingScores：顶层 courseScore
        let item = SchemeScoreItem.fromJson([
            "courseName": "大学英语",
            "courseScore": 85.0,
            "credit": "2.0",
            "gradePointScore": 3.3,
            "gradeName": "B+",
            "academicYearCode": "2025-2026",
            "termName": "春",
        ])
        XCTAssertEqual(item.courseScore, 85.0)
    }

    func testSummaryStats() {
        let items = [
            scoreItem("高数", credit: "5", score: 92, point: 4.0, attr: "必修", passed: true),
            scoreItem("英语", credit: "2", score: 85, point: 3.3, attr: "选修", passed: true),
            scoreItem("体育", credit: "1", score: -1, point: -1, attr: "必修", passed: false),
        ]
        let summary = SchemeScoreSummary(planName: "主修方案", items: items)
        // gpa = (5*4.0 + 2*3.3) / 7
        XCTAssertEqual(summary.gpa, (20 + 6.6) / 7, accuracy: 0.001)
        XCTAssertEqual(summary.weightedAvgScore, (5 * 92 + 2 * 85) / 7, accuracy: 0.001)
        XCTAssertEqual(summary.earnedCredits, 7.0, accuracy: 0.001)
        XCTAssertEqual(summary.requiredCredits, 5.0, accuracy: 0.001)
        XCTAssertEqual(summary.electiveCredits, 2.0, accuracy: 0.001)
        XCTAssertEqual(summary.passedCount, 2)
        XCTAssertEqual(summary.failedCount, 1)
    }

    func testDefaultSchemeSkipsAuxiliary() {
        let main = SchemeScoreSummary(planName: "主修方案", items: [])
        let minor = SchemeScoreSummary(planName: "计算机微专业", items: [])
        let second = SchemeScoreSummary(planName: "第二专业(法学)", items: [])
        XCTAssertEqual(SchemeScoreSummary.defaultScheme([minor, main, second])?.planName, "主修方案")
        XCTAssertEqual(SchemeScoreSummary.defaultScheme([minor, second])?.planName, "计算机微专业")
    }

    /// allPassingScores 真实响应结构：顶层 lnList，每组 {cjlx, cjList}
    func testPassingScoreParseFromLnList() {
        let json: [String: Any] = [
            "lnList": [
                ["cjlx": "2025-2026学年秋(两学期)", "cjList": [
                    ["cj": "73.0", "courseName": "通用英语Ⅱ-2", "credit": "2.0",
                     "academicYearCode": "2025-2026", "termName": "秋", "gradeName": "B-"],
                ]],
                ["cjlx": "2026-2027学年秋(两学期)", "cjList": [
                    ["cj": "88.0", "courseName": "人工智能导论", "credit": "3.0",
                     "academicYearCode": "2026-2027", "termName": "秋", "gradeName": "B+"],
                ]],
                ["cjlx": "2025-2026学年春(两学期)", "cjList": []],
            ]
        ]
        let groups = PassingScoreGroup.parse(json)
        XCTAssertEqual(groups.count, 2)
        // 学年倒序，最新在前；空组过滤
        XCTAssertEqual(groups.first?.label, "2026-2027学年秋(两学期)")
        XCTAssertEqual(groups.first?.items.first?.courseName, "人工智能导论")
        XCTAssertEqual(groups.last?.label, "2025-2026学年秋(两学期)")
    }

    func testPassingScoreGroupOrdering() {
        let items = [
            scoreItem("A", credit: "1", score: 90, point: 4, attr: "必修", passed: true, year: "2024-2025", term: "秋"),
            scoreItem("B", credit: "1", score: 90, point: 4, attr: "必修", passed: true, year: "2024-2025", term: "春"),
            scoreItem("C", credit: "1", score: 90, point: 4, attr: "必修", passed: true, year: "2025-2026", term: "秋"),
        ]
        let groups = PassingScoreGroup.group(items)
        XCTAssertEqual(groups.count, 3)
        // 学年倒序；同学年春在前
        XCTAssertEqual(groups[0].label, "2025-2026学年秋")
        XCTAssertEqual(groups[1].label, "2024-2025学年春")
        XCTAssertEqual(groups[2].label, "2024-2025学年秋")
    }

    private func scoreItem(_ name: String, credit: String, score: Double, point: Double,
                           attr: String, passed: Bool,
                           year: String = "2025-2026", term: String = "秋") -> SchemeScoreItem {
        SchemeScoreItem(
            courseName: name, englishCourseName: nil, courseAttributeName: attr,
            credit: credit, cj: passed ? "88" : "F",
            courseScore: score, gradePointScore: point,
            gradeName: passed ? "B+" : "F",
            academicYearCode: year, termName: term
        )
    }
}
