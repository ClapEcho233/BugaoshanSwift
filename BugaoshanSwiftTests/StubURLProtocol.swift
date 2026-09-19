import Foundation
import XCTest
@testable import BugaoshanSwift

/// 记录的请求（httpBody 已从 stream 物化）
struct RecordedRequest {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data

    var bodyString: String { String(data: body, encoding: .utf8) ?? "" }
}

/// URLProtocol 测试桩：按 URL 前缀/路径脚本化响应，记录请求供断言。
/// 用法：`StubURLProtocol.handler = { request in ... }`，
/// 客户端使用 `URLSessionConfiguration.ephemeral` + `protocolClasses = [StubURLProtocol.self]`。
final class StubURLProtocol: URLProtocol {

    /// 返回 (状态码, 头, body)；nil → 未匹配（连接错误）
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data)?)?
    nonisolated(unsafe) static var recordedRequests: [RecordedRequest] = []
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

    /// httpBody 可能被移入 httpBodyStream，这里统一物化
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(
            RecordedRequest(
                url: request.url!,
                method: request.httpMethod ?? "GET",
                headers: (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value },
                body: Self.bodyData(of: request)
            )
        )
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

