import Foundation

/// 节次时间
struct TimeSlot: Codable, Equatable, Sendable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int

    var startMinuteOfDay: Int { startHour * 60 + startMinute }
    var endMinuteOfDay: Int { endHour * 60 + endMinute }

    /// JSON 形如 {"startTime":{"hour":8,"minute":15},"endTime":{"hour":9,"minute":0}}
    enum CodingKeys: String, CodingKey {
        case startTime, endTime
    }

    init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.nestedContainer(keyedBy: HMKeys.self, forKey: .startTime)
        let end = try container.nestedContainer(keyedBy: HMKeys.self, forKey: .endTime)
        startHour = try start.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        startMinute = try start.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        endHour = try end.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        endMinute = try end.decodeIfPresent(Int.self, forKey: .minute) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var start = container.nestedContainer(keyedBy: HMKeys.self, forKey: .startTime)
        try start.encode(startHour, forKey: .hour)
        try start.encode(startMinute, forKey: .minute)
        var end = container.nestedContainer(keyedBy: HMKeys.self, forKey: .endTime)
        try end.encode(endHour, forKey: .hour)
        try end.encode(endMinute, forKey: .minute)
    }

    private enum HMKeys: String, CodingKey { case hour, minute }

    /// 显示用 "HH:mm"
    func format(_ isStart: Bool) -> String {
        let h = isStart ? startHour : endHour
        let m = isStart ? startMinute : endMinute
        return String(format: "%02d:%02d", h, m)
    }
}

/// 课表配置（对应 lib/models/schedule_config.dart，含全部 fromJson 兼容逻辑）
struct ScheduleConfig: Codable, Equatable, Identifiable, Sendable {

    var id: String = "default"
    var semesterName: String = ""
    /// 学期第一教学周起点（允许是周日——教务周以周日为首日）
    var semesterStartDate: Date = Date()
    var totalWeeks: Int = 20
    var morningSections: Int = 4
    var afternoonSections: Int = 5
    var eveningSections: Int = 3
    var courseDuration: Int = 45
    var breakDuration: Int = 10
    var autoSyncTime: Bool = true
    var timeSlots: [TimeSlot] = []

    // MARK: - 派生

    var sectionsPerDay: Int { morningSections + afternoonSections + eveningSections }
    var semesterEndDate: Date {
        Calendar.current.date(byAdding: .day, value: totalWeeks * 7 - 1, to: semesterStartDate)!
    }

    /// 当前教学周：以 semesterStartDate 为第 1 周第 1 天，每 7 天进一周；
    /// 学期前返回 1；无 totalWeeks 上限钳制
    func getCurrentWeek(from now: Date = Date()) -> Int {
        let today = now.startOfDay
        let start = semesterStartDate.startOfDay
        if today < start { return 1 }
        let days = today.days(since: start)
        return days / 7 + 1
    }

    /// 第 week 周 dayOfWeek（1=周一…7=周日）对应的日期。
    /// 周日语义：教务把周日挂在同一教学周内（周日=本周周一的前一天）。
    func dateForCourseDay(week: Int, dayOfWeek: Int) -> Date {
        let startWeekday = semesterStartDate.dartWeekday
        let mondayOffset = ((1 - startWeekday) % 7 + 7) % 7
        let daysFromMonday = dayOfWeek == 7 ? -1 : dayOfWeek - 1
        let offset = (week - 1) * 7 + mondayOffset + daysFromMonday
        return Calendar.current.date(byAdding: .day, value: offset, to: semesterStartDate)!
    }

    // MARK: - Codable（键名与 Dart toJson 逐字一致）

    enum CodingKeys: String, CodingKey {
        case id, semesterName, semesterStartDate, totalWeeks
        case morningSections, afternoonSections, eveningSections
        case courseDuration, breakDuration, autoSyncTime, timeSlots
        case semesterEndDate   // 旧字段（仅读取）
        case sectionsPerDay    // 旧字段（仅读取）
    }

    init() {
        timeSlots = ScheduleConfig.defaultTimeSlots(morning: 4, afternoon: 5, evening: 3, courseDuration: 45, breakDuration: 10)
    }

