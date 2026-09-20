import Foundation
import XCTest
import BigInt
@testable import BugaoshanSwift

/// ScuAuth 状态机测试：登录、恢复、TTL 刷新、登出、principal 绑定。
final class ScuAuthTests: XCTestCase {

    private var transport: StubTransport!
    private var secure: InMemorySecureStore!
    private var defaults: InMemoryDefaultsStore!
    private var auth: ScuAuth!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        transport = StubTransport()
        secure = InMemorySecureStore()
        defaults = InMemoryDefaultsStore()
        auth = ScuAuth(
            transport: transport,
            secure: secure,
            defaults: defaults,
            log: AuthLogger.shared,
            cookieClientFactory: {
                CookieClient(log: AuthLogger.shared, sessionConfiguration: StubURLProtocol.makeConfig())
            },
            ocr: { _ in "abcd" }
        )
    }

    // MARK: - extractTokenErrorMessage

    func testExtractTokenErrorMessage() {
        XCTAssertEqual(
            ScuAuth.extractTokenErrorMessage(#"{"message":"invalid_captcha"}"#),
            "invalid_captcha"
        )
        XCTAssertEqual(ScuAuth.extractTokenErrorMessage(#"{"error":"bad_grant"}"#), "bad_grant")
        XCTAssertEqual(
            ScuAuth.extractTokenErrorMessage(#"{"error_description":"密码错误"}"#),
            "密码错误"
        )
        // message 优先于 error
        XCTAssertEqual(
            ScuAuth.extractTokenErrorMessage(#"{"message":"m","error":"e"}"#),
            "m"
        )
        XCTAssertNil(ScuAuth.extractTokenErrorMessage("<html>维护中</html>"))
        XCTAssertNil(ScuAuth.extractTokenErrorMessage(#"{"message":""}"#))
    }

    // MARK: - 登录

    /// 合法 04||x||y 公钥的 base64（SM2 加密入口会校验点格式）
    private static let stubPublicKeyBase64: String = {
        let x = SM2.leftPadBytes(
            BigUInt("09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020", radix: 16)!, 32)
        let y = SM2.leftPadBytes(
            BigUInt("CCEA490CE26775A52DC6EA718CC1AA600AED05FBF35E084A6632F6072DA9AD13", radix: 16)!, 32)
        return Data([0x04] + x + y).base64EncodedString()
    }()

    private func stubLoginSuccess() {
        transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap123","captcha":"aGVsbG8="}}"#)
        let keyJson = #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#
        transport.addJson(url: "sm2_key", body: keyJson)
        transport.addJson(
            url: "rest_token",
            body: #"{"success":true,"data":{"access_token":"token-abc"}}"#
        )
    }

    func testLoginHappyPath() async throws {
        stubLoginSuccess()
        try await auth.login(username: "20230001", password: "pw", captchaCode: "cap123", captchaText: "abcd")

        let token = await auth.accessToken
        XCTAssertEqual(token, "token-abc")
        let state = await auth.state
        XCTAssertEqual(state, .ready)

        // 持久化
        let savedToken = await secure.read(StorageKeys.scuAccessToken)
        XCTAssertEqual(savedToken, "token-abc")
        let ts = await defaults.int(StorageKeys.scuLoginTimestamp)
        XCTAssertNotNil(ts)

        // principal 绑定指纹
        let bindingRaw = await secure.read(StorageKeys.scuPrincipalBinding)
        let binding = try JSONSerialization.jsonObject(
            with: Data(bindingRaw!.utf8)
        ) as! [String: String]
        XCTAssertEqual(binding["principal"], "20230001")
        XCTAssertEqual(binding["tokenFingerprint"], tokenFingerprint("token-abc"))
    }

    func testLoginWrongCaptcha() async throws {
        transport.addJson(url: "sm2_key", body: #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#)
        transport.addJson(
            url: "rest_token",
            status: 400,
            body: #"{"message":"invalid_captcha"}"#
        )
        do {
            try await auth.login(username: "u", password: "p", captchaCode: "c", captchaText: "t")
            XCTFail("应抛出登录错误")
        } catch let error as SCUError {
            if case .login(let message) = error {
                XCTAssertEqual(message, "invalid_captcha")
            } else {
                XCTFail("错误类型不符: \(error)")
            }
        }
    }

    func testLoginSuccessFalseWithMessage() async throws {
        transport.addJson(url: "sm2_key", body: #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#)
        transport.addJson(url: "rest_token", body: #"{"success":false,"msg":"账号已锁定"}"#)
        do {
            try await auth.login(username: "u", password: "p", captchaCode: "c", captchaText: "t")
            XCTFail("应抛出登录错误")
        } catch let error as SCUError {
            if case .login(let message) = error {
                XCTAssertEqual(message, "账号已锁定")
            } else {
                XCTFail("错误类型不符: \(error)")
            }
        }
    }

    // MARK: - 冷启动恢复

    func testRestoreFreshToken() async throws {
        await secure.write(StorageKeys.scuAccessToken, "tok")
        let binding: [String: String] = [
            "principal": "user1",
            "tokenFingerprint": tokenFingerprint("tok"),
        ]
        await secure.write(
            StorageKeys.scuPrincipalBinding,
            String(data: try JSONSerialization.data(withJSONObject: binding), encoding: .utf8)!
        )
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970))

        await auth.restoreFromStorage()
        let state = await auth.state
        XCTAssertEqual(state, .ready)
        let principal = await auth.principal
        XCTAssertEqual(principal, "user1")
    }

    func testRestoreExpiredTokenStaysUnknown() async throws {
        await secure.write(StorageKeys.scuAccessToken, "tok")
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970) - 7200)
        await auth.restoreFromStorage()
        let state = await auth.state
        XCTAssertEqual(state, .unknown)
    }

    func testRestoreFingerprintMismatchDeletesBinding() async throws {
        await secure.write(StorageKeys.scuAccessToken, "different-token")
        let binding: [String: String] = [
            "principal": "user1",
            "tokenFingerprint": tokenFingerprint("old-token"),
        ]
        await secure.write(
            StorageKeys.scuPrincipalBinding,
            String(data: try JSONSerialization.data(withJSONObject: binding), encoding: .utf8)!
        )
        await auth.restoreFromStorage()
        let principal = await auth.principal
        XCTAssertNil(principal)
        let raw = await secure.read(StorageKeys.scuPrincipalBinding)
        XCTAssertNil(raw, "指纹不匹配应删除绑定")
    }

    // MARK: - getClient / 刷新

    func testGetClientRefreshViaBindSession() async throws {
        await secure.write(StorageKeys.scuAccessToken, "tok")
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970) - 7200)
        await auth.restoreFromStorage()

        // session/save 成功 → 刷新成功
        StubURLProtocol.handler = { request in
            (200, [:], Data(#"{"success":true}"#.utf8))
        }

        let client = try await auth.getClient()
        let state = await auth.state
        XCTAssertEqual(state, .ready)
        let ts = await defaults.int(StorageKeys.scuLoginTimestamp)
        XCTAssertNotNil(ts)
        // session/save 带上了 Bearer
        let saveRequest = StubURLProtocol.recordedRequests.first
        XCTAssertEqual(saveRequest?.headers["authorization"], "Bearer tok")
        // 第二次 getClient 缓存命中（不再发请求）
        let count = StubURLProtocol.recordedRequests.count
        _ = try await auth.getClient()
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, count)
    }

    func testGetClientRefreshFailThrowsUnauthenticated() async throws {
        await secure.write(StorageKeys.scuAccessToken, "tok")
        await defaults.setInt(StorageKeys.scuLoginTimestamp, Int(Date().timeIntervalSince1970) - 7200)
        await auth.restoreFromStorage()

        // session/save 401，且无凭据可自动登录
        StubURLProtocol.handler = { _ in (401, [:], Data()) }
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func increment() { lock.lock(); value += 1; lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        }
        let counter = Counter()
        await auth.setOnSessionExpired { counter.increment() }

        do {
            _ = try await auth.getClient()
            XCTFail("应抛出未认证错误")
        } catch let error as SCUError {
            XCTAssertTrue(error.isUnauthenticated)
        }
        XCTAssertEqual(counter.count, 1)
    }

    // MARK: - 凭据 / 自动登录

    func testAutoLoginWithOcr() async throws {
        await auth.saveCredentials(username: "u1", password: "pw1")
        stubLoginSuccess()

        let ok = try await auth.autoLogin()
        XCTAssertTrue(ok)
        let state = await auth.state
        XCTAssertEqual(state, .ready)

        // rest_token 载荷包含 OCR 结果与验证码 code
        let tokenRequest = transport.recordedRequests.first { $0.url.absoluteString.contains("rest_token") }
        let body = try JSONSerialization.jsonObject(with: tokenRequest!.body!) as! [String: String]
        XCTAssertEqual(body["cap_text"], "abcd")
        XCTAssertEqual(body["cap_code"], "cap123")
        XCTAssertEqual(body["username"], "u1")
    }

    func testAutoLoginRetriesInvalidCaptchaThenSucceeds() async throws {
        await auth.saveCredentials(username: "u1", password: "pw1")
        // 前 3 次请求中：captcha + sm2 正常，rest_token 前两次 invalid_captcha、第三次成功
        transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap1","captcha":"aGVsbG8="}}"#)
        transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap2","captcha":"aGVsbG8="}}"#)
        transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap3","captcha":"aGVsbG8="}}"#)
        let keyJson = #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#
        transport.addJson(url: "sm2_key", body: keyJson)
        transport.addJson(url: "sm2_key", body: keyJson)
        transport.addJson(url: "sm2_key", body: keyJson)
        transport.addJson(url: "rest_token", status: 400, body: #"{"message":"invalid_captcha"}"#)
        transport.addJson(url: "rest_token", status: 400, body: #"{"message":"invalid_captcha"}"#)
        transport.addJson(url: "rest_token", body: #"{"success":true,"data":{"access_token":"token-xyz"}}"#)

        let ok = try await auth.autoLogin()
        XCTAssertTrue(ok, "第三次应成功")
        let state = await auth.state
        XCTAssertEqual(state, .ready)
        // 每次尝试都取了新验证码
        let captchaCount = transport.recordedRequests.filter { $0.url.absoluteString.contains("captcha") }.count
        XCTAssertEqual(captchaCount, 3)
    }

    func testAutoLoginFailsAfterThreeInvalidCaptchas() async throws {
        await auth.saveCredentials(username: "u1", password: "pw1")
        for _ in 0..<3 {
            transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap","captcha":"aGVsbG8="}}"#)
            transport.addJson(url: "sm2_key", body: #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#)
            transport.addJson(url: "rest_token", status: 400, body: #"{"message":"invalid_captcha"}"#)
        }

        let ok = try await auth.autoLogin()
        XCTAssertFalse(ok, "三次全败应返回 false")
        let captchaCount = transport.recordedRequests.filter { $0.url.absoluteString.contains("captcha") }.count
        XCTAssertEqual(captchaCount, 3, "不应超过 3 次尝试")
    }

    func testAutoLoginFailsFastOnPasswordError() async throws {
        await auth.saveCredentials(username: "u1", password: "wrong")
        transport.addJson(url: "one_time_login/captcha", body: #"{"data":{"code":"cap","captcha":"aGVsbG8="}}"#)
        transport.addJson(url: "sm2_key", body: #"{"data":{"publicKey":"\#(Self.stubPublicKeyBase64)","code":"sm2code"}}"#)
        transport.addJson(url: "rest_token", status: 400, body: #"{"message":"用户名或密码错误"}"#)

        let ok = try await auth.autoLogin()
        XCTAssertFalse(ok)
        // 非验证码错误不重试：只拉过一次验证码
        let captchaCount = transport.recordedRequests.filter { $0.url.absoluteString.contains("captcha") }.count
        XCTAssertEqual(captchaCount, 1)
    }

    func testAutoLoginNoCredentials() async throws {
        let ok = try await auth.autoLogin()
        XCTAssertFalse(ok)
    }

    // MARK: - 登出

    func testLogoutClearsEverything() async throws {
        stubLoginSuccess()
        try await auth.login(username: "20230001", password: "pw", captchaCode: "c", captchaText: "t")
        await auth.saveCredentials(username: "u", password: "p")

        await auth.logout()
        let state = await auth.state
        XCTAssertEqual(state, .unknown)
        let token = await auth.accessToken
        XCTAssertNil(token)
        let savedToken = await secure.read(StorageKeys.scuAccessToken)
        XCTAssertNil(savedToken)
        let ts = await defaults.int(StorageKeys.scuLoginTimestamp)
        XCTAssertNil(ts)
        // 登出不动凭据（记住密码保留，由设置页管理）
        let creds = await auth.getSavedCredentials()
        XCTAssertNotNil(creds)

        // 登出后 getClient → 未登录
        do {
            _ = try await auth.getClient()
            XCTFail("应抛出未登录")
        } catch let error as SCUError {
            XCTAssertTrue(error.isUnauthenticated)
        }
    }
}
