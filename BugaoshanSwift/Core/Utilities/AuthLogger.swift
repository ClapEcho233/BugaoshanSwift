import Foundation
import Combine
import OSLog

/// 认证日志器（对应 lib/utils/auth_logger.dart）：
/// 1000 条环形缓冲 + 写前脱敏，供开发者页查看与导出。
final class AuthLogger: @unchecked Sendable, ObservableObject {

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let level: String   // D / I / W / E
        let tag: String
        let message: String
    }

    static let shared = AuthLogger()

    private let lock = NSLock()
    private var ring: [Entry] = []
    private let capacity = 1000
    private let logger = Logger(subsystem: "io.github.ClapEcho233.BugaoshanSwift", category: "auth")

    /// 测试可注入轻量行为
    var consoleEnabled = true

    // MARK: - 写入

    func d(_ tag: String, _ message: String) { append(level: "D", tag: tag, message: message) }
    func i(_ tag: String, _ message: String) { append(level: "I", tag: tag, message: message) }
    func w(_ tag: String, _ message: String) { append(level: "W", tag: tag, message: message) }
    func e(_ tag: String, _ message: String) { append(level: "E", tag: tag, message: message) }

    private func append(level: String, tag: String, message raw: String) {
        let message = AuthLogRedactor.apply(raw)
        let entry = Entry(timestamp: Date(), level: level, tag: tag, message: message)
        lock.lock()
        ring.append(entry)
        if ring.count > capacity {
            ring.removeFirst(ring.count - capacity)
        }
        lock.unlock()
        if consoleEnabled {
            switch level {
            case "E": logger.error("\(tag, privacy: .public) \(message, privacy: .public)")
            case "W": logger.warning("\(tag, privacy: .public) \(message, privacy: .public)")
            case "I": logger.info("\(tag, privacy: .public) \(message, privacy: .public)")
            default: logger.debug("\(tag, privacy: .public) \(message, privacy: .public)")
            }
        }
        Task { @MainActor in
            self.objectWillChange.send()
        }
    }

    // MARK: - 读取 / 导出

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return ring
    }

    func clear() {
        lock.lock(); ring.removeAll(); lock.unlock()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let exportFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 行格式与 Dart 版一致：`HH:mm:ss.SSS LEVEL [tag] message`
    func exportText() -> String {
        let f = Self.timeFormatter
        return entries.map { "\(f.string(from: $0.timestamp)) \($0.level.padding(toLength: 5, withPad: " ", startingAt: 0)) [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")
    }
}

/// 写前脱敏（对应 AuthLogRedactor.apply）
enum AuthLogRedactor {
    private static let rules: [(NSRegularExpression, String)] = {
        let candidates: [(String, String)] = [
            // "access_token":"..." / "password":"..." → <redacted>
            ("(\"(?:access_token|password)\"\\s*:\\s*)\"[^\"]*\"", "$1\"<redacted>\""),
            // Bearer xxx → Bearer <redacted>
            ("Bearer\\s+[A-Za-z0-9._\\-]+", "Bearer <redacted>"),
            // ?code=xxx / &access_token=xxx
            ("([?&](?:code|access_token)=)([^&\\s\"]+)", "$1<redacted>"),
            // username=xxx / userId=xxx / studentId=xxx …
            ("\\b(user(?:name|id)?|student(?:id|number)?|number)\\s*=\\s*[^\\s,;]+", "<redacted>"),
            // "username":"xxx" 等 JSON 字段
            ("(\"(?:username|userId|studentId|studentNumber|number)\"\\s*:\\s*)\"[^\"]*\"", "$1\"<redacted>\""),
        ]
        // 编译失败时跳过该条（不崩溃；脱敏规则在测试中有覆盖）
        return candidates.compactMap { pattern, template -> (NSRegularExpression, String)? in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, template)
        }
    }()

    static func apply(_ text: String) -> String {
        var result = text
        for (regex, template) in rules {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: template
            )
        }
        return result
    }
}
