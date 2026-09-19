import Foundation

/// 子系统认证协议（对应 lib/services/auth/subsystem_auth.dart）。
/// 仅声明真实 L2 依赖；SCU 根认证不算依赖。 AnyObject：调度器按对象身份去重。
protocol SubsystemAuth: AnyObject, Sendable {
    var moduleId: String { get }
    var dependencies: [any SubsystemAuth] { get }
    func ensureAuthenticated() async throws
    func invalidate() async
}

func ensureAuthDependencies(_ dependencies: [any SubsystemAuth]) async throws {
    for dep in dependencies {
        try await dep.ensureAuthenticated()
    }
}

// MARK: - L1 API 层统一模板（api_request.dart）

/// 认证过期自动重放（精确一次）：仅 UnauthenticatedException 触发；
/// ServiceException / RateLimited / CCYL 普通错误原样冒泡。
func withAuthRetry<T>(
    _ getClient: @escaping () async throws -> CookieClient,
    invalidate: (@Sendable () async -> Void)? = nil,
    _ fn: @escaping (CookieClient) async throws -> T
) async throws -> T {
    do {
        let client = try await getClient()
        return try await fn(client)
    } catch let error as SCUError where error.isUnauthenticated {
        if let invalidate {
            await invalidate()
        }
        let client = try await getClient()
        return try await fn(client)
    }
}

// MARK: - 登录页检测（issue #282 回归语义）

/// HTML-only 登录页检测（zhjw / wfw / newservice 过期判断共用）：
/// 1. 非 `<` 开头（纯 JSON/文本）直接 false
/// 2. 四个强特征任一命中 → 登录页
/// 刻意不用 `type=password`（改密页也有）与裸子串 `login`（loginStatus 误报）
enum LoginPageDetector {

    private static let reTitle = try! NSRegularExpression(pattern: #"<title[^>]*>([^<]*)</title>"#)
    private static let reSpringForm = try! NSRegularExpression(
        pattern: #"<form[^>]+action\s*=\s*["'][^"']*j_spring_security_check"#)
    private static let reMetaRefresh = try! NSRegularExpression(
        pattern: #"content\s*=\s*["'][^"']*url=([^"'>\s]+)"#)
    private static let reJsLocation = try! NSRegularExpression(
        pattern: #"location\s*\.\s*(?:href|replace|assign)\s*[=(]\s*["']([^"']+)["']"#)
    private static let reFormAction = try! NSRegularExpression(
        pattern: #"<form[^>]+action\s*=\s*["']([^"']*)["']"#)
    private static let reLoginWord = try! NSRegularExpression(pattern: #"\blogin\b"#)

    static func looksLikeLoginPage(_ body: String) -> Bool {
        // HTML 哨兵：trimLeft 后必须以 '<' 开头
        var start = body.startIndex
        while start < body.endIndex, body[start].isWhitespace {
            start = body.index(after: start)
        }
        guard start < body.endIndex, body[start] == "<" else { return false }

        let lower = body.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)

        func matchesLoginWord(_ target: String) -> Bool {
            let lowerTarget = target.lowercased()
            return lowerTarget.contains("登录")
                || reLoginWord.firstMatch(in: lowerTarget, range: NSRange(lowerTarget.startIndex..., in: lowerTarget)) != nil
        }

        // 1. <title> 含「登录」或 \blogin\b
        if let m = reTitle.firstMatch(in: lower, range: range),
           let title = captureGroup(m, in: lower, at: 1) {
            if matchesLoginWord(title) { return true }
        }

        // 2. Spring Security 表单 action
        if reSpringForm.firstMatch(in: lower, range: range) != nil {
            return true
        }

        // 3. meta refresh / JS 跳转到 login URL
        if let m = reMetaRefresh.firstMatch(in: lower, range: range),
           let url = captureGroup(m, in: lower, at: 1), matchesLoginWord(url) {
            return true
        }
        if let m = reJsLocation.firstMatch(in: lower, range: range),
           let url = captureGroup(m, in: lower, at: 1), matchesLoginWord(url) {
            return true
        }

        // 4. <form action> 指向 login URL
        if let m = reFormAction.firstMatch(in: lower, range: range),
           let action = captureGroup(m, in: lower, at: 1), !action.isEmpty, matchesLoginWord(action) {
            return true
        }

        return false
    }

    private static func captureGroup(_ match: NSTextCheckingResult, in text: String, at index: Int) -> String? {
        guard match.numberOfRanges > index, let r = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[r])
    }
}

// MARK: - HTTPResponse 便捷

extension HTTPResponse {
    /// 从 finalURL 提取查询参数
    var queryItems: [String: String] {
        guard let comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
