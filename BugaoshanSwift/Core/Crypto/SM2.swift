import Foundation
import BigInt
import Security

/// 国密 SM2 椭圆曲线公钥加密（GB/T 32918.4），自 dart_sm 0.1.4 移植。
/// 仅实现加密/解密（登录密码加密场景不需要签名验签）。
/// 曲线：sm2p256v1；密文排版支持 C1C2C3 / C1C3C2，与 dart_sm 输出逐字节一致。
enum SM2 {

    static let c1c2c3 = 0
    static let c1c3c2 = 1

    // MARK: - sm2p256v1 曲线参数

    static let p = BigUInt("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF", radix: 16)!
    static let a = BigUInt("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC", radix: 16)!
    static let b = BigUInt("28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93", radix: 16)!
    static let n = BigUInt("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123", radix: 16)!
    private static let gx = BigUInt("32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7", radix: 16)!
    private static let gy = BigUInt("BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0", radix: 16)!
    static let G = ECPoint(x: gx, y: gy, z: 1)

    // MARK: - 加密

    /// 加密。返回字节布局：C1(64B, 无04前缀) + C2 + C3(32B)（c1c2c3）或 C1 + C3 + C2（c1c3c2），
    /// 与 dart_sm 的 hex 输出一致（dart_sm 输出即 C1 的 128 hex + …，同样无 04 前缀）。
    /// - Parameters:
    ///   - msg: 明文字节
    ///   - publicKeyHex: 130 位十六进制 "04 || x || y"
    ///   - cipherMode: c1c2c3 或 c1c3c2
    ///   - k: 临时私钥（测试注入用；生产传 nil 随机生成）
    static func encrypt(
        _ msg: [UInt8],
        publicKeyHex: String,
        cipherMode: Int = c1c3c2,
        k: BigUInt? = nil
    ) throws -> [UInt8] {
        guard let publicKeyPoint = try decodePoint(publicKeyHex) else {
            throw SM2Error.invalidPublicKey
        }

        let privateKey: BigUInt
        if let k {
            privateKey = k
        } else {
            privateKey = try randomPrivateKey()
        }

        // C1 = k*G
        let c1Point = G.multiply(privateKey)
        let c1 = try pointToXYBytes(c1Point)

        // 共享点 p = k * Pb
        let shared = publicKeyPoint.multiply(privateKey)
        let x2 = try leftPadBytes(try affineX(shared), 32)
        let y2 = try leftPadBytes(try affineY(shared), 32)

        // C3 = SM3(x2 || M || y2)
        let c3 = SM3.hash(x2 + msg + y2)

        // C2 = M XOR KDF(x2||y2, len)
        let c2 = xorKDF(msg, z: x2 + y2)

        return cipherMode == c1c2c3 ? c1 + c2 + c3 : c1 + c3 + c2
    }

    /// 解密（C1 无 04 前缀、64 字节）。C3 校验失败返回 nil（dart_sm 返回空串）。
    static func decrypt(_ cipher: [UInt8], privateKeyHex: String, cipherMode: Int = c1c3c2) throws -> String? {
        let d = BigUInt(privateKeyHex, radix: 16) ?? 0
        guard cipher.count >= 96 else { return nil }

        let c1Bytes = Array(cipher[0..<64])
        let c3: [UInt8]
        let c2: [UInt8]
        if cipherMode == c1c2c3 {
            c3 = Array(cipher[(cipher.count - 32)...])
            c2 = Array(cipher[64..<(cipher.count - 32)])
        } else {
            c3 = Array(cipher[64..<96])
            c2 = Array(cipher[96...])
        }

        let c1Hex = ([0x04] + c1Bytes).map { String(format: "%02x", $0) }.joined()
        guard let c1Point = try decodePoint(c1Hex) else { return nil }

        let shared = c1Point.multiply(d)
        let x2 = try leftPadBytes(try affineX(shared), 32)
        let y2 = try leftPadBytes(try affineY(shared), 32)

        let msg = xorKDF(c2, z: x2 + y2)
        let checkC3 = SM3.hash(x2 + msg + y2)
        guard checkC3 == c3 else { return nil }
        return String(bytes: msg, encoding: .utf8)
    }

