import XCTest
@testable import BugaoshanSwift

/// 校区/建筑/房间解析（calendar_location_mapper.dart 语义）
final class CalendarLocationMapperTests: XCTestCase {

    func testBuildingWithRoom() {
        // 最长 pattern 优先：一教A101 命中「第一教学楼A座」而非无座版
        let r = CalendarLocationMapper.resolve("一教A101", campusName: "江安")
        XCTAssertEqual(r.title, "四川大学江安校区第一教学楼A座 · A101")
    }

    func testRedirectNote() {
        // 综B → 逸夫教学楼（redirectNote 综B）
        let r = CalendarLocationMapper.resolve("综B503", campusName: "江安")
        XCTAssertEqual(r.title, "四川大学江安校区逸夫教学楼 · B503 (综B)")
    }

    func testCampusFromLocation() {
        let r = CalendarLocationMapper.resolve("江安 二教201")
        XCTAssertTrue(r.title.hasPrefix("四川大学江安校区"))
        XCTAssertTrue(r.title.contains("二教") || r.title.contains("教学楼"))
    }

    func testWangjiangBuilding() {
        let r = CalendarLocationMapper.resolve("基础教学楼B302", campusName: "望江")
        XCTAssertEqual(r.title, "四川大学望江校区基础教学楼B座 · B302")
    }

    func testFallbackCampusLevel() {
        // 无建筑命中但含校区建筑关键字 → 校区级
        let r = CalendarLocationMapper.resolve("文科楼三区201", campusName: "江安")
        XCTAssertTrue(r.title.hasPrefix("四川大学江安校区"))
    }

    func testUnknownLocationPassthrough() {
        let r = CalendarLocationMapper.resolve("某神秘地点")
        XCTAssertEqual(r.title, "某神秘地点")
    }

    func testEmptyLocation() {
        XCTAssertEqual(CalendarLocationMapper.resolve("").title, "")
        XCTAssertEqual(CalendarLocationMapper.resolve("", campusName: "华西").title, "四川大学华西校区")
    }

    func testRoomExtractionLetterNumberForms() {
        func room(_ raw: String) -> String {
            let building = CalendarLocationMapper.buildingLocations
                .filter { $0.campusName == "四川大学江安校区" }
                .max { $0.longestMatchLength(raw) < $1.longestMatchLength(raw) }!
            return CalendarLocationMapper.extractRoomName(raw, building: building)
        }
        XCTAssertEqual(room("一教A101"), "A101")
        XCTAssertEqual(room("综C407"), "C407")
        // 只剩座号字母 → 空
        XCTAssertEqual(room("一教A"), "")
    }

    func testLongestMatchWeights() {
        // 字母结尾 pattern 得分 +1，确保带座版胜出
        let text = "第一教学楼A101"
        let withSeat = CalendarLocationMapper.buildingLocations
            .first { $0.campusName == "四川大学江安校区" && $0.canonicalBuildingName == "第一教学楼A座" }!
        XCTAssertGreaterThan(withSeat.longestMatchLength(text), 0)
    }
}
