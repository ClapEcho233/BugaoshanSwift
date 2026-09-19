import XCTest
@testable import BugaoshanSwift

/// 无感认证模型解析（对应 models/passpoint.dart 的字段容错）
final class PasspointTests: XCTestCase {

    func testDeviceFromJson() {
        let device = PasspointDevice.fromJson([
            "userMac": "B8782EBDCE85",
            "macExpireTime": "2026-09-02",
            "defaultServiceName": "中国电信",
            "isOnline": true,
        ])
        XCTAssertEqual(device.userMac, "B8782EBDCE85")
        XCTAssertEqual(device.defaultServiceName, "中国电信")
        XCTAssertTrue(device.isOnline)
        XCTAssertNotNil(device.macExpireTime)
    }

    func testDeviceExpireTimeUnparseable() {
        // 空 / 0（最长有效期 6 年）→ nil
        for raw in ["", "0", "not-a-date"] {
            XCTAssertNil(PasspointDevice.fromJson(["userMac": "A", "macExpireTime": raw]).macExpireTime, "raw=\(raw)")
        }
    }

    func testDeviceIsOnlineVariants() {
        XCTAssertTrue(PasspointDevice.fromJson(["userMac": "A", "isOnline": 1]).isOnline)
        XCTAssertTrue(PasspointDevice.fromJson(["userMac": "A", "isOnline": "true"]).isOnline)
        XCTAssertFalse(PasspointDevice.fromJson(["userMac": "A", "isOnline": "0"]).isOnline)
        XCTAssertFalse(PasspointDevice.fromJson(["userMac": "A"]).isOnline)
    }

    func testUserInfoFromJsonAndOnline() {
        let user = PasspointUserInfo.fromJson([
            "userId": "2021141463017",
            "userName": "张三",
            "userGroupName": "学生组",
            "accountState": 1,
            "mobile": "",
            "email": "",
        ])
        XCTAssertEqual(user.userId, "2021141463017")
        XCTAssertEqual(user.userName, "张三")
        XCTAssertTrue(user.isOnline)
        XCTAssertFalse(PasspointUserInfo.fromJson(["accountState": "0"]).isOnline)
    }

    func testExitLabels() {
        XCTAssertEqual(PasspointExit.label(for: ""), "校园网")
        XCTAssertEqual(PasspointExit.label(for: "中国电信"), "中国电信")
        XCTAssertNil(PasspointExit.label(for: "未知出口"))
    }
}
