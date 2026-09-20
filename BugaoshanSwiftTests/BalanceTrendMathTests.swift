import XCTest
@testable import BugaoshanSwift

/// 电费趋势图纯函数测试（模拟数据：同日密集采样、充值跳变、一年期长期使用）
final class BalanceTrendMathTests: XCTestCase {

    private func record(
        _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0,
        balance: Double, price: Double = 0.55
    ) -> BalanceRecord {
        BalanceRecord(
            id: nil,
            roomKey: "test_room",
            balanceType: 1,
            timestamp: Int64(BeijingTime.date(year: y, month: mo, day: d, hour: h, minute: mi).timeIntervalSince1970 * 1000),
            balance: balance,
            price: price
        )
    }

    // MARK: - 日聚合（对应 Flutter BalanceTrendCalculator.dailyPoints）

    func testDailyPointsTakesLastRecordPerDay() {
        let records = [
            record(2026, 9, 1, 8, 0, balance: 50),
            record(2026, 9, 1, 22, 0, balance: 40),
            record(2026, 9, 2, 9, 0, balance: 100),   // 充值
            record(2026, 9, 2, 23, 0, balance: 90),
            record(2026, 9, 3, 7, 0, balance: 80),
        ]
        let points = BalanceTrendMath.dailyPoints(from: records)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points.map(\.balance), [40, 90, 80])
        // 每日取的是当天最后一条（时间戳最大）
        XCTAssertEqual(points[0].timestamp, records[1].timestamp)
        XCTAssertEqual(points[1].timestamp, records[3].timestamp)
    }

    func testDailyPointsSingleDayCollapsesToOnePoint() {
        // 用户截图场景：7 分钟内刷新 13 次全部同值 → 图表只画 1 个点
        let records = (0..<13).map {
            record(2026, 9, 20, 19, 30 + $0, balance: 237.36)
        }
        let points = BalanceTrendMath.dailyPoints(from: records)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].timestamp, records.last?.timestamp)
    }

    func testDailyPointsUnsortedInputAndEmpty() {
        let records = [
            record(2026, 9, 2, 23, 0, balance: 90),
            record(2026, 9, 1, 22, 0, balance: 40),
        ]
        // 未排序输入也应输出升序
        let points = BalanceTrendMath.dailyPoints(from: records)
        XCTAssertEqual(points.map(\.balance), [40, 90])
        XCTAssertTrue(BalanceTrendMath.dailyPoints(from: []).isEmpty)
    }

    func testDailyPointsFullYearDownsampling() {
        // 长期使用：一年 365 天 × 每天 5 次 = 1825 条 → 日代表点最多 365
        var records: [BalanceRecord] = []
        let cal = Calendar(identifier: .gregorian)
        let base = BeijingTime.date(year: 2025, month: 9, day: 20)
        for dayOffset in 0..<365 {
            let day = cal.date(byAdding: .day, value: dayOffset, to: base)!
            let comps = cal.dateComponents(in: BeijingTime.timeZone, from: day)
            for hour in [8, 12, 16, 20, 23] {
                records.append(record(
                    comps.year!, comps.month!, comps.day!, hour,
                    balance: 200 - Double(dayOffset) * 0.3 - Double(hour) * 0.01
                ))
            }
        }
        let points = BalanceTrendMath.dailyPoints(from: records)
        XCTAssertEqual(points.count, 365)
        // 升序
        XCTAssertEqual(points.map(\.timestamp), points.map(\.timestamp).sorted())
        // 每个点是当日 23 点那条
        XCTAssertTrue(points.allSatisfy {
            BeijingTime.format($0.date, pattern: "HH") == "23"
        })
    }

    // MARK: - 横轴缩放

    func testDomainPadsShortSpanToMinimumVisible() {
        // 最小缩放：两采样相隔 2 分钟 → 坐标域垫宽到 10 分钟
        let first = BeijingTime.date(year: 2026, month: 9, day: 20, hour: 19, minute: 30)
        let last = first.addingTimeInterval(2 * 60)
        let domain = BalanceTrendMath.domain(from: first, to: last)
        XCTAssertEqual(
            domain.upperBound.timeIntervalSince(domain.lowerBound),
            BalanceTrendMath.minimumVisibleSpan, accuracy: 1.0
        )
        XCTAssertTrue(domain.lowerBound < first)
        XCTAssertTrue(domain.upperBound > last)
    }

    func testDomainAddsBreathingMarginOnLongSpan() {
        // 一年跨度 → 两侧各留 1%（合计 2%，约 3.65 天）
        let first = BeijingTime.date(year: 2025, month: 9, day: 20)
        let last = first.addingTimeInterval(365 * 24 * 3600)
        let domain = BalanceTrendMath.domain(from: first, to: last)
        let total = domain.upperBound.timeIntervalSince(domain.lowerBound)
        XCTAssertEqual(total, 365 * 24 * 3600 * 1.02, accuracy: 60)
    }

    func testAxisDatesAreInteriorAndEvenlySpaced() {
        // 刻度必须是内部点（首尾各留一个步长），标签居中后不超出边界
        let first = BeijingTime.date(year: 2026, month: 9, day: 20, hour: 19, minute: 36)
        let last = first.addingTimeInterval(7 * 60)
        let dates = BalanceTrendMath.axisDates(from: first, to: last)
        XCTAssertEqual(dates.count, 3)
        XCTAssertTrue(dates.allSatisfy { $0 > first && $0 < last })
        let stride = dates[1].timeIntervalSince(dates[0])
        XCTAssertEqual(dates[2].timeIntervalSince(dates[1]), stride, accuracy: 0.5)
        XCTAssertEqual(dates[0].timeIntervalSince(first), stride, accuracy: 0.5)
        XCTAssertTrue(BalanceTrendMath.axisDates(from: first, to: first).isEmpty)
    }

    func testAxisPatternAdaptsToSpan() {
        XCTAssertEqual(BalanceTrendMath.axisPattern(span: 7 * 60), "HH:mm")
        XCTAssertEqual(BalanceTrendMath.axisPattern(span: 23 * 3600 + 59 * 60), "HH:mm")
        XCTAssertEqual(BalanceTrendMath.axisPattern(span: 24 * 3600), "MM-dd")
        XCTAssertEqual(BalanceTrendMath.axisPattern(span: 365 * 24 * 3600), "MM-dd")
    }
}
