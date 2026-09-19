import Foundation

/// HTTP 请求/响应值类型（对应 Dart http 包的 Request/Response 形态）
struct HTTPRequest {
    var method: String
    var url: URL
    var headers: [String: String] = [:]
    var body: Data? = nil

    init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    init(method: String, urlString: String, headers: [String: String] = [:], body: Data? = nil) throws {
        guard let url = URL(string: urlString) else {
            throw SCUError.service("无效的 URL: \(urlString)")
        }
        self.init(method: method, url: url, headers: headers, body: body)
    }
}

struct HTTPResponse {
    var statusCode: Int
    /// 键已小写化
    var headers: [String: String]
    var body: Data
    var finalURL: URL

    var bodyString: String { String(data: body, encoding: .utf8) ?? "" }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Cookie 感知 HTTP 客户端（对应 lib/services/auth/cookie_client.dart）：
/// - 按 host 隔离的内存 cookie jar，发送时只带当前请求域（精确 host 或父域）的 cookie
/// - 手动跟随重定向（≤10 跳），每跳只带目标域 cookie、收集 Set-Cookie
/// - 跨源跳剥离 authorization / proxy-authorization / cookie 敏感头
/// - 传输错误（连接丢失）重建会话重试一次；15s 超时
/// - 对象身份作为「根 client 是否更换」的信号（子系统据此清缓存）
///
/// actor 隔离可变状态；每个实例独立 URLSession（ephemeral，不落共享 cookie/缓存）。
actor CookieClient {

    private static let sensitiveRedirectHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie",
    ]

    private var jar: [String: [String: String]] = [:]
    private var session: URLSession?
    private let redirectDelegate = NoRedirectDelegate()
    private let log: AuthLogger
    private let sessionConfiguration: URLSessionConfiguration?

    /// session/save 成功后置 true；普通 close() 不关闭可复用 client
    var reusable = false

    func markReusable() {
        reusable = true
    }

    init(log: AuthLogger = .shared, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.log = log
        self.sessionConfiguration = sessionConfiguration
    }

    deinit {
        session?.finishTasksAndInvalidate()
    }

    // MARK: - 普通请求（自动 jar cookie + 手动逐跳重定向）

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var headers = request.headers
        let cookies = cookies(for: request.url)
        if !cookies.isEmpty {
            headers["Cookie"] = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
        let response = try await performWithRetry(
            method: request.method, url: request.url, headers: headers, body: request.body,
            storeCookiesHost: request.url
        )
        log.d("CookieClient", "\(request.method) \(request.url.host ?? "")\(request.url.path) -> \(response.statusCode)")
        return response
    }

    // MARK: - 手动重定向跟随（SSO 链）

    /// 逐跳 GET：每跳只带当前跳目标域 cookie，收集 Set-Cookie 存回对应域；
    /// 敏感头仅在初始 URL 或 allowedOrigins 同源时转发。
    func followRedirects(
        to url: URL,
        headers: [String: String]? = nil,
        sensitiveHeaderAllowedOrigins: Set<URL> = [],
        maxRedirects: Int = 10
    ) async throws -> HTTPResponse {
        var current = url
        var lastResponse: HTTPResponse?

        log.d("CookieClient", "followRedirects: start url=\(url) maxRedirects=\(maxRedirects)")
        for i in 0...maxRedirects {
            var hopHeaders = redirectHeaders(
                initialUrl: url, currentUrl: current,
                headers: headers, allowedOrigins: sensitiveHeaderAllowedOrigins
            )
            let cookies = cookies(for: current)
            if !cookies.isEmpty {
                hopHeaders["Cookie"] = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            }

            let response = try await performWithRetry(
                method: "GET", url: current, headers: hopHeaders, body: nil,
                storeCookiesHost: current
            )

            if (300..<400).contains(response.statusCode) {
                guard let location = response.header("location") else {
                    log.d("CookieClient", "followRedirects: no location, end hop=\(i) status=\(response.statusCode)")
                    return response
                }
                log.d("CookieClient", "redirect hop=\(i) \(response.statusCode) \(current.host ?? "?") -> \(location)")
                guard let next = URL(string: location, relativeTo: current)?.absoluteURL else {
                    throw SCUError.service("SSO 重定向地址无法解析: \(location)")
                }
                current = next
                lastResponse = response
            } else {
                log.d("CookieClient", "followRedirects: end hop=\(i) status=\(response.statusCode) url=\(current)")
                return response
            }
        }
        log.e("CookieClient", "followRedirects: max redirects exceeded, last url=\(current)")
        throw SCUError.service("SSO 重定向链超过上限", statusCode: lastResponse?.statusCode)
    }

    // MARK: - 生命周期

    /// 尊重 reusable 的关闭（登出/替换必须用 closeForce）
    func close() {
        guard !reusable else { return }
        session?.finishTasksAndInvalidate()
        session = nil
    }

    func closeForce() {
        session?.finishTasksAndInvalidate()
        session = nil
    }

