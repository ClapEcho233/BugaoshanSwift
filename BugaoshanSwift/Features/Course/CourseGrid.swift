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

    /// dayIndex → dayOfWeek：周末开启时 0=周日，否则 0=周一
    /// 列头文字经 xcstrings 本地化（键为中文单字，en 表提供 Mon–Sun）
    private func weekdayName(_ day: Int) -> String {
        let keys = ["一", "二", "三", "四", "五", "六", "日"]
        return NSLocalizedString(keys[day - 1], comment: "课表列头星期")
    }
}

/// 节次列（35pt 固定）：节号 + 开始/结束时间，每分钟刷新，
/// 浏览本周时高亮当前时刻所在的节次
struct CourseGridGutter: View {
    let config: ScheduleConfig
    let week: Int
    let todayWeek: Int
    let rowHeight: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            // 仅当正在浏览本周（今天所在教学周）时，当前节才有高亮意义
            let currentSection = week == todayWeek ? config.currentSection(at: now) : nil
            VStack(spacing: 0) {
                ForEach(1...config.sectionsPerDay, id: \.self) { section in
                    gutterCell(section, isCurrent: section == currentSection)
                }
            }
        }
    }

    private func gutterCell(_ section: Int, isCurrent: Bool) -> some View {
        VStack(spacing: 1) {
            Text("\(section)")
                .font(.caption2.weight(isCurrent ? .bold : .semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
            if section <= config.timeSlots.count {
                let slot = config.timeSlots[section - 1]
                Text(slot.format(true))
                    .font(.system(size: 8))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                Text(slot.format(false))
                    .font(.system(size: 8))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(width: 35, height: rowHeight)
        .overlay(alignment: .bottom) { sectionBoundary(section) }
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

/// 天列组（仅天列，不带节次列）：供整页使用，也可被按周分页复用；
/// 每分钟刷新，今天的当前节课程高亮
struct CourseGridDayColumns: View {
    let courses: [Course]
    let config: ScheduleConfig
    let week: Int
    let showWeekend: Bool
    let todayWeek: Int
    let rowHeight: Double

    var onTapCourse: ((Course) -> Void)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<dayCount, id: \.self) { index in
                    dayColumn(index, now: now)
                }
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

    private func dayColumn(_ index: Int, now: Date) -> some View {
        let day = dayOfWeek(for: index)
        let dayCourses = visibleCourses(dayOfWeek: day)
        // 今天且正在浏览本周 → 当前时刻所在节次；据此高亮「正在上」的课程
        let isToday = week == todayWeek
            && Calendar.current.isDate(
                config.dateForCourseDay(week: week, dayOfWeek: day), inSameDayAs: now)
        let currentSection = isToday ? config.currentSection(at: now) : nil
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
                    currentProgress: courseProgress(course, currentSection: currentSection, now: now),
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

    /// 当前时刻落在课程节次区间内时的课程时间进度（0…1，跨整段连堂课：
    /// 从首节并始到末节结束的总时长）；不在课内返回 nil
    private func courseProgress(
        _ course: Course, currentSection section: Int?, now: Date
    ) -> Double? {
        guard let section,
              course.startSection <= section, section <= course.endSection,
              course.startSection - 1 < config.timeSlots.count,
              course.endSection - 1 < config.timeSlots.count else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = config.timeSlots[course.startSection - 1].startMinuteOfDay
        let end = config.timeSlots[course.endSection - 1].endMinuteOfDay
        guard end > start else { return nil }
        return min(max(Double(minuteOfDay - start) / Double(end - start), 0), 1)
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
    /// 当前时刻正上这节课的课程时间进度（0…1，仅今天 + 本周视图生效）；
    /// nil = 非当前。高亮样式：轻微加深底色 + 课程色柔阴影 + 底部进度条
    var currentProgress: Double?
    let onTap: () -> Void

    private var isCurrent: Bool { currentProgress != nil }

    private var active: Bool { true }  // 可见课程已按 isActive 过滤

    private var cardHeight: Double {
        Double(course.endSection - course.startSection + 1) * rowHeight - 2
    }

    private var courseColor: Color { course.colorValue.argbColor }

    /// 文字颜色：高亮卡白字（Apple 日历「进行中」事件风格），普通卡黑字
    private var textColor: Color { isCurrent ? .white : .primary }

    /// 课程色过亮（相对亮度 > 0.72，如浅黄/浅粉）时压暗填充背景，保证白字可读
    private var needsDarkening: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(courseColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.72
    }

    /// 卡高决定详情行预算：<56 → 0 行；<100 → 3 行；否则 5 行
    private var detailLineBudget: Int {
        if cardHeight < 56 { return 0 }
        if cardHeight < 100 { return 3 }
        return 5
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                // 高亮卡背景已是课程色实底，左色条融入背景不再需要
                if !isCurrent {
                    Rectangle()
                        .fill(courseColor)
                        .frame(width: 3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.system(size: 12, weight: isCurrent ? .bold : .semibold))
                        .foregroundStyle(textColor)
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
                    if let progress = currentProgress {
                        // 课程时间进度条：直观表达「正在上」，替代硬描边
                        progressTrack(progress)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                Group {
                    if isCurrent {
                        // Apple 日历「进行中」高亮：课程色实底 + 白字
                        ZStack {
                            courseColor
                            if needsDarkening {
                                Color.black.opacity(0.15)
                            }
                        }
                    } else {
                        courseColor.opacity(0.16)
                    }
                }
            }
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

    /// 课程时间进度条（仅高亮卡白底白字语境）：轨道白色淡铺，填充宽 = 已过时间比例
    private func progressTrack(_ progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.25))
            GeometryReader { geo in
                Capsule().fill(Color.white)
                    .frame(width: max(4, geo.size.width * progress))
            }
        }
        .frame(height: 3)
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
