import Foundation

/// 教务导入解析器（对应 lib/pages/course/import/jwxt_parser.dart）
enum JwxtParser {

    struct ParseResult {
        var courses: [Course]
        /// 输入含周末课程（dayOfWeek ∈ {6,7}）→ 调用方自动开启「显示周末」
        var hasWeekend: Bool
        /// 建议的初始 ScheduleConfig（semesterStartDate = 本周一）
        var suggestedConfig: ScheduleConfig
    }

    /// Material primaries 调色板（ARGB，与 Dart 版颜色轮转一致）
    static let materialPrimaries: [Int] = [
        0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF673AB7,
        0xFF3F51B5, 0xFF2196F3, 0xFF03A9F4, 0xFF00BCD4,
        0xFF009688, 0xFF4CAF50, 0xFF8BC34A, 0xFFFFC107,
        0xFFFF9800, 0xFFFF5722, 0xFF795548, 0xFF607D8B,
    ]

    enum ParseError: Error, LocalizedError {
        case invalidJson(String)
        case invalidCourseRange(String)
        case invalidConfig

        var errorDescription: String? {
            switch self {
            case .invalidJson(let reason): return "教务数据解析失败：\(reason)"
            case .invalidCourseRange(let name): return "课程范围非法：\(name)"
            case .invalidConfig: return "Invalid schedule config"
            }
        }
    }

    /// 解析教务 xkxx JSON（教务处导出 / zhjw 在线接口同形状）
    static func parse(jsonString: String) throws -> ParseResult {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let xkxx = root["xkxx"] as? [[String: Any]] else {
            throw ParseError.invalidJson("缺少 xkxx 数组")
        }

        var courses: [Course] = []
        var colorIndex = 0
        for entry in xkxx {
            // 外层 map 每个 key 都是一门课（Dart courseMap.forEach 语义），逐个遍历
            for courseMapAny in entry.values {
            guard let courseMap = courseMapAny as? [String: Any] else { continue }
            let courseName = SafeJSON.string(courseMap["courseName"])
            let idMap = courseMap["id"] as? [String: Any]
            let sequenceNumber = SafeJSON.string(idMap?["coureSequenceNumber"])
            let teacher = SafeJSON.string(courseMap["attendClassTeacher"])
            let name = courseName.isEmpty ? "" : "\(courseName) (\(sequenceNumber))"

            guard let timeAndPlaceList = courseMap["timeAndPlaceList"] as? [[String: Any]] else {
                continue
            }

            var producedAny = false
            for tap in timeAndPlaceList {
                let dayOfWeek = SafeJSON.int(tap["classDay"])
                let startSection = SafeJSON.int(tap["classSessions"])
                let continuing = SafeJSON.int(tap["continuingSession"])
                let endSection = startSection + continuing - 1

                // 楼名/房间候选链
                let building = firstNonEmpty(
                    tap["teachingBuildingName"], tap["jxlm"], tap["building"])
                let room = firstNonEmpty(
                    tap["classroomName"], tap["jasm"], tap["classroom"])
                var location = building + room
                if location.isEmpty {
                    location = firstNonEmpty(
                        tap["customPlace"], tap["teachingPlace"], tap["place"], tap["skdd"])
                }
                let campus = SafeJSON.string(tap["campusName"])

                let classWeek = SafeJSON.string(tap["classWeek"])
                let segments = ClassWeekParser.parseSegments(classWeek)
                for segment in segments {
                    var course = Course()
                    course.id = Course.generateId()
                    course.name = name
                    course.teacher = teacher
                    course.location = location
                    course.campus = campus
                    course.dayOfWeek = dayOfWeek
                    course.startSection = startSection
                    course.endSection = max(endSection, startSection)
                    course.startWeek = segment.startWeek
                    course.endWeek = segment.endWeek
                    course.weekType = segment.weekType
                    course.colorValue = materialPrimaries[colorIndex % materialPrimaries.count]
                    courses.append(course)
                    producedAny = true
                }
            }
            if producedAny {
                colorIndex += 1
            }
            }
        }

        var config = ScheduleConfig()
        config.semesterStartDate = Date().dartMonday
        let hasWeekend = courses.contains { $0.dayOfWeek == 6 || $0.dayOfWeek == 7 }
        return ParseResult(courses: courses, hasWeekend: hasWeekend, suggestedConfig: config)
    }

    private static func firstNonEmpty(_ values: Any?...) -> String {
        for value in values {
            let string = SafeJSON.string(value)
            if !string.isEmpty {
                return string
            }
        }
        return ""
    }

    // MARK: - 校验（validateImportedSchedule）

    static func validate(config: ScheduleConfig, courses: [Course]) throws {
        if config.totalWeeks < 1 || config.timeSlots.isEmpty {
            throw ParseError.invalidConfig
        }
        for course in courses {
            if course.startWeek < 1 || course.endWeek < course.startWeek
                || course.endWeek > config.totalWeeks
                || course.dayOfWeek < 1 || course.dayOfWeek > 7
                || course.startSection < 1 || course.endSection < course.startSection
                || course.endSection > config.timeSlots.count {
                throw ParseError.invalidCourseRange(course.name)
            }
        }
    }

    /// 剥离「（当前）/(当前)」标记
    static func cleanSemesterLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "（当前）", with: "")
            .replacingOccurrences(of: "(当前)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
