import Foundation

/// 校历事件
struct AcademicCalendarEvent: Codable, Equatable, Sendable {
    var date: Date
    var endDate: Date?
    var label: String
    /// holiday / exam / start / course / event
    var tag: String

    func isActive(on target: Date) -> Bool {
        let upper = endDate ?? date
        return target >= date && target <= upper
    }

    func isFinished(on target: Date) -> Bool {
        target > (endDate ?? date)
    }

    func getDaysDifference(target: Date) -> Int {
        target.days(since: date)
    }

    enum CodingKeys: String, CodingKey {
        case date, endDate, label, tag
    }

    init(date: Date, endDate: Date? = nil, label: String, tag: String = "event") {
        self.date = date
        self.endDate = endDate
        self.label = label
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try ScheduleConfig.parseDate(try c.decode(String.self, forKey: .date)) ?? Date()
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate).flatMap(ScheduleConfig.parseDate)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? "event"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ScheduleConfig.formatDate(date), forKey: .date)
        try c.encodeIfPresent(endDate.map(ScheduleConfig.formatDate), forKey: .endDate)
        try c.encode(label, forKey: .label)
        try c.encode(tag, forKey: .tag)
    }
}

/// 校历学期
struct AcademicCalendarSemester: Codable, Equatable, Sendable {
    var name: String
    var startDate: Date
    var totalWeeks: Int
    var events: [AcademicCalendarEvent]

    /// (days/7).floor()+1；学期前或超过 totalWeeks 返回 nil
    func getCurrentWeek(on target: Date) -> Int? {
        let start = startDate.startOfDay
        let today = target.startOfDay
        if today < start { return nil }
        let days = today.days(since: start)
        let week = days / 7 + 1
        return week >= 1 && week <= totalWeeks ? week : nil
    }

    func isDateInSemester(_ target: Date) -> Bool {
        let end = Calendar.current.date(byAdding: .day, value: totalWeeks * 7 - 1, to: startDate)!
        return target >= startDate && target <= end
    }

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: totalWeeks * 7 - 1, to: startDate)!
    }

    /// 第一个 label 含「报到」的事件
    var registrationEvent: AcademicCalendarEvent? {
        events.first { $0.label.contains("报到") }
    }

    /// 与本地课表 id 匹配优先级：
    /// 1. 学期名完全相等；2. 学年键 (\d{4})-(\d{4}) + 季节字 [春秋夏冬] 均包含；
    /// 3. 起点 年+月 相等；4. 仅学年键包含
    func findMatchingScheduleId(in schedules: [(id: String, name: String, startDate: Date)]) -> String? {
        if let exact = schedules.first(where: { $0.name == name }) {
            return exact.id
        }
        func academicYearKey(_ s: String) -> String? {
            guard let range = s.range(of: #"\d{4}-\d{4}"#, options: .regularExpression) else { return nil }
            return String(s[range])
        }
        let selfYear = academicYearKey(name)
        let seasonChars = ["春", "秋", "夏", "冬"]
        let selfSeason = seasonChars.first { name.contains($0) }

        if let selfYear {
            for schedule in schedules {
                guard let otherYear = academicYearKey(schedule.name), otherYear == selfYear,
                      let selfSeason else { continue }
                if let otherSeason = seasonChars.first(where: { schedule.name.contains($0) }),
                   otherSeason == selfSeason {
                    return schedule.id
                }
            }
        }
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: startDate)
        if let byYearMonth = schedules.first(where: { schedule in
            Calendar(identifier: .gregorian).dateComponents([.year, .month], from: schedule.startDate) == comps
        }) {
            return byYearMonth.id
        }
        if let selfYear {
            return schedules.first { academicYearKey($0.name) == selfYear }?.id
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case name, startDate, totalWeeks, events
    }

    init(name: String, startDate: Date, totalWeeks: Int = 20, events: [AcademicCalendarEvent] = []) {
        self.name = name
        self.startDate = startDate
        self.totalWeeks = totalWeeks
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        startDate = try ScheduleConfig.parseDate(try c.decode(String.self, forKey: .startDate)) ?? Date()
        totalWeeks = try c.decodeIfPresent(Int.self, forKey: .totalWeeks) ?? 20
        events = try c.decodeIfPresent([AcademicCalendarEvent].self, forKey: .events) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(ScheduleConfig.formatDate(startDate), forKey: .startDate)
        try c.encode(totalWeeks, forKey: .totalWeeks)
        try c.encode(events, forKey: .events)
    }
}

/// 校历数据（三层结构顶层）
struct AcademicCalendarData: Equatable, Sendable {
    var semesters: [AcademicCalendarSemester]

    init(semesters: [AcademicCalendarSemester] = []) {
        self.semesters = semesters
    }

    /// 第一个 startDate > date 的学期（假定已按 startDate 排序）
    func findNextSemester(after date: Date) -> AcademicCalendarSemester? {
        semesters.first { $0.startDate > date }
    }

    /// 当前日期所在学期
    func findCurrentSemester(on date: Date) -> AcademicCalendarSemester? {
        semesters.first { $0.isDateInSemester(date) }
    }

    static func from(jsonString: String) -> AcademicCalendarData? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AcademicCalendarData.self, from: data)
    }
}

extension AcademicCalendarData: Codable {}
