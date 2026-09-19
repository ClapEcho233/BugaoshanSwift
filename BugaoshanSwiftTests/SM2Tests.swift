import XCTest
import BigInt
@testable import BugaoshanSwift

/// SM3 / SM2 移植正确性测试。
/// - SM3 用 GB/T 32905 标准向量
/// - 曲线运算用 GB/T 32918 附录标准密钥对
/// - 加解密用固定 k 做确定性回环（覆盖 KDF 与 C3 一致性）
final class SM2Tests: XCTestCase {

    // MARK: - SM3 标准向量

    func testSM3StandardVectorAbc() {
        XCTAssertEqual(
            SM3.hashHex("abc"),
            "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0"
        )
    }

    func testSM3StandardVectorAbcd64() {
        // GB/T 32905-2016 例 2："abcd" × 16
        XCTAssertEqual(
            SM3.hashHex(String(repeating: "abcd", count: 16)),
            "debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732"
        )
    }

    func testSM3EmptyInput() {
        XCTAssertEqual(SM3.hash([]).count, 32)
    }

    // MARK: - 曲线

    func testBasePointOnCurve() {
        XCTAssertTrue(SM2.verifyPublicKey(
            "04"
                + "32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7"
                + "BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0"
        ))
    }

    /// GB/T 32918 附录 A.2 标准密钥对：私钥 → 公钥推导
    func testStandardKeyPairDerivation() {
        let privateKey = "3945208F7B2144B13F36E38AC6D39F95889393692860B51A42FB81EF4DF7C5B8"
        let expectedPublicKey = "04"
            + "09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020"
            + "CCEA490CE26775A52DC6EA718CC1AA600AED05FBF35E084A6632F6072DA9AD13"
        XCTAssertEqual(
            SM2.publicKey(fromPrivateKey: privateKey).uppercased(),
            expectedPublicKey
        )
    }

    // MARK: - 大数工具

    func testBitLength() {
        XCTAssertEqual(bitLength(BigUInt(0)), 0)
        XCTAssertEqual(bitLength(BigUInt(1)), 1)
        XCTAssertEqual(bitLength(BigUInt(2)), 2)
        XCTAssertEqual(bitLength(BigUInt(3)), 2)
        XCTAssertEqual(bitLength(BigUInt(255)), 8)
        XCTAssertEqual(bitLength(BigUInt(256)), 9)
        XCTAssertEqual(bitLength(BigUInt("FFFFFFFFFFFFFFFF", radix: 16)!), 64)
    }

    func testModInverse() {
        XCTAssertEqual(modInverse(BigInt(3), BigInt(11))!, BigInt(4))
        // z=1 的逆元（affine 坐标转换常见路径）
        XCTAssertEqual(modInverse(BigInt(1), BigInt(SM2.p))!, BigInt(1))
    }

    // MARK: - 加解密回环

    private static let testPrivateKey = "3945208F7B2144B13F36E38AC6D39F95889393692860B51A42FB81EF4DF7C5B8"
    private static let testPublicKey =
        "04"
        + "09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020"
        + "CCEA490CE26775A52DC6EA718CC1AA600AED05FBF35E084A6632F6072DA9AD13"
    private static let fixedK = BigUInt("59276E27D506861F1667F61776DBE6F4D2A1E1EAC5A0E7FE20C2C2B67F1B0A5F", radix: 16)!

