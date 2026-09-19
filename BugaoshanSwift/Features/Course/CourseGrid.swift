import SwiftUI

// MARK: - 共享组件（周网格 = 表头 + 节次列 + 天列）

/// 表头（星期 + 日期，当天加粗高亮）
struct CourseGridHeader: View {
    let config: ScheduleConfig
    let week: Int
    let showWeekend: Bool
    let todayWeek: Int
    var showDates: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 35)
            ForEach(0..<dayCount, id: \.self) { index in
                let day = dayOfWeek(for: index)
                let date = config.dateForCourseDay(week: week, dayOfWeek: day)
                let isToday = showDates && week == todayWeek && Calendar.current.isDate(date, inSameDayAs: Date())
                VStack(spacing: 2) {
                    Text(weekdayName(day))
                        .font(.caption.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    if showDates {
                        Text(dateText(date))
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
        }
    }

    private var dayCount: Int { showWeekend ? 7 : 5 }

    /// dayIndex → dayOfWeek：周末开启时 0=周日，否则 0=周一
    func dayOfWeek(for index: Int) -> Int {
        showWeekend ? (index == 0 ? 7 : index) : index + 1
    }

    private func dateText(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(comps.month!)/\(comps.day!)"
    }

    private func weekdayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][day - 1]
    }
}

/// 节次列（35pt 固定）
struct CourseGridGutter: View {
    let config: ScheduleConfig
    let rowHeight: Double

    var body: some View {
        VStack(spacing: 0) {
            ForEach(1...config.sectionsPerDay, id: \.self) { section in
                VStack(spacing: 1) {
                    Text("\(section)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if section <= config.timeSlots.count {
                        Text(config.timeSlots[section - 1].format(true))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        if rowHeight >= 60 {
                            Text(config.timeSlots[section - 1].format(false))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(width: 35, height: rowHeight)
                .overlay(alignment: .bottom) { sectionBoundary(section) }
            }
        }
    }

    /// 节次分隔线：上午/下午结束边界 1.5pt 强调，普通 0.5pt
    private func sectionBoundary(_ section: Int) -> some View {
        let isBoundary = section == config.morningSections
            || section == config.morningSections + config.afternoonSections
        return Rectangle()
            .fill(isBoundary
                  ? AnyShapeStyle(Color.accentColor.opacity(150.0 / 255.0))
                  : AnyShapeStyle(Color(.separator).opacity(0.5)))
            .frame(height: isBoundary ? 1.5 : 0.5)
            .padding(.horizontal, 2)
    }
}

/// 天列组（仅天列，不带节次列）：供整页使用，也可被按周分页复用
struct CourseGridDayColumns: View {
    let courses: [Course]
    let config: ScheduleConfig
    let week: Int
    let showWeekend: Bool
    let rowHeight: Double

    var onTapCourse: ((Course) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<dayCount, id: \.self) { index in
                dayColumn(index)
            }
        }
    }

    private var dayCount: Int { showWeekend ? 7 : 5 }

    /// 该天可见课程（同槽合并 + 按节次排序）
    private func visibleCourses(dayOfWeek: Int) -> [Course] {
        let active = courses.filter { $0.dayOfWeek == dayOfWeek && $0.isActive(inWeek: week) }
        return Self.mergeSameSlotCourses(active.sorted {
            if $0.startSection != $1.startSection { return $0.startSection < $1.startSection }
            if $0.endSection != $1.endSection { return $0.endSection > $1.endSection }
            return $0.startWeek < $1.startWeek
        })
    }

    static func mergeSameSlotCourses(_ sorted: [Course]) -> [Course] {
        struct Key: Hashable {
            let name: String
            let day: Int
            let start: Int
            let end: Int
            let location: String
        }
        var order: [Key] = []
        var groups: [Key: [Course]] = [:]
        for course in sorted {
            let key = Key(name: course.name, day: course.dayOfWeek,
                          start: course.startSection, end: course.endSection,
                          location: course.location)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(course)
        }
        return order.map { key in
            let group = groups[key]!
            if group.count == 1 { return group[0] }
            var merged = group[0]
            let teachers = group.map(\.teacher).filter { !$0.isEmpty }
            merged.teacher = Array(Set(teachers)).sorted().joined(separator: "、")
            merged.startWeek = group.map(\.startWeek).min() ?? 1
            merged.endWeek = group.map(\.endWeek).max() ?? 20
            return merged
        }
    }

    private func dayOfWeek(for index: Int) -> Int {
        showWeekend ? (index == 0 ? 7 : index) : index + 1
    }

    private func dayColumn(_ index: Int) -> some View {
        let day = dayOfWeek(for: index)
        let dayCourses = visibleCourses(dayOfWeek: day)
        return ZStack(alignment: .topLeading) {
            // 节次网格底
            VStack(spacing: 0) {
                ForEach(1...config.sectionsPerDay, id: \.self) { section in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) { sectionBoundary(section) }
                }
            }
            // 课程卡（topLeading 对齐 + offset 定位，不使用液态玻璃，
            // 否则相邻卡片会被 GlassEffectContainer 合并/变形导致偏移和吞卡）
            ForEach(dayCourses) { course in
                CourseCardView(
                    course: course,
                    config: config,
                    rowHeight: rowHeight,
                    onTap: { onTapCourse?(course) }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 1)
                .offset(y: Double(course.startSection - 1) * rowHeight + 1)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 0.5)
        }
        .clipped()
    }