    /// 所有域 cookie 拼接（仅调试日志用）
    var cookieHeader: String {
        var all: [String: String] = [:]
        for cookies in jar.values {
            for (k, v) in cookies { all[k] = v }
        }
        return all.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    // MARK: - Cookie jar

    /// 域匹配：精确 host 或父域
    private func cookies(for url: URL) -> [String: String] {
        guard let host = url.host?.lowercased() else { return [:] }
        var result: [String: String] = [:]
        for (jarHost, cookies) in jar {
            if host == jarHost || host.hasSuffix(".\(jarHost)") {
                for (k, v) in cookies { result[k] = v }
            }
        }
        return result
    }

    /// 解析并存储 Set-Cookie（Dart 同款前瞻正则切分，避免切断 expires 日期中的逗号）
    private func storeCookies(host rawHost: String, response: HTTPResponse) {
        guard let raw = response.header("set-cookie") else { return }
        let host = rawHost.lowercased()

        var stored: [String] = []
        let parts = Self.splitSetCookieHeader(raw)
        for part in parts {
            let kv = part.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let eq = kv.firstIndex(of: "="), eq != kv.startIndex else { continue }
            let name = String(kv[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(kv[kv.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            jar[host, default: [:]][name] = value
            stored.append(name)
        }
        if !stored.isEmpty {
            log.d("CookieClient", "set-cookie host=\(host) count=\(stored.count) [\(stored.joined(separator: ","))]")
        }
    }

    /// `,\s*(?=[A-Za-z][^,=\s]*\s*=)`：仅当逗号后紧跟 `name=` 形态才切分
    static func splitSetCookieHeader(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var scanner = raw.startIndex
        let lookahead = try! NSRegularExpression(pattern: ",\\s*(?=[A-Za-z][^,=\\s]*\\s*=)")

        while scanner < raw.endIndex {
            let rest = NSRange(scanner..<raw.endIndex, in: raw)
            if let match = lookahead.firstMatch(in: raw, range: rest),
               match.range.location == rest.location {
                // 在此处切分
                parts.append(String(current))
                current = ""
                scanner = raw.index(scanner, offsetBy: match.range.length)
            } else {
                current.append(raw[scanner])
                scanner = raw.index(after: scanner)
            }
        }
        parts.append(String(current))
        return parts
    }

    // MARK: - 敏感头过滤

    private func redirectHeaders(
        initialUrl: URL,
        currentUrl: URL,
        headers: [String: String]?,
        allowedOrigins: Set<URL>
    ) -> [String: String] {
        guard let headers, !headers.isEmpty else { return [:] }
        let mayForwardSensitive =
            Self.isSameOrigin(initialUrl, currentUrl)
            || allowedOrigins.contains { Self.isSameOrigin($0, currentUrl) }
        if mayForwardSensitive { return headers }
        return headers.filter { !Self.sensitiveRedirectHeaders.contains($0.key.lowercased()) }
    }

    static func isSameOrigin(_ left: URL, _ right: URL) -> Bool {
        effectivePort(left) == effectivePort(right)
            && (left.scheme?.lowercased() ?? "") == (right.scheme?.lowercased() ?? "")
            && (left.host?.lowercased() ?? "") == (right.host?.lowercased() ?? "")
    }

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return -1
        }
    }

    // MARK: - 传输（含 ClientException 重试）

    private func performWithRetry(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?,
        storeCookiesHost: URL
    ) async throws -> HTTPResponse {
        do {
            return try await performOnce(method: method, url: url, headers: headers, body: body, storeCookiesHost: storeCookiesHost)
        } catch let error as URLError where error.code == .networkConnectionLost {
            log.w("CookieClient", "send: transport error, retrying: \(error.localizedDescription)")
            session?.finishTasksAndInvalidate()
            session = nil
            return try await performOnce(method: method, url: url, headers: headers, body: body, storeCookiesHost: storeCookiesHost)
        }
    }

    private func performOnce(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?,
        storeCookiesHost: URL
    ) async throws -> HTTPResponse {
        if session == nil {
            session = Self.makeSession(delegate: redirectDelegate, configuration: sessionConfiguration)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Constants.httpTimeout
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await session!.data(for: request)
        } catch let error as URLError {
            throw SCUError.service("网络请求失败: \(error.localizedDescription)")
        } catch {
            throw SCUError.service("网络请求失败: \(error.localizedDescription)")
        }
        guard let http = urlResponse as? HTTPURLResponse else {
            throw SCUError.service("非 HTTP 响应: \(url)")
        }
        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            responseHeaders[String(describing: key).lowercased()] = String(describing: value)
        }
        let response = HTTPResponse(
            statusCode: http.statusCode,
            headers: responseHeaders,
            body: data,
            finalURL: http.url ?? url
        )
        storeCookies(host: storeCookiesHost.host ?? "", response: response)
        return response
    }

    private static func makeSession(
        delegate: NoRedirectDelegate,
        configuration: URLSessionConfiguration?
    ) -> URLSession {
        let config = configuration ?? URLSessionConfiguration.ephemeral
        if configuration == nil {
            config.timeoutIntervalForRequest = Constants.httpTimeout
            config.timeoutIntervalForResource = Constants.httpTimeout * 4
        }
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

/// 拦截自动重定向：completionHandler(nil) 让 3xx 响应直接返回，由 CookieClient 手动逐跳处理
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
