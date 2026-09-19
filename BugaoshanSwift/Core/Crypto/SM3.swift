import Foundation

/// 国密 SM3 杂凑算法（GB/T 32905-2016），自 dart_sm 0.1.4 逐行移植。
/// 仅实现哈希本体；KDF 流在 SM2 中按 dart_sm 的调用形态内联实现。
enum SM3 {

    static func hash(_ data: [UInt8]) -> [UInt8] {
        let inputLength = data.count * 8
        var paddingLength = inputLength % 512
        paddingLength = paddingLength >= 448
            ? 512 - (paddingLength % 448) - 1
            : 448 - paddingLength - 1

        let size = (inputLength + paddingLength + 1 + 64) / 8
        var padded = [UInt8](repeating: 0, count: size)
        padded.replaceSubrange(0..<data.count, with: data)
        padded[data.count] = 0x80

        // 大端 64 位消息长度
        var len = UInt64(inputLength)
        for i in 0..<8 {
            padded[size - 1 - i] = UInt8(truncatingIfNeeded: len)
            len >>= 8
        }

        var v: [UInt32] = iv
        let blockCount = padded.count / 64
        var w = [UInt32](repeating: 0, count: 68)
        var m = [UInt32](repeating: 0, count: 64)

        for block in 0..<blockCount {
            let start = block * 16
            for j in 0..<16 {
                let o = (start + j) * 4
                w[j] = (UInt32(padded[o]) << 24) | (UInt32(padded[o + 1]) << 16)
                    | (UInt32(padded[o + 2]) << 8) | UInt32(padded[o + 3])
            }
            for j in 16..<68 {
                w[j] = p1((w[j - 16] ^ w[j - 9]) ^ leftShift(w[j - 3], 15)) ^ leftShift(w[j - 13], 7) ^ w[j - 6]
            }
            for j in 0..<64 {
                m[j] = w[j] ^ w[j + 4]
            }

            var a = v[0], b = v[1], c = v[2], d = v[3]
            var e = v[4], f = v[5], g = v[6], h = v[7]

            for j in 0..<64 {
                let t = j <= 15 ? t1 : t2
                let ss1 = leftShift(leftShift(a, 12) &+ e &+ leftShift(t, j), 7)
                let ss2 = ss1 ^ leftShift(a, 12)
                let boolFn = j <= 15 ? ((a ^ b) ^ c) : ((a & b) | (a & c) | (b & c))
                let tt1 = boolFn &+ d &+ ss2 &+ m[j]
                let boolE = j <= 15 ? ((e ^ f) ^ g) : ((e & f) | ((~e) & g))
                let tt2 = boolE &+ h &+ ss1 &+ w[j]

                d = c
                c = leftShift(b, 9)
                b = a
                a = tt1
                h = g
                g = leftShift(f, 19)
                f = e
                e = p0(tt2)
            }

            v[0] ^= a; v[1] ^= b; v[2] ^= c; v[3] ^= d
            v[4] ^= e; v[5] ^= f; v[6] ^= g; v[7] ^= h
        }

        var result = [UInt8](repeating: 0, count: 32)
        for i in 0..<8 {
            result[i * 4] = UInt8(truncatingIfNeeded: v[i] >> 24)
            result[i * 4 + 1] = UInt8(truncatingIfNeeded: v[i] >> 16)
            result[i * 4 + 2] = UInt8(truncatingIfNeeded: v[i] >> 8)
            result[i * 4 + 3] = UInt8(truncatingIfNeeded: v[i])
        }
        return result
    }

    static func hashHex(_ data: [UInt8]) -> String {
        Data(hash(data)).map { String(format: "%02x", $0) }.joined()
    }

    static func hashHex(_ string: String) -> String {
        hashHex(Array(string.utf8))
    }

    // MARK: - 内部

    private static let iv: [UInt32] = [
        0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
        0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
    ]
    private static let t1: UInt32 = 0x79cc4519
    private static let t2: UInt32 = 0x7a879d8a

    /// dart_sm 的 leftShift：32 位循环左移（n 先 &31；s=0 时即原值）
    private static func leftShift(_ x: UInt32, _ n: Int) -> UInt32 {
        let s = n & 31
        if s == 0 { return x }
        return (x << UInt32(s)) | (x >> UInt32(32 - s))
    }

    private static func p0(_ x: UInt32) -> UInt32 {
        x ^ leftShift(x, 9) ^ leftShift(x, 17)
    }

    private static func p1(_ x: UInt32) -> UInt32 {
        x ^ leftShift(x, 15) ^ leftShift(x, 23)
    }
}