    /// 生成 [1, n-1] 内随机私钥（dart_sm：随机位串后 % (n-1) + 1）
    static func randomPrivateKey() throws -> BigUInt {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SM2Error.randomFailed }
        let r = BigUInt(Data(bytes))
        return r % (n - 1) + 1
    }

    /// 由私钥推导公钥（130 hex，04 前缀）
    static func publicKey(fromPrivateKey privateKeyHex: String) -> String {
        let d = BigUInt(privateKeyHex, radix: 16) ?? 0
        let pub = G.multiply(d)
        let x = leftPadHex(try! affineX(pub), 64)
        let y = leftPadHex(try! affineY(pub), 64)
        return "04" + x + y
    }

    /// 校验公钥点是否在曲线上
    static func verifyPublicKey(_ publicKeyHex: String) -> Bool {
        guard let point = try? decodePoint(publicKeyHex), let x = point.x, let y = point.y else {
            return false
        }
        let lhs = (y * y) % p
        let rhs = (x * x % p * x + a * x + b) % p
        return lhs == rhs
    }

    // MARK: - 点编解码

    /// 解析 "04 || x(64hex) || y(64hex)"（dart_sm decodePointHex 的 case 4/6/7 分支）
    static func decodePoint(_ hex: String) throws -> ECPoint? {
        let s = hex.hasPrefix("0x") || hex.hasPrefix("0X") ? String(hex.dropFirst(2)) : hex
        guard s.count >= 4, let prefix = UInt8(s.prefix(2), radix: 16) else { return nil }
        guard prefix == 4 || prefix == 6 || prefix == 7 else { return nil }
        let body = s.dropFirst(2)
        guard body.count % 2 == 0, body.count >= 128 else { return nil }
        let len = body.count / 2
        guard let x = BigUInt(body.prefix(len), radix: 16),
              let y = BigUInt(body.suffix(len), radix: 16) else { return nil }
        return ECPoint(x: x, y: y, z: 1)
    }

    private static func pointToXYBytes(_ point: ECPoint) throws -> [UInt8] {
        try leftPadBytes(try affineX(point), 32) + leftPadBytes(try affineY(point), 32)
    }

    // MARK: - KDF（dart_sm 内联形态：t_i = SM3(z || ct_be32)，ct 从 1 起）

    private static func xorKDF(_ msg: [UInt8], z: [UInt8]) -> [UInt8] {
        var out = msg
        var ct: UInt32 = 1
        var offset = 0
        var t: [UInt8] = []
        func nextT() {
            var input = z
            withUnsafeBytes(of: ct.bigEndian) { input.append(contentsOf: $0) }
            t = SM3.hash(input)
            ct += 1
            offset = 0
        }
        nextT()
        for i in 0..<out.count {
            if offset == t.count { nextT() }
            out[i] ^= t[offset]
            offset += 1
        }
        return out
    }

    // MARK: - 工具

    static func leftPadBytes(_ value: BigUInt, _ length: Int) -> [UInt8] {
        let serialized = value.serialize()  // 大端、无前导零
        precondition(serialized.count <= length, "值超出目标长度")
        return [UInt8](repeating: 0, count: length - serialized.count) + Array(serialized)
    }

    static func leftPadHex(_ value: BigUInt, _ length: Int) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: length - hex.count) + hex
    }

    static func affineX(_ point: ECPoint) throws -> BigUInt {
        guard let x = point.x, let inv = modInverse(BigInt(point.z), BigInt(p)) else {
            throw SM2Error.infinityPoint
        }
        return x * BigUInt(inv) % p
    }

    static func affineY(_ point: ECPoint) throws -> BigUInt {
        guard let y = point.y, let inv = modInverse(BigInt(point.z), BigInt(p)) else {
            throw SM2Error.infinityPoint
        }
        return y * BigUInt(inv) % p
    }
}

enum SM2Error: Error {
    case invalidPublicKey
    case randomFailed
    case infinityPoint
}

// MARK: - Jacobian 坐标点（dart_sm ECPointFp 移植；单曲线，参数走 SM2 常量）

struct ECPoint {
    var x: BigUInt?
    var y: BigUInt?
    var z: BigUInt

    init(x: BigUInt?, y: BigUInt?, z: BigUInt = 1) {
        self.x = x
        self.y = y
        self.z = z
    }

    static var infinity: ECPoint { ECPoint(x: nil, y: nil) }

    var isInfinity: Bool { x == nil && y == nil }

