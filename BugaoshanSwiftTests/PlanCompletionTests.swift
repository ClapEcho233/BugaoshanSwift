import XCTest
@testable import BugaoshanSwift

/// 方案修读解析（对应 zhjw_html_parsers.dart 多分支逻辑）
final class PlanCompletionTests: XCTestCase {

    // MARK: - zNodes

    func testTryParseZNodesMissReturnsNil() {
        // 选择页不含 zNodes → nil（继续走链接提取分支）
        XCTAssertNil(try ZhjwApiService.tryParseZNodes("<html><body>选择页</body></html>"))
    }

    func testTryParseZNodesEmptyArray() throws {
        let html = "var zNodes = [];"
        let nodes = try XCTUnwrap(try ZhjwApiService.tryParseZNodes(html))
        XCTAssertTrue(nodes.isEmpty)
    }

    func testParseZNodesThrowsOnMiss() {
        XCTAssertThrowsError(try ZhjwApiService.parseZNodes("<html></html>"))
    }

    func testNodeFromJsonCategory() throws {
        let json: [[String: Any]] = [[
            "id": "8a8080", "pId": "-1", "flagId": "", "flagType": "001",
            "name": "公共基础课(最低修读学分:25,已及格课程门数:17,必修课未修读:3)",
            "sfwc": "是", "yxxf": "22.5", "zsxf": "25",
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let text = String(data: data, encoding: .utf8)!
        let nodes = try ZhjwApiService.parseZNodes("var zNodes = \(text);")
        XCTAssertEqual(nodes.count, 1)
        let node = nodes[0]
        XCTAssertTrue(node.isCategory)
        XCTAssertFalse(node.isCourse)
        XCTAssertTrue(node.completed)
        XCTAssertEqual(node.earnedCredits, "22.5")
        XCTAssertEqual(node.requiredCredits, "25")
        XCTAssertFalse(node.name.contains("<"))
    }

    func testNodeFromJsonCourseFields() throws {
        // [304112010]新生研讨课[1学分,2023-2024学年秋](必修,96.0(20240107))
        let json: [[String: Any]] = [[
            "id": "c1", "pId": "g1", "flagType": "kch",
            "name": "[304112010]新生研讨课[1学分,2023-2024学年秋](必修,96.0(20240107))",
            "sfwc": "是", "yxxf": "1", "zsxf": "1",
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let text = String(data: data, encoding: .utf8)!
        let nodes = try ZhjwApiService.parseZNodes("var zNodes = \(text);")
        let node = try XCTUnwrap(nodes.first)
        XCTAssertTrue(node.isCourse)
        XCTAssertEqual(node.courseCode, "304112010")
        XCTAssertEqual(node.courseName, "新生研讨课")
        XCTAssertEqual(node.courseCredits, "1")
        XCTAssertEqual(node.academicTerm, "2023-2024学年秋")
        XCTAssertEqual(node.gradeInfo, "(必修,96.0(20240107))")
    }

    // MARK: - 方案名与链接

    func testExtractPlanName() {
        let html = """
        legend: { data: ['2021级计算机科学与技术培养方案'] },
        """
        XCTAssertEqual(ZhjwApiService.extractPlanName(html), "2021级计算机科学与技术培养方案")
        XCTAssertEqual(ZhjwApiService.extractPlanName("<html></html>"), "")
    }

    func testExtractPlanLinksButtonEntities() {
        // 真机形态：onclick 引号是 &#39; 实体；title 尾部 (ID) 需剥掉
        let html = #"<button type="button" class="btn" title="广播电视编导培养方案(10692)" onclick="getPyfaIndex(&#39;10692&#39;);">查看</button>"#
        let links = ZhjwApiService.extractPlanLinks(html)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].id, "10692")
        XCTAssertEqual(links[0].name, "广播电视编导培养方案")
        XCTAssertEqual(links[0].path, "/student/integratedQuery/planCompletion/getPyfaIndex/10692")
    }

    func testExtractPlanLinksAnchorFallback() {
        let html = #"<a href="/student/integratedQuery/planCompletion/getPyfaIndex/42?x=1">第二学&nbsp;士</a>"#
        let links = ZhjwApiService.extractPlanLinks(html)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].id, "42")
        XCTAssertEqual(links[0].name, "第二学 士")
    }

    func testExtractPlanLinksBareIdFallback() {
        let links = ZhjwApiService.extractPlanLinks("var x = 'getPyfaIndex/7'")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].id, "7")
        XCTAssertEqual(links[0].name, "方案7")
    }

    func testExtractPlanLinksDedup() {
        let html = #"<button title="A(1)" onclick="getPyfaIndex('1');"></button><a href="getPyfaIndex/1">A</a>"#
        XCTAssertEqual(ZhjwApiService.extractPlanLinks(html).count, 1)
    }

    // MARK: - 摘要统计

    func testSummaryStats() {
        let nodes = [
            node(id: "1", pId: "-1", flagType: "001", sfwc: "是", yxxf: "25", zsxf: "25"),
            node(id: "2", pId: "-1", flagType: "002", sfwc: "否", yxxf: "3", zsxf: "8"),
            node(id: "3", pId: "1", flagType: "001", sfwc: "是", yxxf: "99", zsxf: "99"), // 非根级不计
        ]
        let stats = PlanCompletionSummaryStats.compute(nodes)
        XCTAssertEqual(stats.totalEarned, 28, accuracy: 0.001)
        XCTAssertEqual(stats.completedCount, 1)
        XCTAssertEqual(stats.moduleCount, 2)
    }

    private func node(id: String, pId: String, flagType: String, sfwc: String, yxxf: String, zsxf: String) -> PlanCompletionNode {
        PlanCompletionNode(
            id: id, pId: pId, flagId: "", flagType: flagType,
            name: "n\(id)", rawName: "n\(id)", completed: sfwc == "是",
            earnedCredits: yxxf, requiredCredits: zsxf,
            courseCode: "", courseName: "", courseCredits: "", academicTerm: "", gradeInfo: ""
        )
    }
}
