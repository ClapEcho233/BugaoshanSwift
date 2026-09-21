import XCTest
@testable import BugaoshanSwift

/// 报修工单模型解析测试
/// 重点：历史工单（已关闭等）无 activeId 时回退列表行 id（issue：详情页空白）
final class RepairModelsTests: XCTestCase {

    // MARK: - activeId 回退（对应 Flutter json['activeId'] ?? json['id'] ?? ''）

    func testActiveIdFallsBackToIdWhenNull() {
        // 历史工单：后端只返回 id，activeId 为 null
        let ticket = RepairTicket.fromJson([
            "id": "1912001",
            "status": "已关闭",
            "createTime": 1_758_000_000_000,
        ])
        XCTAssertEqual(ticket.activeId, "1912001")
    }

    func testActiveIdFallsBackToIdWhenMissingOrEmpty() {
        // activeId 字段缺失
        XCTAssertEqual(RepairTicket.fromJson(["id": "42"]).activeId, "42")
        // activeId 为空字符串（Swift 版加宽：空串查详情必然失败，回退只有收益）
        XCTAssertEqual(RepairTicket.fromJson(["id": "42", "activeId": ""]).activeId, "42")
    }

    func testActiveIdPreferredWhenPresent() {
        // 进行中工单：activeId 优先
        let ticket = RepairTicket.fromJson([
            "id": "1912001",
            "activeId": "8800123",
            "status": "待完工",
        ])
        XCTAssertEqual(ticket.activeId, "8800123")
        XCTAssertEqual(ticket.id, "8800123")
    }

    func testActiveIdEmptyWhenBothMissing() {
        XCTAssertEqual(RepairTicket.fromJson(["status": "待处理"]).activeId, "")
    }

    // MARK: - 数值型 id（Dart toString 语义）

    func testNumericIdAndActiveId() {
        // 后端某些接口返回数值型 id
        let ticket = RepairTicket.fromJson([
            "id": NSNumber(value: 1001),
            "activeId": NSNumber(value: 2002),
        ])
        XCTAssertEqual(ticket.activeId, "2002")
        XCTAssertEqual(
            RepairTicket.fromJson(["id": NSNumber(value: 1001)]).activeId, "1001")
    }
}
