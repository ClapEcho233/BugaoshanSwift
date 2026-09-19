import Foundation

/// 教务周次解析（week_parser.dart + class_week_parser.dart）
enum WeekParser {

    struct WeekRange: Equatable, Sendable {
        var startWeek: Int
        var endWeek: Int
        var weekType: WeekType
    }

    /// 解析教务「周次说明」串：
    /// "1-10周" → (1,10,every)；"1-10,12周" → (1,12,every)；"1-16(单)" → odd；
    /// "第16周" → (16,16,every)；"" → (1,20,every)
    static func parseWeeks(_ zcsm: String) -> WeekRange {
        var weekType: WeekType = .every
        let noZhou = zcsm.replacingOccurrences(of: "周", with: "")
        if noZhou.contains("单") {
            weekType = .odd
        } else if noZhou.contains("双") {
            weekType = .even
        }
        // 只留数字/逗号/连字符
        let digitsOnly = String(noZhou.filter { $0.isNumber || $0 == "," || $0 == "-" })

        var minWeek: Int?
        var maxWeek: Int?
        for part in digitsOnly.split(separator: ",") where !part.isEmpty {
            let segment = part.split(separator: "-", omittingEmptySubsequences: false)
            if segment.count >= 2,
               let first = Int(segment[0]),
               let second = Int(segment[1]) {
                minWeek = [minWeek, min(first, second)].compactMap { $0 }.min()
                maxWeek = [maxWeek, max(first, second)].compactMap { $0 }.max()
            } else if let single = Int(part) {
                minWeek = [minWeek, single].compactMap { $0 }.min()
                maxWeek = [maxWeek, single].compactMap { $0 }.max()
            }
        }
        return WeekRange(
            startWeek: minWeek ?? 1,
            endWeek: maxWeek ?? Course.defaultTotalWeeks,
            weekType: weekType
        )
    }
}

enum ClassWeekParser {

    /// 教务 JSON classWeek 位串：'0'/'1' 序列，第 i 位（0-based）为 '1' 表示第 i+1 周有课
    static func parseSegments(_ classWeek: String) -> [WeekParser.WeekRange] {
        let activeWeeks: [Int] = classWeek.enumerated().compactMap { index, char in
            char == "1" ? index + 1 : nil
        }
        guard !activeWeeks.isEmpty else { return [] }

        // 完整无缺口交替序列（所有相邻差为 2 且 >1 个周）→ 单个 odd/even 区间
        if activeWeeks.count > 1,
           zip(activeWeeks, activeWeeks.dropFirst()).allSatisfy({ $1 - $0 == 2 }) {
            let type: WeekType = activeWeeks[0] % 2 == 1 ? .odd : .even
            return [WeekParser.WeekRange(startWeek: activeWeeks[0], endWeek: activeWeeks[activeWeeks.count - 1], weekType: type)]
        }

        // 否则按连续段（差 1）拆分为多个 every 区间
        var segments: [WeekParser.WeekRange] = []
        var segmentStart = activeWeeks[0]
        var previous = activeWeeks[0]
        for week in activeWeeks.dropFirst() {
            if week == previous + 1 {
                previous = week
                continue
            }
            segments.append(WeekParser.WeekRange(startWeek: segmentStart, endWeek: previous, weekType: .every))
            segmentStart = week
            previous = week
        }
        segments.append(WeekParser.WeekRange(startWeek: segmentStart, endWeek: previous, weekType: .every))
        return segments
    }

    /// 周列表 → 交替段合并展示（教务周次串 → 位串的逆操作，用于展示「1-16周(单)」）
    static func formatWeeks(_ segments: [WeekParser.WeekRange]) -> String {
        segments.map { segment in
            let range = segment.startWeek == segment.endWeek
                ? "\(segment.startWeek)"
                : "\(segment.startWeek)-\(segment.endWeek)"
            switch segment.weekType {
            case .every: return range + "周"
            case .odd: return range + "周(单)"
            case .even: return range + "周(双)"
            }
        }.joined(separator: ",")
    }
}
