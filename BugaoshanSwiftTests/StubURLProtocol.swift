import Foundation
import XCTest
@testable import BugaoshanSwift

/// URLProtocol 测试桩：按 URL 前缀/路径脚本化响应，记录请求供断言。
/// 用法：`StubURLProtocol.handler = { request in ... }`，
/// 客户端使用 `URLSessionConfiguration.ephemeral` + `protocolClasses = [StubURLProtocol.self]`。
final class StubURLProtocol: URLProtocol {

    /// 返回 (状态码, 头, body)；nil → 未匹配（连接错误）
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data)?)?
    nonisolated(unsafe) static var recordedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        handler = nil
        recordedRequests = []
        lock.unlock()
    }

    static func makeConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let result = Self.handler?(request)
        Self.lock.unlock()

        guard let (status, headers, data) = result else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
