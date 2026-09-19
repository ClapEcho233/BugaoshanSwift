import Foundation
import Combine

/// 直连 HTTP 传输（无 cookie jar；验证码/sm2_key/rest_token 等公开端点用，
/// 对应 Dart 版直接使用 package:http 的场景）。系统默认重定向行为。
protocol HTTPTransport: Sendable {
    func request(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct URLSessionTransport: HTTPTransport {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Constants.httpTimeout
        config.timeoutIntervalForResource = Constants.httpTimeout * 4
        return URLSession(configuration: config)
    }()

    func request(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = Constants.httpTimeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await Self.session.data(for: urlRequest)
        } catch let error as URLError {
            throw SCUError.service("网络请求失败: \(error.localizedDescription)")
        }
        guard let http = urlResponse as? HTTPURLResponse else {
            throw SCUError.service("非 HTTP 响应: \(request.url)")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data,
            finalURL: http.url ?? request.url
        )
    }
}

/// 测试桩：按 (method, url) 匹配脚本化的响应序列
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        var match: (HTTPRequest) -> Bool
        var response: () throws -> HTTPResponse
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private var requests: [HTTPRequest] = []

    func add(match: @escaping (HTTPRequest) -> Bool, response: @escaping () throws -> HTTPResponse) {
        lock.lock(); defer { lock.unlock() }
        stubs.append(Stub(match: match, response: response))
    }

    func addJson(url contains: String, status: Int = 200, body: String) {
        add(
            match: { $0.url.absoluteString.contains(contains) },
            response: {
                HTTPResponse(
                    statusCode: status,
                    headers: ["content-type": "application/json"],
                    body: Data(body.utf8),
                    finalURL: URL(string: "https://stub.local/\(contains)")!
                )
            }
        )
    }

    var recordedRequests: [HTTPRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func request(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        requests.append(request)
        let index = stubs.firstIndex { $0.match(request) }
        guard let index else {
            lock.unlock()
            throw SCUError.service("StubTransport: 未匹配的请求 \(request.method) \(request.url)")
        }
        let stub = stubs.remove(at: index)
        lock.unlock()
        return try stub.response()
    }
}

/// UI 状态桥：认证栈（actor）→ SwiftUI（MainActor ObservableObject）
@MainActor
final class AuthBus: ObservableObject {
    @Published var scuState: AuthState = .unknown
    @Published var username: String?
    @Published var realname: String?
    /// 各子系统 moduleId → ready
    @Published var subsystemReady: [String: Bool] = [:]

    nonisolated init() {}
}