    func negate() -> ECPoint {
        guard let y = y else { return self }
        return ECPoint(x: x, y: (SM2.p - y) % SM2.p, z: z)
    }

    /// dart_sm ECPointFp.multiply 的窗口法（k3=3k 逐位比较，i 从 bitLength(k3)-2 到 1）
    func multiply(_ k: BigUInt) -> ECPoint {
        if isInfinity { return self }
        if k == 0 { return .infinity }

        let k3 = k * 3
        let neg = negate()
        var q = self
        for i in stride(from: bitLength(k3) - 2, through: 1, by: -1) {
            q = q.twice()
            let k3Bit = (k3 >> i) & 1
            let kBit = (k >> i) & 1
            if k3Bit != kBit {
                q = q.add(k3Bit == 1 ? self : neg)
            }
        }
        return q
    }

    func add(_ other: ECPoint) -> ECPoint {
        if isInfinity { return other }
        if other.isInfinity { return self }
        let q = BigInt(SM2.p)
        let x1 = BigInt(x!), y1 = BigInt(y!), z1 = BigInt(z)
        let x2 = BigInt(other.x!), y2 = BigInt(other.y!), z2 = BigInt(other.z)

        let w1 = (x1 * z2) % q
        let w2 = (x2 * z1) % q
        let w3 = (w1 - w2) %% q
        let w4 = (y1 * z2) % q
        let w5 = (y2 * z1) % q
        let w6 = (w4 - w5) %% q

        if w3 == 0 {
            if w6 == 0 { return twice() }
            return .infinity
        }

        let w7 = (w1 + w2) % q
        let w8 = (z1 * z2) % q
        let w9 = (w3 * w3) % q
        let w10 = (w3 * w9) % q
        let w6sq = (w6 * w6) % q
        let w11 = (w8 * w6sq - w7 * w9) %% q

        let x3 = (w3 * w11) % q
        let w9w1 = (w9 * w1) %% q
        let y3 = (w6 * (w9w1 - w11) - w4 * w10) %% q
        let z3 = (w10 * w8) % q

        return ECPoint(x: BigUInt(x3), y: BigUInt(y3), z: BigUInt(z3))
    }

    func twice() -> ECPoint {
        if isInfinity { return self }
        let q = BigInt(SM2.p)
        let x1 = BigInt(x!), y1 = BigInt(y!), z1 = BigInt(z)

        let x1sq = x1 * x1
        let z1sq = z1 * z1
        let w1 = (x1sq * 3 + BigInt(SM2.a) * z1sq) %% q
        let w2 = (y1 * 2 * z1) % q
        let w3 = (y1 * y1) % q
        let w4 = (w3 * x1 * z1) % q
        let w5 = (w2 * w2) % q
        let w6 = (w1 * w1 - w4 * 8) %% q

        let x3 = (w2 * w6) % q
        let inner = (w4 * 4 - w6) %% q
        let y3 = (w1 * inner - w5 * 2 * w3) %% q
        let z3 = (w2 * w5) % q

        return ECPoint(x: BigUInt(x3), y: BigUInt(y3), z: BigUInt(z3))
    }
}

infix operator %% : MultiplicationPrecedence

/// 非负取模（Dart BigInt % 语义）
func %% (_ value: BigInt, _ modulus: BigInt) -> BigInt {
    let r = value % modulus
    return r.sign == .minus ? r + modulus : r
}

/// 二进制有效位数
func bitLength(_ value: BigUInt) -> Int {
    guard value > 0 else { return 0 }
    var total = 0
    var v = value
    var topByte: UInt8 = 0
    while v > 0 {
        topByte = UInt8(truncatingIfNeeded: v & 0xFF)
        v >>= 8
        total += 8
    }
    var extra = 0
    var byte = topByte
    while byte > 0 {
        byte >>= 1
        extra += 1
    }
    return total - 8 + extra
}

/// 扩展欧几里得模逆（结果非负；不可逆返回 nil）
func modInverse(_ a: BigInt, _ m: BigInt) -> BigInt? {
    var (oldR, r) = (a %% m, m)
    var (oldS, s) = (BigInt(1), BigInt(0))
    while r != 0 {
        let q = oldR / r
        (oldR, r) = (r, oldR - q * r)
        (oldS, s) = (s, oldS - q * s)
    }
    guard oldR == 1 else { return nil }
    return (oldS %% m)
}
