import Foundation
import BigInt

/// 统一身份认证密码加密（对应 Flutter 版 lib/utils/sm2_crypto.dart）。
/// 输入服务端返回的 base64 公钥，输出 04||C1||C2||C3 的 base64 密文。
enum SM2Crypto {

    static func encryptWithBase64Key(_ plaintext: String, publicKeyBase64: String) throws -> String {
        guard let pubKeyBytes = Data(base64Encoded: publicKeyBase64), !pubKeyBytes.isEmpty else {
            throw SM2Error.invalidPublicKey
        }

        // dart_sm 的 decodePointHex 需要完整的 04||x||y（130 hex）；没有 04 前缀则补上
        var allBytes = Array(pubKeyBytes)
        if allBytes[0] != 0x04 {
            allBytes = [0x04] + allBytes
        }
        let pubKeyHex = allBytes.map { String(format: "%02x", $0) }.joined()

        // 服务端 Python 端按 C1C2C3 解密
        let cipher = try SM2.encrypt(
            Array(plaintext.utf8),
            publicKeyHex: pubKeyHex,
            cipherMode: SM2.c1c2c3
        )

        // dart_sm 输出 C1(无04) + C2 + C3；Python 期望 04 || C1 || C2 || C3（base64）
        return Data([0x04] + cipher).base64EncodedString()
    }
}
