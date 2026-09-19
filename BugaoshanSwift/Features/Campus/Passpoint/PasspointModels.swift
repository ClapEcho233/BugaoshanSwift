import Foundation

// MARK: - 无感认证模型（对应 models/passpoint.dart）

/// 无感设备列表项（query-user-mab-info 返回 d.data[] 元素）。
///
/// 注意：服务端 `macExpireTime` 是到期日期字符串（yyyy-MM-dd）而非天数；
/// 无法解析（空串/0，对应「最长有效期 6 年」）时为 nil。
struct PasspointDevice: Identifiable, Equatable, Sendable {
    var id: String { userMac }
    var userMac: String
    var macExpireTime: Date?
    var defaultServiceName: String
    var isOnline: Bool

    static func fromJson(_ json: [String: Any]) -> PasspointDevice {
        PasspointDevice(
            userMac: SafeJSON.string(json["userMac"]),
            macExpireTime: parseExpireTime(SafeJSON.string(json["macExpireTime"])),
            defaultServiceName: SafeJSON.string(json["defaultServiceName"]),
            isOnline: json["isOnline"] as? Bool == true
                || SafeJSON.string(json["isOnline"]) == "1"
                || SafeJSON.string(json["isOnline"]) == "true"
        )
    }

    /// 解析到期日期（yyyy-MM-dd，宽松兼容带时间的 ISO 串）；空/非法返回 nil。
    static func parseExpireTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

/// 校园网账户信息（query-user 返回 d.queryUserResult.data）。
struct PasspointUserInfo: Equatable, Sendable {
    var userId: String
    var userName: String
    var userGroupName: String
    var accountState: Int
    var mobile: String
    var email: String

    /// 账户是否在线（1=在线）
    var isOnline: Bool { accountState == 1 }

    static func fromJson(_ json: [String: Any]) -> PasspointUserInfo {
        PasspointUserInfo(
            userId: SafeJSON.string(json["userId"]),
            userName: SafeJSON.string(json["userName"]),
            userGroupName: SafeJSON.string(json["userGroupName"]),
            accountState: SafeJSON.int(json["accountState"]),
            mobile: SafeJSON.string(json["mobile"]),
            email: SafeJSON.string(json["email"])
        )
    }
}

/// 无感认证出口（defaultServiceName 可选项；前端固定四项）。
struct PasspointExit: Equatable, Identifiable, Sendable {
    var id: String { value }
    var label: String
    var value: String

    static let all: [PasspointExit] = [
        PasspointExit(label: "校园网", value: ""),
        PasspointExit(label: "中国电信", value: "中国电信"),
        PasspointExit(label: "中国移动", value: "中国移动"),
        PasspointExit(label: "中国联通", value: "中国联通"),
    ]

    /// 显示用：按 value 反查 label
    static func label(for value: String) -> String? {
        all.first(where: { $0.value == value })?.label
    }
}
