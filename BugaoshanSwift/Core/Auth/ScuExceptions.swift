import Foundation

/// 异常体系（对应 lib/services/auth/scu_exceptions.dart 的 sealed 层级）。
/// `localizedDescription` 供 UI 直接展示。
enum SCUError: Error, LocalizedError, Equatable {
    /// 认证丢失。L1 包装器精确重放一次；随后冒泡到 Provider → UI「前往登录」。
    case unauthenticated(String = "未登录或登录已过期")
    /// 网络/解析/非 200/业务错误。不做认证自动重试。
    case service(String, statusCode: Int? = nil)
    /// 服务端限流（zhjw「请勿频繁刷新」）。不做自动重试。
    case rateLimited
    /// 登录页错误（验证码/凭据）。仅 UI 自动登录重试，且仅 invalid_captcha，最多 5 次。
    case login(String)
    /// 忘记密码业务错误（400 验证码错误、439 验证码过期等）。
    case forgotPassword(String, businessCode: Int? = nil)

    var errorDescription: String? {
        switch self {
        case .unauthenticated(let message), .service(let message, _),
             .login(let message), .forgotPassword(let message, _):
            return message
        case .rateLimited:
            return "rateLimited"
        }
    }

    var statusCode: Int? {
        switch self {
        case .service(_, let code): return code
        case .forgotPassword(_, let code): return code
        default: return nil
        }
    }
}

extension SCUError {
    /// 是否为认证类错误（决定 retryOnUnauthenticated 是否触发重放）
    var isUnauthenticated: Bool {
        if case .unauthenticated = self { return true }
        return false
    }
}

/// CCYL 独立异常（不属于 SCUError 层级；业务码 401 → token 过期 → CCYL 包装器重试一次）
enum CcylError: Error, LocalizedError {
    case general(String)
    case authExpired

    var errorDescription: String? {
        switch self {
        case .general(let message): return message
        case .authExpired: return "青春川大登录已过期"
        }
    }
}

/// 电费查询独立异常
enum BalanceQueryError: Error, LocalizedError {
    case general(String)
    case auth

    var errorDescription: String? {
        switch self {
        case .general(let message): return message
        case .auth: return "电费查询登录已失效"
        }
    }
}