    func testEncryptDecryptRoundTripC1C2C3() throws {
        let plaintext = "Hello不高山123!@#"
        let cipher = try SM2.encrypt(
            Array(plaintext.utf8),
            publicKeyHex: Self.testPublicKey,
            cipherMode: SM2.c1c2c3,
            k: Self.fixedK
        )
        // C1(64) + C2(len) + C3(32)
        XCTAssertEqual(cipher.count, 64 + plaintext.utf8.count + 32)
        let decrypted = try SM2.decrypt(cipher, privateKeyHex: Self.testPrivateKey, cipherMode: SM2.c1c2c3)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptRoundTripC1C3C2() throws {
        let plaintext = "P@ssw0rd-测试"
        let cipher = try SM2.encrypt(
            Array(plaintext.utf8),
            publicKeyHex: Self.testPublicKey,
            cipherMode: SM2.c1c3c2,
            k: Self.fixedK
        )
        let decrypted = try SM2.decrypt(cipher, privateKeyHex: Self.testPrivateKey, cipherMode: SM2.c1c3c2)
        XCTAssertEqual(decrypted, plaintext)
    }

    /// 明文超过一个 KDF 块（32 字节），验证 ct 递增路径
    func testEncryptDecryptLongPlaintext() throws {
        let plaintext = String(repeating: "a1b2c3d4e5", count: 8)  // 40 字节
        let cipher = try SM2.encrypt(
            Array(plaintext.utf8),
            publicKeyHex: Self.testPublicKey,
            cipherMode: SM2.c1c2c3,
            k: Self.fixedK
        )
        let decrypted = try SM2.decrypt(cipher, privateKeyHex: Self.testPrivateKey, cipherMode: SM2.c1c2c3)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptRejectsTamperedCipher() throws {
        let cipher = try SM2.encrypt(
            Array("secret".utf8),
            publicKeyHex: Self.testPublicKey,
            cipherMode: SM2.c1c2c3,
            k: Self.fixedK
        )
        var tampered = cipher
        tampered[tampered.count - 1] ^= 0x01  // 破坏 C3
        let result = try SM2.decrypt(tampered, privateKeyHex: Self.testPrivateKey, cipherMode: SM2.c1c2c3)
        XCTAssertNil(result)
    }

    func testRandomPrivateKeyRange() throws {
        for _ in 0..<20 {
            let k = try SM2.randomPrivateKey()
            XCTAssertGreaterThan(k, BigUInt(0))
            XCTAssertLessThan(k, SM2.n)
        }
    }

    // MARK: - 应用层包装（登录密码加密）

    func testWrapperOutputFormat() throws {
        // 公钥 base64（无 04 前缀形态，服务端可能直接下发裸坐标）
        let pubKeyBytes: [UInt8] = [0x04]
            + Array(BigUInt("09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020", radix: 16)!.serialize())
        // 左补齐到 32 字节后拼 y
        let yBytes = SM2.leftPadBytes(
            BigUInt("CCEA490CE26775A52DC6EA718CC1AA600AED05FBF35E084A6632F6072DA9AD13", radix: 16)!, 32)
        let xBytes = SM2.leftPadBytes(
            BigUInt("09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020", radix: 16)!, 32)
        let fullKey = Data([0x04] + xBytes + yBytes)

        let cipherBase64 = try SM2Crypto.encryptWithBase64Key("myPassword123", publicKeyBase64: fullKey.base64EncodedString())
        let cipherBytes = Array(Data(base64Encoded: cipherBase64)!)

        // 04 || C1(64) || C2(12) || C3(32)
        XCTAssertEqual(cipherBytes.count, 1 + 64 + "myPassword123".utf8.count + 32)
        XCTAssertEqual(cipherBytes[0], 0x04)

        // 去掉 04 前缀后可解回
        let stripped = Array(cipherBytes[1...])
        let decrypted = try SM2.decrypt(stripped, privateKeyHex: Self.testPrivateKey, cipherMode: SM2.c1c2c3)
        XCTAssertEqual(decrypted, "myPassword123")
    }

    /// 公钥不带 04 前缀（64 字节裸 x||y）时自动补前缀
    func testWrapperAddsMissingPrefix() throws {
        let xBytes = SM2.leftPadBytes(
            BigUInt("09F9DF311E5421A150DD7D161E4BC5C672179FAD1833FC076BB08FF356F35020", radix: 16)!, 32)
        let yBytes = SM2.leftPadBytes(
            BigUInt("CCEA490CE26775A52DC6EA718CC1AA600AED05FBF35E084A6632F6072DA9AD13", radix: 16)!, 32)
        let bareKey = Data(xBytes + yBytes)  // 64 字节，无前缀

        XCTAssertThrowsError(try SM2Crypto.encryptWithBase64Key("x", publicKeyBase64: Data([0x05]).base64EncodedString()))
        // 无前缀的合法裸公钥也能工作
        _ = try SM2Crypto.encryptWithBase64Key("x", publicKeyBase64: bareKey.base64EncodedString())
    }
}
