import Foundation

// MARK: - 班级课表 / 课程课表模型（对应 class_schedule_inquiry_model.dart / course_curriculum_model.dart）

/// 学年学期筛选选项（value 如 "2026-2027-1-1"，label 如 "2026-2027学年秋"）
struct CurriculumSemesterOption: Identifiable, Equatable, Sendable {
    var id: String { value }
    var value: String
    var label: String
}

/// 院系筛选选项（value 如 "201"，name 如 "数学学院"）
struct DepartmentOption: Identifiable, Equatable, Sendable {
    var id: String { value }
    var value: String
    var name: String
}

/// 专业筛选选项（subjectJson）
struct SubjectOption: Identifiable, Equatable, Sendable {
    var id: String { code }
    var code: String
    var name: String

    static func fromJson(_ json: [String: Any]) -> SubjectOption {
        SubjectOption(
            code: SafeJSON.string(json["subjectCode"]),
            name: SafeJSON.string(json["subjectName"])
        )
    }
}

/// 班级筛选选项（classJson）
struct ClassOption: Identifiable, Equatable, Sendable {
    var id: String { code }
    var code: String
    var name: String

    static func fromJson(_ json: [String: Any]) -> ClassOption {
        ClassOption(
            code: SafeJSON.string(json["classCode"]),
            name: SafeJSON.string(json["className"])
        )
    }
}

/// 课程类别筛选选项（kclb 下拉）
struct CourseCategoryOption: Identifiable, Equatable, Sendable {
    var id: String { code }
    var code: String
    var name: String
}

/// 班级列表中的一个班级（classCurriculum/search 记录）
struct ClassInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(planCode)-\(classCode)" }
    var planCode: String        // executiveEducationPlanNumber
    var classCode: String       // classNum
    var planName: String        // executiveEducationPlanName
    var className: String
    var departmentName: String
    var subjectName: String

    static func fromJson(_ json: [String: Any]) -> ClassInfo {
        let id = json["id"] as? [String: Any] ?? [:]
        return ClassInfo(
            planCode: SafeJSON.string(id["executiveEducationPlanNumber"]),
            classCode: SafeJSON.string(id["classNum"]),
            planName: SafeJSON.string(json["executiveEducationPlanName"]),
            className: SafeJSON.string(json["className"]),
            departmentName: SafeJSON.string(json["departmentName"]),
            subjectName: SafeJSON.string(json["subjectName"])
        )
    }
}

/// 课表中的一门课程（班级/课程课表共用结构）
struct ClassScheduleInquiryItem: Equatable, Sendable {
    var dayOfWeek: Int      // skxq: 1-7
    var startPeriod: Int    // skjc: 开始节次
    var duration: Int       // cxjc: 持续节数
    var courseCode: String  // kch
    var courseSeq: String   // kxh
    var courseName: String  // kcm
    var teacherName: String // jsm
    var weeksDescription: String // zcsm
    var campus: String      // xqm
    var building: String    // jxlm
    var classroom: String   // jasm

    static func fromJson(_ json: [String: Any]) -> ClassScheduleInquiryItem {
        let id = json["id"] as? [String: Any] ?? [:]
        return ClassScheduleInquiryItem(
            dayOfWeek: SafeJSON.int(id["skxq"]),
            startPeriod: SafeJSON.int(id["skjc"]),
            duration: SafeJSON.int(json["cxjc"]),
            courseCode: SafeJSON.string(id["kch"]),
            courseSeq: SafeJSON.string(id["kxh"]),
            courseName: SafeJSON.string(json["kcm"]),
            teacherName: SafeJSON.string(json["jsm"]),
            weeksDescription: SafeJSON.string(json["zcsm"]),
            campus: SafeJSON.string(json["xqm"]),
            building: SafeJSON.string(json["jxlm"]),
            classroom: SafeJSON.string(json["jasm"])
        )
    }

    /// 转 Course 喂给 CourseGrid（location = 教学楼 + 教室）
    var toCourse: Course {
        let range = WeekParser.parseWeeks(weeksDescription)
        var course = Course()
        course.name = courseName
        course.teacher = teacherName
        course.location = [building, classroom].filter { !$0.isEmpty }.joined(separator: " ")
        course.startWeek = range.startWeek
        course.endWeek = range.endWeek
        course.dayOfWeek = dayOfWeek
        course.startSection = startPeriod
        course.endSection = startPeriod + duration - 1
        course.weekType = range.weekType
        course.colorValue = Self.stableColor(for: courseCode)
        return course
    }

    /// 按课程号稳定取色（与 Flutter 版 10 色板一致的语义）
    static func stableColor(for courseCode: String) -> Int {
        let palette: [Int] = [
            0xFF2196F3, 0xFF009688, 0xFFFF9800, 0xFF9C27B0, 0xFFE91E63,
            0xFF3F51B5, 0xFF4CAF50, 0xFFFF5722, 0xFF00BCD4, 0xFF795548,
        ]
        var hash = 5381
        for byte in courseCode.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ Int(byte) & 0x7fffffff
        }
        return palette[Int(hash & 0x7fffffff) % palette.count]
    }
}

/// 课程课表列表中的一个教学班
struct CourseSectionInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(planCode)-\(courseCode)-\(courseSeq)" }
    var planCode: String   // ZXJXJHH
    var planName: String   // ZXJXJHM
    var courseCode: String // KCH
    var courseName: String // KCM
    var courseSeq: String  // KXH
    var credits: String    // XF
    var category: String   // KCLBMC
    var examType: String   // KSLXMC
    var department: String // KKXSM
    var teachers: String   // JSM

    static func fromJson(_ json: [String: Any]) -> CourseSectionInfo {
        CourseSectionInfo(
            planCode: SafeJSON.string(json["ZXJXJHH"]),
            planName: SafeJSON.string(json["ZXJXJHM"]),
            courseCode: SafeJSON.string(json["KCH"]),
            courseName: SafeJSON.string(json["KCM"]),
            courseSeq: SafeJSON.string(json["KXH"]),
            credits: SafeJSON.string(json["XF"]),
            category: SafeJSON.string(json["KCLBMC"]),
            examType: SafeJSON.string(json["KSLXMC"]),
            department: SafeJSON.string(json["KKXSM"]),
            teachers: SafeJSON.string(json["JSM"])
        )
    }
}
