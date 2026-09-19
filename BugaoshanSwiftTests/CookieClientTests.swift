import Foundation
import XCTest
@testable import BugaoshanSwift

/// CookieClient 语义复刻测试：per-host jar、父域匹配、Set-Cookie 切分、
/// 手动重定向、跨源敏感头剥离、重定向上限。
final class CookieClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> CookieClient {
        CookieClient(log: AuthLogger.shared, sessionConfiguration: StubURLProtocol.makeConfig())
    }

    // MARK: - Cookie jar

    func testStoresAndSendsCookiesSameHost() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path == "/set" {
                return (200, ["Set-Cookie": "session=abc; Path=/; HttpOnly"], Data())
            }
            return (200, [:], Data())
        }
        let client = makeClient()
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://a.scu.edu.cn/set")!))

        // 同 host 二次请求带上 cookie
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://a.scu.edu.cn/api")!))
        let cookieHeader = StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Cookie")
        XCTAssertEqual(cookieHeader, "session=abc")
    }

    func testParentDomainMatch() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.host == "scu.edu.cn" {
                return (200, ["Set-Cookie": "root=1"], Data())
            }
            return (200, [:], Data())
        }
        let client = makeClient()
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://scu.edu.cn/x")!))
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://id.scu.edu.cn/api")!))

        let cookieHeader = StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Cookie")
        XCTAssertEqual(cookieHeader, "root=1")
    }

    func testNoCrossHostLeak() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.host == "a.com" {
                return (200, ["Set-Cookie": "secret=x"], Data())
            }
            return (200, [:], Data())
        }
        let client = makeClient()
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://a.com/")!))
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://b.com/")!))

        let cookieHeader = StubURLProtocol.recordedRequests.last?.value(forHTTPHeaderField: "Cookie")
        XCTAssertNil(cookieHeader)
    }

    // MARK: - Set-Cookie 切分

    func testSplitSetCookieHeaderWithExpiresComma() {
        let raw = "a=1; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT, b=2; Path=/"
        let parts = CookieClient.splitSetCookieHeader(raw)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].hasPrefix("a=1"))
        XCTAssertTrue(parts[1].hasPrefix("b=2"))
    }

    // MARK: - followRedirects

    func testFollowRedirectsPerHopCookies() async throws {
        StubURLProtocol.handler = { request in
            switch (request.url!.host, request.url!.path) {
            case ("id.scu.edu.cn", "/seed"):
                return (200, ["Set-Cookie": "sso=1; Path=/"], Data())
            case ("id.scu.edu.cn", "/start"):
                return (302, ["Location": "https://app.scu.edu.cn/landing"], Data("sso".utf8))
            case ("app.scu.edu.cn", "/landing"):
                return (200, [:], Data("ok".utf8))
            default:
                return nil
            }
        }
        let client = makeClient()
        // 先在 id.scu.edu.cn 域种下 cookie
        _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://id.scu.edu.cn/seed")!))

        let response = try await client.followRedirects(
            to: URL(string: "https://id.scu.edu.cn/start")!,
            headers: ["Authorization": "Bearer tok"]
        )
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.bodyString, "ok")

        // start（同源）：带 Authorization + cookie；landing（跨源）：两者都剥离
        let start = StubURLProtocol.recordedRequests[1]
        XCTAssertEqual(start.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(start.value(forHTTPHeaderField: "Cookie"), "sso=1")
        let landing = StubURLProtocol.recordedRequests.last!
        XCTAssertNil(landing.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(landing.value(forHTTPHeaderField: "Cookie"))
    }

    func testSensitiveHeaderAllowedOrigin() async throws {
        StubURLProtocol.handler = { request in
            switch request.url!.host {
            case "id.scu.edu.cn":
                return (302, ["Location": "https://allowed.scu.edu.cn/x"], Data())
            default:
                return (200, [:], Data())
            }
        }
        let client = makeClient()
        _ = try await client.followRedirects(
            to: URL(string: "https://id.scu.edu.cn/start")!,
            headers: ["Authorization": "Bearer tok"],
            sensitiveHeaderAllowedOrigins: [URL(string: "https://allowed.scu.edu.cn/")!]
        )
        let final = StubURLProtocol.recordedRequests.last!
        XCTAssertEqual(final.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testRelativeLocationResolution() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path == "/step1" {
                return (302, ["Location": "/step2"], Data())
            }
            return (200, [:], Data("done".utf8))
        }
        let client = makeClient()
        let response = try await client.followRedirects(to: URL(string: "https://x.scu.edu.cn/step1")!)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(StubURLProtocol.recordedRequests.last!.url!.absoluteString, "https://x.scu.edu.cn/step2")
    }

    func testMaxRedirectsExceeded() async throws {
        StubURLProtocol.handler = { _ in
            (302, ["Location": "https://loop.scu.edu.cn/next"], Data())
        }
        let client = makeClient()
        do {
            _ = try await client.followRedirects(to: URL(string: "https://loop.scu.edu.cn/start")!)
            XCTFail("应抛出重定向上限错误")
        } catch let error as SCUError {
            if case .service(let message, _) = error {
                XCTAssertTrue(message.contains("重定向链超过上限"))
            } else {
                XCTFail("错误类型不符: \(error)")
            }
        }
        // 11 次请求（0...10 跳）
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 11)
    }

    // MARK: - reusable / close

    func testReusableCloseIsNoop() async {
        let client = makeClient()
        await client.markReusable()
        await client.close()
        // reusable close 不销毁会话（无崩溃即可）
    }
}