    init(id: String) {
        self.init()
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "default"
        semesterName = try c.decodeIfPresent(String.self, forKey: .semesterName) ?? ""
        semesterStartDate = try c.decodeIfPresent(String.self, forKey: .semesterStartDate).flatMap(Self.parseDate) ?? Date()

        let legacyEndDate = try c.decodeIfPresent(String.self, forKey: .semesterEndDate).flatMap(Self.parseDate)
        if let weeks = try c.decodeIfPresent(Int.self, forKey: .totalWeeks) {
            totalWeeks = weeks
        } else if let endDate = legacyEndDate {
            // 兼容：totalWeeks 缺失但有 semesterEndDate → 天数/7 向上取整
            let days = endDate.days(since: semesterStartDate)
            totalWeeks = max(1, (days + 6) / 7)
        } else {
            totalWeeks = 20
        }

        if let morning = try c.decodeIfPresent(Int.self, forKey: .morningSections) {
            morningSections = morning
            afternoonSections = try c.decodeIfPresent(Int.self, forKey: .afternoonSections) ?? 5
            eveningSections = try c.decodeIfPresent(Int.self, forKey: .eveningSections) ?? 3
        } else if let legacyTotal = try c.decodeIfPresent(Int.self, forKey: .sectionsPerDay) {
            // 兼容：旧字段 sectionsPerDay（总节数）拆分
            morningSections = min(4, legacyTotal)
            afternoonSections = legacyTotal >= 9 ? 5 : (legacyTotal > 4 ? legacyTotal - 4 : 0)
            eveningSections = legacyTotal > 9 ? legacyTotal - 9 : 0
        } else {
            morningSections = 4
            afternoonSections = 5
            eveningSections = 3
        }

        courseDuration = try c.decodeIfPresent(Int.self, forKey: .courseDuration) ?? 45
        breakDuration = try c.decodeIfPresent(Int.self, forKey: .breakDuration) ?? 10
        autoSyncTime = try c.decodeIfPresent(Bool.self, forKey: .autoSyncTime) ?? true
        if let slots = try c.decodeIfPresent([TimeSlot].self, forKey: .timeSlots) {
            timeSlots = slots
        } else {
            // 4-5-3 直接返回江安预设拷贝；否则按节数/时长推导
            timeSlots = morningSections == 4 && afternoonSections == 5 && eveningSections == 3
                ? ScheduleConfig.jiangAnTimeSlots
                : ScheduleConfig.defaultTimeSlots(
                    morning: morningSections, afternoon: afternoonSections,
                    evening: eveningSections, courseDuration: courseDuration, breakDuration: breakDuration)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(semesterName, forKey: .semesterName)
        try c.encode(Self.formatDate(semesterStartDate), forKey: .semesterStartDate)
        try c.encode(totalWeeks, forKey: .totalWeeks)
        try c.encode(morningSections, forKey: .morningSections)
        try c.encode(afternoonSections, forKey: .afternoonSections)
        try c.encode(eveningSections, forKey: .eveningSections)
        try c.encode(courseDuration, forKey: .courseDuration)
        try c.encode(breakDuration, forKey: .breakDuration)
        try c.encode(autoSyncTime, forKey: .autoSyncTime)
        try c.encode(timeSlots, forKey: .timeSlots)
    }

    // MARK: - 日期编解码（yyyy-MM-dd，月/日 padLeft 2 位）

    static func parseDate(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        return Calendar(identifier: .gregorian).date(from: components)
    }

    static func formatDate(_ date: Date) -> String {
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    // MARK: - 默认时间表推导

    /// 非 4-5-3 时的通用推导：上午 08:00 起、下午 14:00 起、晚上 19:00 起，
    /// 每节 +courseDuration，节间 +breakDuration
    static func defaultTimeSlots(
        morning: Int, afternoon: Int, evening: Int,
        courseDuration: Int, breakDuration: Int
    ) -> [TimeSlot] {
        var slots: [TimeSlot] = []
        func appendSessions(_ count: Int, startingAt startMinute: Int) {
            var minute = startMinute
            for _ in 0..<count {
                let end = minute + courseDuration
                slots.append(TimeSlot(
                    startHour: minute / 60, startMinute: minute % 60,
                    endHour: end / 60, endMinute: end % 60
                ))
                minute = end + breakDuration
            }
        }
        appendSessions(morning, startingAt: 8 * 60)
        appendSessions(afternoon, startingAt: 14 * 60)
        appendSessions(evening, startingAt: 19 * 60)
        return slots
    }

    // MARK: - 校区时间表预设（各 12 节，4-5-3）

    static let jiangAnTimeSlots: [TimeSlot] = [
        TimeSlot(startHour: 8, startMinute: 15, endHour: 9, endMinute: 0),
        TimeSlot(startHour: 9, startMinute: 10, endHour: 9, endMinute: 55),
        TimeSlot(startHour: 10, startMinute: 15, endHour: 11, endMinute: 0),
        TimeSlot(startHour: 11, startMinute: 10, endHour: 11, endMinute: 55),
        TimeSlot(startHour: 13, startMinute: 50, endHour: 14, endMinute: 35),
        TimeSlot(startHour: 14, startMinute: 45, endHour: 15, endMinute: 30),
        TimeSlot(startHour: 15, startMinute: 40, endHour: 16, endMinute: 25),
        TimeSlot(startHour: 16, startMinute: 45, endHour: 17, endMinute: 30),
        TimeSlot(startHour: 17, startMinute: 40, endHour: 18, endMinute: 25),
        TimeSlot(startHour: 19, startMinute: 20, endHour: 20, endMinute: 5),
        TimeSlot(startHour: 20, startMinute: 15, endHour: 21, endMinute: 0),
        TimeSlot(startHour: 21, startMinute: 10, endHour: 21, endMinute: 55),
    ]

    static let wangJiangHuaXiTimeSlots: [TimeSlot] = [
        TimeSlot(startHour: 8, startMinute: 0, endHour: 8, endMinute: 45),
        TimeSlot(startHour: 8, startMinute: 55, endHour: 9, endMinute: 40),
        TimeSlot(startHour: 10, startMinute: 0, endHour: 10, endMinute: 45),
        TimeSlot(startHour: 10, startMinute: 55, endHour: 11, endMinute: 40),
        TimeSlot(startHour: 14, startMinute: 0, endHour: 14, endMinute: 45),
        TimeSlot(startHour: 14, startMinute: 55, endHour: 15, endMinute: 40),
        TimeSlot(startHour: 15, startMinute: 50, endHour: 16, endMinute: 35),
        TimeSlot(startHour: 16, startMinute: 55, endHour: 17, endMinute: 40),
        TimeSlot(startHour: 17, startMinute: 50, endHour: 18, endMinute: 35),
        TimeSlot(startHour: 19, startMinute: 30, endHour: 20, endMinute: 15),
        TimeSlot(startHour: 20, startMinute: 25, endHour: 21, endMinute: 10),
        TimeSlot(startHour: 21, startMinute: 20, endHour: 22, endMinute: 5),
    ]

    static let campusKeywords = ["江安", "望江", "华西"]

    /// 名字含「江安」→江安表；含「望江」或「华西」→望江/华西表；否则 nil
    static func timeSlotsForCampusName(_ name: String) -> [TimeSlot]? {
        if name.contains("江安") { return jiangAnTimeSlots }
        if name.contains("望江") || name.contains("华西") { return wangJiangHuaXiTimeSlots }
        return nil
    }

    /// 先匹配 course.campus，未命中再匹配 course.location
    static func campusKeyword(of course: Course) -> String? {
        for keyword in campusKeywords {
            if course.campus.contains(keyword) { return keyword }
        }
        for keyword in campusKeywords {
            if course.location.contains(keyword) { return keyword }
        }
        return nil
    }

    /// 按 course.name 去重后统计校区关键词（同名多条取第一个命中）；
    /// 严格最多者胜，并列/为空返回 nil
    static func dominantCampus(ofCourses courses: [Course]) -> String? {
        var seen = Set<String>()
        var counts: [String: Int] = [:]
        for course in courses {
            guard !seen.contains(course.name) else { continue }
            seen.insert(course.name)
            if let keyword = campusKeyword(of: course) {
                counts[keyword, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return nil }
        let sorted = counts.sorted { $0.value > $1.value }
        guard sorted.count == 1 || sorted[0].value > sorted[1].value else { return nil }
        return sorted.first?.key
    }

    /// 仅当 4-5-3 且存在主导校区时替换为该校区预设（导入流程自动套时间表）
    static func applyCampusTimeSlots(
        _ config: inout ScheduleConfig,
        courses: [Course]
    ) {
        guard config.morningSections == 4, config.afternoonSections == 5, config.eveningSections == 3,
              let campus = dominantCampus(ofCourses: courses),
              let slots = timeSlotsForCampusName(campus) else {
            return
        }
        config.timeSlots = slots
    }

    /// 与任一预设完全一致 → 用户未自定义过
    static func isPresetTimeSlots(_ slots: [TimeSlot]) -> Bool {
        slots == jiangAnTimeSlots || slots == wangJiangHuaXiTimeSlots
    }
}
