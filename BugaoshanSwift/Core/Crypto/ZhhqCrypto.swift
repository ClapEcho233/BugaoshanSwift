import Foundation
import CommonCrypto

/// zhhq（智慧后勤）前端加密（对应 lib/utils/zhhq_crypto.dart）。
/// AES-128-CBC + PKCS7，密钥为 16 字节 ASCII 常量（前端公开常量，非机密，
/// 可从 zhhq JS 包提取——不轮换、不当凭据、日志无需脱敏）。
enum ZhhqCrypto {

    /// 响应体解密用 key/iv
    static let responseKey = "1974051005060708"
    static let responseIv = "1974051005060708"
    /// Token 请求头加密：key = clientSecret，iv = clientId
    static let clientId = "web201911chengdu"
    static let clientSecret = "bf8ec0449942e7f4"

    // MARK: - AES-128-CBC

    private static func ccAES(
        operation: CCOperation,
        input: [UInt8],
        key: [UInt8],
        iv: [UInt8]
    ) -> [UInt8]? {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else {
            return nil
        }
        let bufferSize = input.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var processed = 0
        let status = input.withUnsafeBufferPointer { inPtr in
            key.withUnsafeBufferPointer { keyPtr in
                iv.withUnsafeBufferPointer { ivPtr in
                    buffer.withUnsafeMutableBufferPointer { bufPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress,
                            kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress,
                            input.count,
                            bufPtr.baseAddress,
                            bufferSize,
                            &processed
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess), processed > 0 else { return nil }
        return Array(buffer[0..<processed])
    }

    static func encrypt(
        _ plaintext: String,
        key: String = responseKey,
        iv: String = responseIv
    ) throws -> String {
        guard let out = ccAES(
            operation: CCOperation(kCCEncrypt),
            input: Array(plaintext.utf8),
            key: Array(key.utf8),
            iv: Array(iv.utf8)
        ) else {
            throw SCUError.service("zhhq AES 加密失败")
        }
        return Data(out).base64EncodedString()
    }

    static func decrypt(
        _ ciphertextBase64: String,
        key: String = responseKey,
        iv: String = responseIv
    ) -> String? {
        guard let data = Data(base64Encoded: ciphertextBase64) else { return nil }
        guard let out = ccAES(
            operation: CCOperation(kCCDecrypt),
            input: [UInt8](data),
            key: Array(key.utf8),
            iv: Array(iv.utf8)
        ) else { return nil }
        return String(bytes: out, encoding: .utf8)
    }

    /// 响应体：AES 解密 + JSON；失败返回 nil
    static func zhhqDecodeResponse(_ body: String) -> [String: Any]? {
        guard let plain = decrypt(body),
              let data = plain.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
