import Foundation
import XCTest
@testable import BugaoshanSwift

/// 子系统认证层测试：登录页检测、zhhq AES、表单编码、SSO 中继、WfwAuth、调度器。
final class SubsystemAuthTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: - LoginPageDetector（issue #282 回归语义）

    func testLoginPageTitle() {
        XCTAssertTrue(LoginPageDetector.looksLikeLoginPage(
            "<html><head><title>统一身份认证 登录</title></head></html>"))
        XCTAssertTrue(LoginPageDetector.looksLikeLoginPage(
            "<html><head><title>User Login</title></head></html>"))
        // loginStatus 不能误报
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage(
            #"<html><head><title>loginStatus</title></head></html>"#))
    }

    func testLoginPageSpringForm() {
        XCTAssertTrue(LoginPageDetector.looksLikeLoginPage(
            #"<html><form id="f" action="/j_spring_security_check" method="post"></form></html>"#))
    }

    func testLoginPageMetaRefresh() {
        XCTAssertTrue(LoginPageDetector.looksLikeLoginPage(
            #"<meta http-equiv="refresh" content="0;url=/cas/login?service=x">"#))
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage(
            #"<meta http-equiv="refresh" content="0;url=/home">"#))
    }

    func testLoginPageFormAction() {
        XCTAssertTrue(LoginPageDetector.looksLikeLoginPage(
            #"<form action="/account/login" method="get"></form>"#))
    }

    func testLoginPageSentinel() {
        // 纯 JSON 不算登录页
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage(#"{"e":0,"m":"ok"}"#))
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage(""))
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage("   {\"login\":1}"))
    }

    func testLoginPagePasswordPageNotLogin() {
        // 改密页（有 password 框但 title 不含 login）不应误报
        XCTAssertFalse(LoginPageDetector.looksLikeLoginPage(
            "<html><head><title>修改密码</title></head><body><input type=\"password\"/></body></html>"))
    }

    // MARK: - ZhhqCrypto（openssl 参考向量）

    func testZhhqAesEncryptVectors() throws {
        XCTAssertEqual(
            try ZhhqCrypto.encrypt("hello"),
            "7Vtcdi6L+6A9Fm64JTBaLg=="
        )
        XCTAssertEqual(
            try ZhhqCrypto.encrypt(#"{"e":0}"#),
            "Ie46hCnoxIgH+78YlkzbVA=="
        )
        XCTAssertEqual(
            try ZhhqCrypto.encrypt("四川大学10610"),
            "d8ZZ9Vr8ErBaIOZkL68ls9xEh29VK7sfD5bAJov4c6k="
        )
        XCTAssertEqual(
            try ZhhqCrypto.encrypt("hello", key: ZhhqCrypto.clientSecret, iv: ZhhqCrypto.clientId),
            "5TsOGzrrm9+75UsaVaQuTQ=="
        )
    }

    func testZhhqAesRoundTrip() throws {
        let cipher = try ZhhqCrypto.encrypt("测试字符串 test 123!@#")
        XCTAssertEqual(ZhhqCrypto.decrypt(cipher), "测试字符串 test 123!@#")
    }

    func testZhhqDecodeResponse() {
        let json: [String: Any] = ["errorCode": "0", "status": "success", "data": "abcdefghijklmnop"]
        let body = try! ZhhqCrypto.encrypt(
            String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!)
        let decoded = ZhhqCrypto.zhhqDecodeResponse(body)
        XCTAssertEqual(decoded?["data"] as? String, "abcdefghijklmnop")
        XCTAssertNil(ZhhqCrypto.zhhqDecodeResponse("not-base64-!!!"))
    }

    // MARK: - FormEncoding（对齐 Dart Uri 语义）

    func testFormEncoding() {
        XCTAssertEqual(FormEncoding.encode("abc123"), "abc123")
        XCTAssertEqual(FormEncoding.encode("a b"), "a+b")
        XCTAssertEqual(FormEncoding.encode("a+b"), "a%2Bb")
        XCTAssertEqual(FormEncoding.encode("四川大学"), "%E5%9B%9B%E5%B7%9D%E5%A4%A7%E5%AD%A6")
        XCTAssertEqual(FormEncoding.encodeComponent("a b"), "a%20b")
        XCTAssertEqual(FormEncoding.encode("abc/xyz+12="), "abc%2Fxyz%2B12%3D")
    }

    // MARK: - SsoRelayAuth

    private func makeScuAuthReady() async -> ScuAuth {
        let secure = InMemorySecureStore()
        let defaults = InMemoryDefaultsStore()
        let transport = StubTransport()
        let auth = ScuAuth(
            transport: transport,
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
        // session/save 成功
        StubURLProtocol.handler = { _ in (200, [:], Data(#"{"success":true}"#.utf8)) }
        return auth
    }

    func testSsoRelayLoginAndCache() async throws {
        let scuAuth = await makeScuAuthReady()
        let relay = SubsystemAuthFactory.zhjw(scuAuth: scuAuth)

        // zhjw SSO 链返回 200
        StubURLProtocol.handler = { request in
            if request.url!.host == "zhjw.scu.edu.cn" {
                return (200, [:], Data("index".utf8))
            }
            return (200, [:], Data(#"{"success":true}"#.utf8))
        }

        let client1 = try await relay.getClient()
        let ready = await relay.isReady
        XCTAssertTrue(ready)

        // 缓存命中：不再发请求
        let count = StubURLProtocol.recordedRequests.count
        let client2 = try await relay.getClient()
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, count)
        XCTAssertTrue(client1 === client2)
    }

    func testSsoRelayRejected() async throws {
        let scuAuth = await makeScuAuthReady()
        let relay = SubsystemAuthFactory.fitness(scuAuth: scuAuth)
        StubURLProtocol.handler = { _ in (403, [:], Data()) }
        do {
            _ = try await relay.getClient()
            XCTFail("应抛未认证")
        } catch let error as SCUError {
            XCTAssertTrue(error.isUnauthenticated)
        }
    }

    // MARK: - WfwAuth

    func testWfwWarmUpBoundSession() async throws {
        let scuAuth = await makeScuAuthReady()
        let wfw = WfwAuth(scuAuth: scuAuth)
        // 已绑定的 get-info 直接返回 e==0
        StubURLProtocol.handler = { request in
            if request.url!.host == "wfw.scu.edu.cn" {
                return (200, [:], Data(#"{"e":0,"m":"","d":{}}"#.utf8))
            }
            return (200, [:], Data(#"{"success":true}"#.utf8))
        }
        _ = try await wfw.getClient()
        let ready = await wfw.isReady
        XCTAssertTrue(ready)
    }

    func testWfwWarmUpAnonymousSessionRejected() async throws {
        let scuAuth = await makeScuAuthReady()
        let wfw = WfwAuth(scuAuth: scuAuth)
        // 匿名会话：e != 0 —— 必须判未就绪（关键陷阱回归）
        StubURLProtocol.handler = { request in
            if request.url!.host == "wfw.scu.edu.cn" {
                return (200, ["Set-Cookie": "eai-sess=anonymous"], Data(#"{"e":10013,"m":"未登录"}"#.utf8))
            }
            return (200, [:], Data(#"{"success":true}"#.utf8))
        }
        do {
            _ = try await wfw.getClient()
            XCTFail("匿名会话应判未认证")
        } catch let error as SCUError {
            XCTAssertTrue(error.isUnauthenticated)
        }
        let ready = await wfw.isReady
        XCTAssertFalse(ready)
    }

    func testWfwBusinessCode10013IsUnauthenticated() async throws {
        // wfw 业务过期码 e==10013 → API 层判未认证（此处验证解析辅助）
        let json: [String: Any] = ["e": 10013, "m": "登录已失效"]
        XCTAssertEqual(SafeJSON.int(json["e"]), 10013)
    }

    // MARK: - ZhhqAuth（SSO + login/auto 换 tokenKey）

    func testZhhqFullLogin() async throws {
        let scuAuth = await makeScuAuthReady()
        let secure = InMemorySecureStore()
        let zhhq = ZhhqAuth(
            scuAuth: scuAuth,
            secure: secure,
            cookieClientFactory: {
                CookieClient(log: AuthLogger.shared, sessionConfiguration: StubURLProtocol.makeConfig())
            }
        )

        // CAS 中继 → 回跳带 userinfo；login/auto 返回加密 tokenKey
        let encryptedTokenKey = try ZhhqCrypto.encrypt("ITSOFT-WILAB-SESSION-abcdefgh")
        StubURLProtocol.handler = { request in
            switch (request.url!.host, request.url!.path) {
            case ("id.scu.edu.cn", let p) where p.hasPrefix("/enduser/sp/sso"):
                return (302, ["Location": "https://zhhq.scu.edu.cn/account/login?userinfo=ENCRYPTED_USERINFO"], Data())
            case ("id.scu.edu.cn", _):
                return (200, [:], Data(#"{"success":true}"#.utf8))
            case ("zhhq.scu.edu.cn", "/account/login"):
                return (200, [:], Data("<html>login page</html>".utf8))
            case ("zhhq.scu.edu.cn", "/api/auth/login/auto"):
                let json: [String: Any] = ["errorCode": "0", "status": "success", "data": "ITSOFT-WILAB-SESSION-abcdefgh"]
                let body = try! ZhhqCrypto.encrypt(String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!)
                return (200, [:], Data(body.utf8))
            default:
                return nil
            }
        }

        _ = try await zhhq.getClient()
        let tokenKey = await zhhq.currentTokenKey()
        XCTAssertEqual(tokenKey, "ITSOFT-WILAB-SESSION-abcdefgh")
        // 持久化
        let saved = await secure.read(StorageKeys.zhhqTokenKey)
        XCTAssertEqual(saved, "ITSOFT-WILAB-SESSION-abcdefgh")

        // login/auto 请求体：userInfo 双层编码 + timestamp AES
        let autoRequest = StubURLProtocol.recordedRequests.first { $0.url.path == "/api/auth/login/auto" }
        let bodyString = autoRequest?.bodyString ?? ""
        XCTAssertTrue(bodyString.contains("userInfo=ENCRYPTED_USERINFO"), "无特殊字符时单层结果等于原值")
        XCTAssertTrue(bodyString.contains("clientId=web201911chengdu"))
        XCTAssertTrue(bodyString.contains("schoolCode=10610"))
        XCTAssertTrue(bodyString.contains("schoolName=%E5%9B%9B%E5%B7%9D%E5%A4%A7%E5%AD%A6"))
    }

    // MARK: - AuthCoordinator（依赖拓扑 + 失败隔离）

    func testCoordinatorDependencyOrderAndIsolation() async throws {
        final class StubAuth: SubsystemAuth, @unchecked Sendable {
            let moduleId: String
            let dependencies: [any SubsystemAuth]
            let shouldFail: Bool
            private let lock = NSLock()
            private var _ensured = false
            init(_ id: String, deps: [any SubsystemAuth] = [], fail: Bool = false) {
                moduleId = id
                dependencies = deps
                shouldFail = fail
            }
            var ensured: Bool {
                lock.lock(); defer { lock.unlock() }
                return _ensured
            }
            func ensureAuthenticated() async throws {
                for dep in dependencies {
                    try await dep.ensureAuthenticated()
                }
                lock.lock()
                let already = _ensured
                _ensured = true
                lock.unlock()
                if shouldFail && !already {
                    throw SCUError.service("\(moduleId) 预热失败（仅一次）")
                }
            }
            func invalidate() async {}
        }

        let zhjw = StubAuth("zhjw")
        let failing = StubAuth("failing", fail: true)
        let dependent = StubAuth("dependent", deps: [failing])
        let coordinator = AuthCoordinator(modules: [zhjw, failing, dependent])

        // 失败不抛给调用方
        await coordinator.warmUpAll()

        let zhjwOk = await withCheckedContinuation { c in c.resume(returning: zhjw.ensured) }
        XCTAssertTrue(zhjwOk, "无关模块不受失败影响")
        // 失败模块也应被尝试过
        XCTAssertTrue(failing.ensured)
        XCTAssertTrue(dependent.ensured, "依赖失败时模块本身仍被调用（跳过）")
    }
}
