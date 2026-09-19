import Foundation

/// 周类型（枚举序号 0/1/2，JSON 与 DB 均存序号）
enum WeekType: Int, Codable, Equatable, Sendable, CaseIterable {
    case every = 0
    case odd = 1
    case even = 2
}

/// 课表中的一条「课程占用」：某门课在某天某节次段、某周次区间的一次排课。
/// 同一门课多个周段/多节次会展开成多条 Course 记录。
struct Course: Identifiable, Codable, Equatable, Hashable, Sendable {

    static let defaultTotalWeeks = 20

    var id: String = ""
    var name: String = ""
    var teacher: String = ""
    var location: String = ""
    var campus: String = ""
    var startWeek: Int = 1
    var endWeek: Int = Course.defaultTotalWeeks
    /// 1=周一 … 7=周日
    var dayOfWeek: Int = 1
    /// 1-based，对应 timeSlots 索引 startSection-1
    var startSection: Int = 1
    var endSection: Int = 1
    /// ARGB 位编码（与 Flutter 版 Color.toARGB32() 一致）
    var colorValue: Int = 0xFF2196F3
    var weekType: WeekType = .every

    /// `'{microsecondsSinceEpoch}_{++counter}'`（进程内静态计数）
    static func generateId() -> String {
        struct Counter {
            static let lock = NSLock()
            static var value = 0
            static func next() -> Int {
                lock.lock(); defer { lock.unlock() }
                value += 1
                return value
            }
        }
        let micros = Int(Date().timeIntervalSince1970 * 1_000_000)
        return "\(micros)_\(Counter.next())"
    }

    var generatedId: Course {
        var copy = self
        copy.id = Self.generateId()
        return copy
    }

    /// 该周是否有课：区间内 +（odd 需周为奇 / even 需周为偶）
    func isActive(inWeek week: Int) -> Bool {
        guard week >= startWeek, week <= endWeek else { return false }
        switch weekType {
        case .every: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }

    /// 冲突判定：同 dayOfWeek + 节次区间相交 + 周区间相交 + 奇偶有共享周
    func conflicts(with other: Course, excludeId: String? = nil) -> Bool {
        if let excludeId, other.id == excludeId { return false }
        guard dayOfWeek == other.dayOfWeek else { return false }
        // 节次区间相交
        guard startSection <= other.endSection, other.startSection <= endSection else { return false }
        // 周区间相交
        let weekOverlapStart = max(startWeek, other.startWeek)
        let weekOverlapEnd = min(endWeek, other.endWeek)
        guard weekOverlapStart <= weekOverlapEnd else { return false }
        return hasSharedWeek(with: other, in: weekOverlapStart...weekOverlapEnd)
    }

    private func hasSharedWeek(with other: Course, in range: ClosedRange<Int>) -> Bool {
        // every + 任意 → 恒有共享；odd/even 互斥；同类取交集内任一周即可
        if weekType == .every || other.weekType == .every {
            if weekType == .every && other.weekType == .every { return true }
            // one every, one odd/even → 取 odd/even 一方在交集内的第一个奇/偶周
            let parityType = weekType == .every ? other.weekType : weekType
            for week in range where (parityType == .odd ? week % 2 == 1 : week % 2 == 0) {
                return true
            }
            return false
        }
        if weekType != other.weekType { return false }
        // 同为 odd 或同为 even
        for week in range where (weekType == .odd ? week % 2 == 1 : week % 2 == 0) {
            return true
        }
        return false
    }
}

// MARK: - 周界计算（Dart DateTimeExtension 语义；dayIndex 1=周一 … 7=周日）

extension Date {
    /// Dart weekday：周一=1 … 周日=7
    var dartWeekday: Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }

    /// 本周周一（Dart toMonday）
    var dartMonday: Date {
        Calendar.current.date(byAdding: .day, value: -(dartWeekday - 1), to: self)!
    }

    /// 教务语义的「本周周日」：周日挂在同一教学周内（Dart toSunday：
    /// weekday % 7 —— 周日=7 → 0）
    var dartSunday: Date {
        Calendar.current.date(byAdding: .day, value: -(dartWeekday % 7), to: self)!
    }

    /// 当天零点（公历）
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// 天数差（today.difference(start).inDays 语义，按零点算）
    func days(since earlier: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let a = cal.startOfDay(for: earlier)
        let b = cal.startOfDay(for: self)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

// MARK: - ARGB 颜色（Flutter Color 兼容）

import SwiftUI

extension Int {
    /// ARGB int → SwiftUI Color（与 Flutter Color.toARGB32() 对应）
    var argbColor: Color {
        let a = Double((self >> 24) & 0xFF) / 255.0
        let r = Double((self >> 16) & 0xFF) / 255.0
        let g = Double((self >> 8) & 0xFF) / 255.0
        let b = Double(self & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

extension Color {
    /// SwiftUI Color → ARGB int（尽量保真；space 归一化在 UI 层处理）
    var argbValue: Int {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        let ai = Int((a * 255).rounded())
        return (ai << 24) | (ri << 16) | (gi << 8) | bi
    }
}
