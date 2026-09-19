import XCTest
@testable import BugaoshanSwift

/// 体测解析（真实账号 2025-09-20 抓包样本；无数据年份 data 为空数组）
final class FitnessTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - FitnessScore.fromJson（2025 真实响应）

    private static let realScoreBody = #"{"status":1,"info":"查询成功","data":{"student_num":"2025141530009","student_name":"熊宇顺","total_score":54.399999999999999,"total_grade":"不及格","report_type":"正常","report_desc":"暂无","report_status":"正常","bmi_score":"181.5\/66.1","bmi_score2":100,"bmi_grade":"正常","bmi_class":"green","vc_score":4738,"vc_score2":85,"vc_grade":"良好","vc_class":"green","jump_score":"196.0","jump_score2":30,"jump_grade":"不及格","jump_class":"red","sit_and_reach_score":"-7.7","sit_and_reach_score2":0,"sit_and_reach_grade":"不及格","sit_and_reach_class":"red","pull_and_sit_score":2,"pull_and_sit_score2":0,"pull_and_sit_grade":"不及格","pull_and_sit_class":"red","50m_score":"7.3","50m_score2":78,"50m_grade":"及格","50m_class":"green","run_score":"4'57''","run_score2":40,"run_grade":"不及格","run_class":"red","lack_show_score_msg":0,"free_show_score_msg":0,"studentYear":"大一成绩","sex":"男","grade":2025}}"#

    func testScoreFromRealCapture() throws {
        let json = try SafeJSON.parseObject(Self.realScoreBody, api: "fitness-score")
        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let score = FitnessApiService.FitnessScore.fromJson(data)

        // 浮点总分四舍五入到 1 位；"不及格"不得被"及格"前缀误判吞掉
        XCTAssertEqual(score.totalScore, "54.4")
        XCTAssertEqual(score.totalGrade, "不及格")
        XCTAssertEqual(score.studentName, "熊宇顺")
        XCTAssertEqual(score.studentNum, "2025141530009")
        XCTAssertEqual(score.sex, "男")
        XCTAssertEqual(score.studentYear, "大一成绩")
        XCTAssertEqual(score.reportType, "正常")
        XCTAssertEqual(score.reportStatus, "正常")

        XCTAssertEqual(score.bmi.rawScore, "181.5/66.1")
        XCTAssertEqual(score.bmi.gradedScore, "100")
        XCTAssertEqual(score.bmi.grade, "正常")
        XCTAssertFalse(score.bmi.isFail)

        // 数值型字段（vc_score=4738 是数字而非字符串）
        XCTAssertEqual(score.vitalCapacity.rawScore, "4738")
        XCTAssertEqual(score.vitalCapacity.gradedScore, "85")
        XCTAssertEqual(score.vitalCapacity.grade, "良好")

        XCTAssertTrue(score.jump.isFail)
        XCTAssertEqual(score.jump.rawScore, "196.0")
        XCTAssertTrue(score.sitAndReach.isFail)
        XCTAssertEqual(score.sitAndReach.rawScore, "-7.7")
        XCTAssertTrue(score.pullAndSit.isFail)
        XCTAssertEqual(score.pullAndSit.rawScore, "2")
        XCTAssertFalse(score.fiftyM.isFail)
        XCTAssertEqual(score.fiftyM.rawScore, "7.3")
        XCTAssertTrue(score.run.isFail)
        XCTAssertEqual(score.run.rawScore, "4'57''")
    }

    func testScoreMissingFieldsFallback() {
        let score = FitnessApiService.FitnessScore.fromJson([:])
        XCTAssertEqual(score.totalScore, "-")
        XCTAssertEqual(score.studentName, "-")
        XCTAssertEqual(score.bmi.rawScore, "-")
        XCTAssertFalse(score.bmi.isFail)  // class 缺失默认 green
    }

    func testFormatScore() {
        XCTAssertEqual(FitnessApiService.FitnessScore.formatScore(54.399999999999999), "54.4")
        XCTAssertEqual(FitnessApiService.FitnessScore.formatScore(60), "60")
        XCTAssertEqual(FitnessApiService.FitnessScore.formatScore(60.0), "60")
        XCTAssertEqual(FitnessApiService.FitnessScore.formatScore(78.25), "78.3")
    }

    // MARK: - FitnessNotice.fromJson + HTML 剥离

    func testNoticeFromJson() {
        let notice = FitnessApiService.FitnessNotice.fromJson([
            "id": 12,
            "title": "望江校区室外体测地点变更通知",
            "content": "<p>第一段</p><br/><p>第二段&nbsp;内容 &amp; 更多</p>",
            "create_time": "2025年04月23日 17:44",
            "read_num": "123",
            "is_stick": 1,
        ])
        XCTAssertEqual(notice.id, "12")
        XCTAssertEqual(notice.title, "望江校区室外体测地点变更通知")
        XCTAssertEqual(notice.time, "2025年04月23日 17:44")
        XCTAssertEqual(notice.readNum, 123)
        XCTAssertTrue(notice.isSticky)
        // <p>→\n 与 <br/>→\n 相邻会产生空行（与 Dart stripFitnessHtml 一致）
        XCTAssertEqual(notice.plainContent, "第一段\n\n第二段 内容 & 更多")
    }

    func testNoticeNotSticky() {
        let notice = FitnessApiService.FitnessNotice.fromJson(["id": "1", "is_stick": 0])
        XCTAssertFalse(notice.isSticky)
        XCTAssertTrue(FitnessApiService.FitnessNotice.fromJson(["id": "2"]).isSticky == false)
    }

    func testStripHtmlEntitiesAndTags() {
        let plain = FitnessApiService.FitnessNotice.stripHtml(
            "<p style=\"x\">A</p><div>B&lt;C&gt;</div><p></p><p></p>D&nbsp;E")
        XCTAssertTrue(plain.contains("A\n"))
        XCTAssertTrue(plain.contains("B<C>"))
        XCTAssertTrue(plain.hasSuffix("D E"))
    }

    // MARK: - fetchScore API 行为（无数据年份 / 会话失效）

    private func makeFitnessApi() async throws -> FitnessApiService {
        let secure = InMemorySecureStore()
        let defaults = InMemoryDefaultsStore()
        let auth = ScuAuth(
            transport: StubTransport(),
            secure: secure,
            defaults: defaults,
            log: AuthLogger.shared,
            cookieClientFactory: {
                CookieClient(log: AuthLogger.shared, sessionConfiguration: StubURLProtocol.makeConfig())
            }
        )
        await secure.write(StorageKeys.scuAccessToken, "tok")
        let binding: [String: String] = [
            "principal": "user1",
            "tokenFingerprint": tokenFingerprint("tok"),
        ]
        await secure.write(
            StorageKeys.scuPrincipalBinding,
            String(data: try! JSONSerialization.data(withJSONObject: binding), encoding: .utf8)!
        )
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970))
        await auth.restoreFromStorage()
        StubURLProtocol.handler = { request in
            if request.url!.host == "pead.scu.edu.cn" {
                let path = request.url!.path
                let body = path.contains("getStudentScore") ? Self.noDataBody
                    : (path.contains("getSchoolNoticeList") ? Self.noticeBody : "index")
                return (200, [:], Data(body.utf8))
            }
            // SSO 握手 / session-save 等一律 success（与 SubsystemAuthTests.makeScuAuthReady 一致）
            return (200, [:], Data(#"{"success":true}"#.utf8))
        }
        return FitnessApiService(auth: SubsystemAuthFactory.fitness(scuAuth: auth))
    }

    private static let noDataBody = #"{"status":1,"info":"未查询到该学年体测成绩","data":[]}"#
    private static let noticeBody = #"{"status":1,"data":[{"id":"9","title":"免测现场审核公告","content":"<p>内容</p>","create_time":"2023年06月08日 15:03","read_num":5,"is_stick":0}]}"#

    func testFetchScoreNoDataYearReturnsNil() async throws {
        let api = try await makeFitnessApi()
        let score = try await api.fetchScore(year: "2026")
        XCTAssertNil(score)
        // 请求体带 year_num
        let body = StubURLProtocol.recordedRequests.last { $0.url.path.contains("getStudentScore") }?
            .bodyString ?? ""
        XCTAssertTrue(body.contains("year_num=2026"), "请求体应为 year_num=2026，实际 \(body)")
    }

    func testFetchNoticesParsesList() async throws {
        let api = try await makeFitnessApi()
        let notices = try await api.fetchNotices()
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].title, "免测现场审核公告")
        XCTAssertEqual(notices[0].plainContent, "内容")
    }

    func testFetchScoreSessionExpiredThrowsUnauthenticated() async throws {
        StubURLProtocol.handler = nil
        let secure = InMemorySecureStore()
        let defaults = InMemoryDefaultsStore()
        let auth = ScuAuth(
            transport: StubTransport(),
            secure: secure,
            defaults: defaults,
            log: AuthLogger.shared,
            cookieClientFactory: {
                CookieClient(log: AuthLogger.shared, sessionConfiguration: StubURLProtocol.makeConfig())
            }
        )
        await secure.write(StorageKeys.scuAccessToken, "tok")
        let binding: [String: String] = [
            "principal": "user1",
            "tokenFingerprint": tokenFingerprint("tok"),
        ]
        await secure.write(
            StorageKeys.scuPrincipalBinding,
            String(data: try! JSONSerialization.data(withJSONObject: binding), encoding: .utf8)!
        )
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970))
        await auth.restoreFromStorage()
        StubURLProtocol.handler = { request in
            if request.url!.host == "pead.scu.edu.cn", request.url!.path.contains("getStudentScore") {
                return (200, [:], Data(#"{"status":0,"info":"登录信息失效，请重新登录"}"#.utf8))
            }
            if request.url!.host == "pead.scu.edu.cn" {
                return (200, [:], Data("index".utf8))
            }
            return (200, [:], Data(#"{"success":true}"#.utf8))
        }
        let api = FitnessApiService(auth: SubsystemAuthFactory.fitness(scuAuth: auth))
        do {
            _ = try await api.fetchScore(year: "2025")
            XCTFail("应抛未认证错误")
        } catch let error as SCUError {
            XCTAssertTrue(error.isUnauthenticated)
        }
    }
}
