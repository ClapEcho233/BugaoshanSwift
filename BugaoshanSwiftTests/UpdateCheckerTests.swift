import XCTest
@testable import BugaoshanSwift

/// GitHub 版本比较（update_checker.dart 语义）
final class UpdateCheckerTests: XCTestCase {

    func testStripVPrefix() {
        XCTAssertEqual(UpdateChecker.stripVPrefix("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.stripVPrefix("1.2.3"), "1.2.3")
    }

    func testParseVersion() {
        XCTAssertEqual(UpdateChecker.parseVersion("1.2.3"), [1, 2, 3])
        XCTAssertEqual(UpdateChecker.parseVersion("v1.2.3+5"), [1, 2, 3])
        XCTAssertEqual(UpdateChecker.parseVersion("1.2"), [1, 2, 0])
        XCTAssertNil(UpdateChecker.parseVersion("abc"))
    }

    func testHasUpdate() {
        XCTAssertTrue(UpdateChecker.hasUpdate(currentVersion: "1.2.0", latestVersion: "v1.3.0"))
        XCTAssertTrue(UpdateChecker.hasUpdate(currentVersion: "1.2.9", latestVersion: "1.2.10"))
        XCTAssertFalse(UpdateChecker.hasUpdate(currentVersion: "1.2.3", latestVersion: "1.2.3"))
        XCTAssertFalse(UpdateChecker.hasUpdate(currentVersion: "2.0.0", latestVersion: "1.9.9"))
        // 非法输入保守处理
        XCTAssertFalse(UpdateChecker.hasUpdate(currentVersion: "x", latestVersion: "9.9.9"))
    }

    func testPrereleaseBaseVersion() {
        XCTAssertEqual(UpdateChecker.prereleaseBaseVersion("v2.3.0-pre7"), "2.3.0")
        XCTAssertEqual(UpdateChecker.prereleaseBaseVersion("2.3.0"), "2.3.0")
        XCTAssertNil(UpdateChecker.prereleaseBaseVersion("vnext"))
    }

    func testIsNewerPrerelease() {
        // 与当前 tag 相同 → false
        XCTAssertFalse(UpdateChecker.isNewerPrerelease("v2.3.0-pre7", currentVersion: "2.2.0", gitTag: "v2.3.0-pre7"))
        // nil → false
        XCTAssertFalse(UpdateChecker.isNewerPrerelease(nil, currentVersion: "2.2.0", gitTag: "v2.2.0"))
        // 基础版本高于当前 → true
        XCTAssertTrue(UpdateChecker.isNewerPrerelease("v2.3.0-pre7", currentVersion: "2.2.0", gitTag: "v2.2.0"))
        // 基础版本不高于当前 → false（同版预发布不提示）
        XCTAssertFalse(UpdateChecker.isNewerPrerelease("v2.2.0-pre1", currentVersion: "2.2.0", gitTag: "v2.1.0"))
    }

    func testFileNameFromContentDisposition() {
        XCTAssertEqual(
            DownloadManager.fileNameFromContentDisposition("attachment; filename*=UTF-8''%E9%80%9A%E7%9F%A5.pdf"),
            "通知.pdf"
        )
        XCTAssertEqual(
            DownloadManager.fileNameFromContentDisposition("attachment; filename=\"notice.pdf\""),
            "notice.pdf"
        )
        XCTAssertEqual(
            DownloadManager.fileNameFromContentDisposition("attachment; filename=plain.docx"),
            "plain.docx"
        )
        XCTAssertNil(DownloadManager.fileNameFromContentDisposition("inline"))
    }

    func testSanitizeDownloadFileName() {
        XCTAssertEqual(sanitizeDownloadFileName("a/b\\c.pdf"), "c.pdf")
        XCTAssertEqual(sanitizeDownloadFileName(".."), "download")
        XCTAssertEqual(sanitizeDownloadFileName("name<>:?.pdf"), "name____.pdf")
    }
}
