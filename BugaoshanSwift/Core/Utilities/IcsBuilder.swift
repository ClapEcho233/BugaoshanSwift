import Foundation

/// ICS 生成（对应 lib/services/ics_service.dart）：
/// 伪 VTIMEZONE 固定 +0800；课程逐周 VEVENT；UID 方案支撑跨版本去重。
enum IcsBuilder {

    // MARK: - VCALENDAR 头

    static func header(productName: String) -> String {
        """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Bugaoshan//\(productName)//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        X-WR-TIMEZONE:Asia/Shanghai
        BEGIN:VTIMEZONE
        TZID:Asia/Shanghai
        BEGIN:STANDARD
        TZOFFSETFROM:+0800
        TZOFFSETTO:+0800
        TZNAME:CST
        DTSTART:19700101T000000
        RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=3
        END:STANDARD
        BEGIN:DAYLIGHT
        TZOFFSETFROM:+0800
        TZOFFSETTO:+0800
        TZNAME:CST
        DTSTART:19700101T000000
        RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
        END:DAYLIGHT
        END:VTIMEZONE

        """
    }

    static let footer = "END:VCALENDAR"

    // MARK: - 课程 ICS

    /// 文件名：{semesterName sanitize}.ics
    static func courseScheduleIcs(config: ScheduleConfig, courses: [Course]) -> String {
        var lines = [header(productName: "Course Schedule")]
        let calendar = Calendar(identifier: .gregorian)
        for course in courses {
            for week in course.startWeek...course.endWeek where course.isActive(inWeek: week) {
                let date = config.dateForCourseDay(week: week, dayOfWeek: course.dayOfWeek)
                guard course.startSection <= config.timeSlots.count,
                      course.endSection <= config.timeSlots.count else { continue }
                let start = config.timeSlots[course.startSection - 1]
                let end = config.timeSlots[course.endSection - 1]
                let day = calendar.dateComponents([.year, .month, .day], from: date)
                let dayString = String(format: "%04d%02d%02d", day.year!, day.month!, day.day!)
                lines.append("BEGIN:VEVENT")
                lines.append("DTSTART;TZID=Asia/Shanghai:\(dayString)T\(hm(start.startHour, start.startMinute))00")
                lines.append("DTEND;TZID=Asia/Shanghai:\(dayString)T\(hm(end.endHour, end.endMinute))00")
                lines.append("SUMMARY:\(escape(course.name))")
                let resolvedLocation = CalendarLocationMapper.resolve(course.location, campusName: course.campus).title
                if !resolvedLocation.isEmpty {
                    lines.append("LOCATION:\(escape(resolvedLocation))")
                }
                if !course.teacher.isEmpty {
                    lines.append("DESCRIPTION:\(escape("教师: \(course.teacher)"))")
                }
                lines.append("UID:\(course.id)_\(week)@bugaoshan")
                lines.append("END:VEVENT")
            }
        }
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    /// 考试 ICS（ExamInfo 待 Phase 3 模型，此处先按字段约定）
    static func examIcs(exams: [(name: String, week: String, date: String, timeRange: String,
                                 location: String, seatNumber: String, ticketNumber: String, tip: String)]) -> String {
        var lines = [header(productName: "Exam Schedule")]
        for exam in exams {
            // 日期时间解析：不匹配则跳过该考试
            guard let dayString = normalizedDate(exam.date),
                  let (startHM, endHM) = normalizedTimeRange(exam.timeRange) else {
                continue
            }
            var summary = exam.name
            if !summary.hasSuffix("考试") {
                summary += "考试"
            }
            var descriptionParts = [exam.week]
            if !exam.seatNumber.isEmpty {
                descriptionParts.append("座位号: \(exam.seatNumber)")
            }
            if !exam.ticketNumber.isEmpty {
                descriptionParts.append("准考证号: \(exam.ticketNumber)")
            }
            if !exam.tip.isEmpty && exam.tip != "无" {
                descriptionParts.append("提示: \(exam.tip)")
            }
            lines.append("BEGIN:VEVENT")
            lines.append("DTSTART;TZID=Asia/Shanghai:\(dayString)T\(startHM)00")
            lines.append("DTEND;TZID=Asia/Shanghai:\(dayString)T\(endHM)00")
            lines.append("SUMMARY:\(escape(summary))")
            let resolvedExamLocation = CalendarLocationMapper.resolve(exam.location).title
            if !resolvedExamLocation.isEmpty {
                lines.append("LOCATION:\(escape(resolvedExamLocation))")
            }
            lines.append("DESCRIPTION:\(escape(descriptionParts.joined(separator: "\\n")))")
            lines.append("UID:exam-\(uidHash("exam|\(normalizeExamName(exam.name))"))@bugaoshan")
            lines.append("END:VEVENT")
        }
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    // MARK: - 校历 ICS

    static func academicCalendarIcs(semester: AcademicCalendarSemester) -> String {
        var lines = [header(productName: "Academic Calendar")]
        let calendar = Calendar(identifier: .gregorian)
        for event in semester.events {
            let startComps = calendar.dateComponents([.year, .month, .day], from: event.date)
            let endComps = calendar.dateComponents([.year, .month, .day], from: event.endDate ?? event.date)
            let start = String(format: "%04d%02d%02dT080000", startComps.year!, startComps.month!, startComps.day!)
            let end = String(format: "%04d%02d%02dT180000", endComps.year!, endComps.month!, endComps.day!)
            let millis = Int(event.date.timeIntervalSince1970 * 1000)
            lines.append("BEGIN:VEVENT")
            lines.append("DTSTART;TZID=Asia/Shanghai:\(start)")
            lines.append("DTEND;TZID=Asia/Shanghai:\(end)")
            lines.append("SUMMARY:\(escape(event.label))")
            lines.append("LOCATION:\(escape("四川大学"))")
            lines.append("DESCRIPTION:\(escape("四川大学官方校历日程\\n类型: \(event.tag)"))")
            lines.append("UID:acad-\(semester.name.replacingOccurrences(of: " ", with: "_"))-\(event.label.replacingOccurrences(of: " ", with: "_"))-\(millis)@bugaoshan")
            lines.append("END:VEVENT")
        }
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    static func calendarFileName(semesterName: String) -> String {
        "\(safeFileName(semesterName)).ics"
    }

    // MARK: - 工具

    private static func hm(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d%02d", hour, minute)
    }

    private static func normalizedDate(_ date: String) -> String? {
        let parts = date.split(separator: "-")
        guard parts.count == 3, parts.allSatisfy({ $0.count == 2 || $0.count == 4 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return String(format: "%04d%02d%02d", year, month, day)
    }

    private static func normalizedTimeRange(_ range: String) -> (String, String)? {
        let parts = range.split(separator: "-")
        guard parts.count == 2 else { return nil }
        let startParts = parts[0].split(separator: ":")
        let endParts = parts[1].split(separator: ":")
        guard startParts.count == 2, endParts.count == 2,
              let sh = Int(startParts[0]), let sm = Int(startParts[1]),
              let eh = Int(endParts[0]), let em = Int(endParts[1]) else {
            return nil
        }
        return (String(format: "%02d%02d", sh, sm), String(format: "%02d%02d", eh, em))
    }

    /// 去掉「（已结束）/(已结束)」标记、折叠空白
    static func normalizeExamName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "（已结束）", with: "")
            .replacingOccurrences(of: "(已结束)", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func uidHash(_ input: String) -> String {
        // sha1 hex 前 24 字符
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    /// 非 [A-Za-z0-9_一-鿿.] 替换为 _；空回退 calendar
    static func safeFileName(_ value: String, allowHyphen: Bool = false) -> String {
        let result = value.unicodeScalars.map { scalar -> Character in
            let allowed: Bool
            if scalar.isASCII {
                allowed = CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "_" || scalar == "."
                    || (allowHyphen && scalar == "-")
            } else {
                // CJK 统一表意文字 一(U+4E00)..鿿(U+9FFF)
                allowed = scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
            }
            return allowed ? Character(scalar) : "_"
        }
        let string = String(result)
        return string.isEmpty ? "calendar" : string
    }
}

import CryptoKit

// MARK: - 北京时间（对应 beijing_time.dart：固定 UTC+8，不依赖设备时区）

enum BeijingTime {
    static let timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    /// 北京日历日 y/m/d + h/m → UTC Date
    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = timeZone
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    /// utcTime 所在北京日 00:00 对应的 UTC 即时
    static func startOfDayUtc(of utcTime: Date) -> Date {
        let comps = Calendar(identifier: .gregorian).dateComponents(in: timeZone, from: utcTime)
        return date(year: comps.year!, month: comps.month!, day: comps.day!)
    }

    static func startOfTodayUtc() -> Date {
        startOfDayUtc(of: Date())
    }

    /// 北京日 bucket key（当日 00:00 的 Date）
    static func dayBucket(of utcTime: Date) -> Date {
        startOfDayUtc(of: utcTime)
    }

    /// 按北京时区格式化
    static func format(_ utcTime: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: utcTime)
    }
}
