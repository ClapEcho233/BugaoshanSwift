import Foundation

/// 宽松 JSON 取值（对应 lib/utils/json_utils.dart）：
/// 统一各解析处的 null / 类型不符 / 可解析字符串回退，杜绝强转崩溃。
enum SafeJSON {

    static func double(_ value: Any?, fallback: Double = 0) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) ?? fallback }
        return fallback
    }

    static func int(_ value: Any?, fallback: Int = 0) -> Int {
        if let n = value as? NSNumber {
            // NSNumber 带 bool 类型时 intValue 为 0/1，与 Dart num 行为一致
            return n.intValue
        }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) ?? fallback }
        return fallback
    }

    static func string(_ value: Any?, fallback: String = "") -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let v = value { return String(describing: v) }
        return fallback
    }

    static func bool(_ value: Any?, fallback: Bool = false) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        if let s = value as? String {
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: break
            }
        }
        return fallback
    }

    // MARK: - 安全解析

    /// 解析顶层对象；失败抛 exceptionFactory 产物（message 只带长度与 200 字符摘要语义）
    static func parseObject(
        _ body: String,
        api: String,
        exception: (String) -> Error = { SCUError.service("\($0)") }
    ) throws -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw exception("[\(api)] 响应解析失败")
        }
        return object
    }

    static func parseList(
        _ body: String,
        api: String,
        exception: (String) -> Error = { SCUError.service("\($0)") }
    ) throws -> [[String: Any]] {
        guard let data = body.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw exception("[\(api)] 响应解析失败")
        }
        return list
    }

    static func parseObject(_ data: Data, api: String) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SCUError.service("[\(api)] 响应解析失败")
        }
        return object
    }

    /// 响应摘要（≤200 字符），供日志与错误信息
    static func preview(_ body: String) -> String {
        body.count > 200 ? String(body.prefix(200)) + "…(\(body.count)B)" : body
    }
}