    /// 节次分隔线：上午/下午结束边界 1.5pt 强调，普通 0.5pt
    private func sectionBoundary(_ section: Int) -> some View {
        let isBoundary = section == config.morningSections
            || section == config.morningSections + config.afternoonSections
        return Rectangle()
            .fill(isBoundary
                  ? AnyShapeStyle(Color.accentColor.opacity(150.0 / 255.0))
                  : AnyShapeStyle(Color(.separator).opacity(0.5)))
            .frame(height: isBoundary ? 1.5 : 0.5)
            .padding(.horizontal, 2)
    }
}

// MARK: - 课程卡（Apple 日历日程卡风格：浅色底 + 左色条 + 彩色文字）

struct CourseCardView: View {
    let course: Course
    let config: ScheduleConfig
    let rowHeight: Double
    let onTap: () -> Void

    private var active: Bool { true }  // 可见课程已按 isActive 过滤

    private var cardHeight: Double {
        Double(course.endSection - course.startSection + 1) * rowHeight - 2
    }

    private var courseColor: Color { course.colorValue.argbColor }

    /// 文字统一黑色
    private var textColor: Color { .primary }

    /// 卡高决定详情行预算：<56 → 0 行；<100 → 3 行；否则 5 行
    private var detailLineBudget: Int {
        if cardHeight < 56 { return 0 }
        if cardHeight < 100 { return 3 }
        return 5
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(courseColor)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(6)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if detailLineBudget > 0 {
                        if !course.location.isEmpty, detailLineBudget >= 1 {
                            detailText(course.location, lines: 4)
                        }
                        if !course.teacher.isEmpty, detailLineBudget >= 2 {
                            detailText(course.teacher, lines: 2)
                        }
                        if detailLineBudget >= 3 {
                            detailText(weekRangeText, lines: 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(courseColor.opacity(0.16), in: .rect(cornerRadius: 6))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(height: cardHeight)
        .contentShape(.rect(cornerRadius: 6))
        .opacity(active ? 1 : 0.5)
    }

    @ViewBuilder
    private func detailText(_ text: String, lines: Int) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .lineLimit(lines)
            .foregroundStyle(textColor.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekRangeText: String {
        let base = course.startWeek == course.endWeek
            ? "第\(course.startWeek)周"
            : "\(course.startWeek)-\(course.endWeek) 周"
        switch course.weekType {
        case .every: return base
        case .odd: return base + "（单）"
        case .even: return base + "（双）"
        }
    }
}
