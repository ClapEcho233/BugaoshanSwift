import SwiftUI

/// 周网格（对应 course_grid.dart + grid_day_column + grid_section_column）：
/// 固定 35pt 节次列 + 5/7 天列（周末开时顺序为 日一二三四五六），
/// 课程卡按 (startSection-1)×rowHeight 定位；液态玻璃卡片（iOS 26+）。
struct CourseGrid: View {
    let courses: [Course]
    let config: ScheduleConfig
    let week: Int
    let showWeekend: Bool
    let rowHeight: Double
    let todayWeek: Int

    var onTapCourse: ((Course) -> Void)?

    private var dayCount: Int { showWeekend ? 7 : 5 }
    private var sections: Int { config.sectionsPerDay }
    private var isCurrentWeek: Bool { week == todayWeek }

    /// dayIndex → dayOfWeek：周末开启时 0=周日，否则 0=周一
    private func dayOfWeek(for index: Int) -> Int {
        showWeekend ? (index == 0 ? 7 : index) : index + 1
    }

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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    sectionColumn
                    ForEach(0..<dayCount, id: \.self) { index in
                        dayColumn(index)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 表头（星期 + 日期）

    private var header: some View {
        HStack(spacing: 0) {
            Text("节次")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 35)
            ForEach(0..<dayCount, id: \.self) { index in
                let day = dayOfWeek(for: index)
                let date = config.dateForCourseDay(week: week, dayOfWeek: day)
                let isToday = isCurrentWeek && isTodayDate(date)
                VStack(spacing: 2) {
                    Text(weekdayName(day))
                        .font(.caption.weight(isToday ? .bold : .regular))
                    Text(dateText(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isToday
                        ? Color.accentColor.opacity(isToday ? 0.15 : 0)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
        }
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    private func isTodayDate(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    private func dateText(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(comps.month!)/\(comps.day!)"
    }

    private func weekdayName(_ day: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][day - 1]
    }

    // MARK: - 节次列（35pt 固定）

    private var sectionColumn: some View {
        VStack(spacing: 0) {
            ForEach(1...sections, id: \.self) { section in
                VStack(spacing: 1) {
                    Text("\(section)")
                        .font(.caption.weight(.semibold))
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
                .overlay(alignment: .bottom) {
                    sectionBoundary(section)
                }
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

    // MARK: - 天列

    private func dayColumn(_ index: Int) -> some View {
        let day = dayOfWeek(for: index)
        let dayCourses = visibleCourses(dayOfWeek: day)
        return ZStack(alignment: .top) {
            // 节次网格底
            VStack(spacing: 0) {
                ForEach(1...sections, id: \.self) { section in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: rowHeight)
                        .overlay(alignment: .bottom) { sectionBoundary(section) }
                }
            }
            // 课程卡
            GlassEffectContainer(spacing: 2) {
                ForEach(dayCourses) { course in
                    CourseCardView(
                        course: course,
                        config: config,
                        rowHeight: rowHeight,
                        onTap: { onTapCourse?(course) }
                    )
                    .offset(y: Double(course.startSection - 1) * rowHeight + 1)
                }
            }
        }
        .padding(.leading, 1)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 0.5)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - 课程卡（液态玻璃招牌场景）

struct CourseCardView: View {
    let course: Course
    let config: ScheduleConfig
    let rowHeight: Double
    let onTap: () -> Void

    private var active: Bool { true }  // 可见课程已按 isActive 过滤

    private var cardHeight: Double {
        Double(course.endSection - course.startSection + 1) * rowHeight - 2
    }

    /// 亮度 > 0.45 → 深色文字，否则白字
    private var courseColor: Color { course.colorValue.argbColor }
    private var textColor: Color {
        let c = course.colorValue
        let r = Double((c >> 16) & 0xFF) / 255
        let g = Double((c >> 8) & 0xFF) / 255
        let b = Double(c & 0xFF) / 255
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.45 ? .black.opacity(0.85) : .white
    }

    /// 卡高决定详情行预算：<56 → 0 行；<100 → 3 行；否则 5 行
    private var detailLineBudget: Int {
        if cardHeight < 56 { return 0 }
        if cardHeight < 100 { return 3 }
        return 5
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(6)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if detailLineBudget > 0 {
                    if !course.location.isEmpty, detailLineBudget >= 1 {
                        detailText(course.location, lines: 4, cost: 1)
                    }
                    if !course.teacher.isEmpty, detailLineBudget >= 2 {
                        detailText(course.teacher, lines: 2, cost: 1)
                    }
                    if detailLineBudget >= 3 {
                        detailText(weekRangeText, lines: 4, cost: 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .frame(height: cardHeight)
        .glassEffect(
            .regular.tint(courseColor).interactive(),
            in: .rect(cornerRadius: 8)
        )
        .opacity(active ? 1 : 0.5)
    }

    @ViewBuilder
    private func detailText(_ text: String, lines: Int, cost: Int) -> some View {
        Text(text)
            .font(.system(size: max(8, 12 * 0.85)))
            .lineLimit(lines)
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
