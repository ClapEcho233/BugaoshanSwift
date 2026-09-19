import Foundation

/// NSRegularExpression 轻量封装：捕获组以 [String] 返回（组 0 = 整体匹配），
/// 供 HTML 解析场景复用（zhjw 等站点的正则全部按 Dart 原版搬运）。
enum RegexHelper {

    /// 首个匹配的捕获组；未匹配返回 nil
    static func firstMatch(
        _ pattern: String, in text: String, dotAll: Bool = false
    ) -> [String]? {
        guard let regex = make(pattern, dotAll: dotAll) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { i in
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// 全部匹配（每项为捕获组数组）
    static func allMatches(
        _ pattern: String, in text: String, dotAll: Bool = false
    ) -> [[String]] {
        guard let regex = make(pattern, dotAll: dotAll) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            (0..<match.numberOfRanges).compactMap { i in
                guard let r = Range(match.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    static func matches(_ pattern: String, in text: String, dotAll: Bool = false) -> Bool {
        guard let regex = make(pattern, dotAll: dotAll) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func make(_ pattern: String, dotAll: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: pattern,
            options: dotAll ? [.dotMatchesLineSeparators] : []
        )
    }
}
