import Foundation

/// 电费余额趋势纯函数工具。
/// 对应 Flutter 版 BalanceTrendCalculator 的绘图规则：
/// 按北京日历日（UTC+8）聚合，每日取最后一条采样作为日代表点绘图，
/// 长期使用时图表最多 365 点（DB 保留一年），保证可读性。
enum BalanceTrendMath {

    /// 按北京日历日聚合：同一日取最后一条作为日代表点（按时间升序返回）。
    /// 未排序输入亦正确（以时间戳比较，不依赖输入顺序）。
    static func dailyPoints(from records: [BalanceRecord]) -> [BalanceRecord] {
        var byDay: [Date: BalanceRecord] = [:]
        for record in records {
            let day = BeijingTime.dayBucket(of: record.date)
            if let existing = byDay[day], existing.timestamp >= record.timestamp {
                continue
            }
            byDay[day] = record
        }
        return byDay.values.sorted { $0.timestamp < $1.timestamp }
    }

    /// 横轴最小可视跨度：数据跨度极短（同日连续刷新）时垫宽坐标域，
    /// 避免秒级缩放导致刻度标签重叠。
    static let minimumVisibleSpan: TimeInterval = 10 * 60

    /// 坐标域：数据范围两侧各留边距（两侧合计 2%，且总跨度不小于最小可视跨度），
    /// 保证最小缩放与呼吸空间。
    static func domain(from first: Date, to last: Date) -> ClosedRange<Date> {
        let span = last.timeIntervalSince(first)
        let pad = max(minimumVisibleSpan - span, span * 0.02) / 2
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    /// 横轴刻度：坐标域内均匀分布的内部时间点，
    /// 首尾各留一个步长的边距，标签居中后不会超出图表边界。
    static func axisDates(from first: Date, to last: Date, count: Int = 3) -> [Date] {
        guard last > first, count > 0 else { return [] }
        let stride = last.timeIntervalSince(first) / Double(count + 1)
        return (1...count).map { first.addingTimeInterval(Double($0) * stride) }
    }

    /// 横轴标签格式：数据跨度不足一天显示 HH:mm（24 小时制），否则 MM-dd。
    static func axisPattern(span: TimeInterval) -> String {
        span >= 24 * 3600 ? "MM-dd" : "HH:mm"
    }
}
