import XCTest
@testable import BugaoshanSwift

/// 班级/课程课表模型解析
final class CurriculumTests: XCTestCase {

    func testClassInfoFromJson() {
        let info = ClassInfo.fromJson([
            "id": [
                "executiveEducationPlanNumber": "2026-2027-1-1",
                "classNum": "242010801",
            ],
            "executiveEducationPlanName": "2026-2027学年秋",
            "className": "数学2024-1班",
            "departmentName": "数学学院",
            "subjectName": "数学与应用数学",
        ])
        XCTAssertEqual(info.planCode, "2026-2027-1-1")
        XCTAssertEqual(info.classCode, "242010801")
        XCTAssertEqual(info.planName, "2026-2027学年秋")
        XCTAssertEqual(info.id, "2026-2027-1-1-242010801")
    }

    func testScheduleItemFromJsonAndToCourse() {
        let item = ClassScheduleInquiryItem.fromJson([
            "id": ["skxq": "3", "skjc": "2", "kch": "MATH101", "kxh": "01"],
            "cxjc": "2",
            "kcm": "高等数学",
            "jsm": "张三",
            "zcsm": "1-16(单)",
            "xqm": "江安",
            "jxlm": "一教",
            "jasm": "D101",
        ])
        XCTAssertEqual(item.dayOfWeek, 3)
        XCTAssertEqual(item.startPeriod, 2)
        XCTAssertEqual(item.duration, 2)
        XCTAssertEqual(item.weeksDescription, "1-16(单)")

        let course = item.toCourse
        XCTAssertEqual(course.name, "高等数学")
        XCTAssertEqual(course.teacher, "张三")
        XCTAssertEqual(course.location, "一教 D101")
        XCTAssertEqual(course.startWeek, 1)
        XCTAssertEqual(course.endWeek, 16)
        XCTAssertEqual(course.weekType, .odd)
        XCTAssertEqual(course.startSection, 2)
        XCTAssertEqual(course.endSection, 3)
        XCTAssertEqual(course.dayOfWeek, 3)
    }

    func testStableColorDeterministic() {
        let a = ClassScheduleInquiryItem.stableColor(for: "MATH101")
        let b = ClassScheduleInquiryItem.stableColor(for: "MATH101")
        XCTAssertEqual(a, b)
        // ARGB 不透明
        XCTAssertEqual(a >> 24, 0xFF)
    }

    func testCourseSectionFromJsonUppercaseKeys() {
        let section = CourseSectionInfo.fromJson([
            "ZXJXJHH": "2026-2027-1-1",
            "ZXJXJHM": "2026-2027学年秋",
            "KCH": "GEN001",
            "KCM": "新生研讨课",
            "KXH": "02",
            "XF": "1",
            "KCLBMC": "通识模块",
            "KSLXMC": "考查",
            "KKXSM": "数学学院",
            "JSM": "李四、王五",
        ])
        XCTAssertEqual(section.planCode, "2026-2027-1-1")
        XCTAssertEqual(section.courseCode, "GEN001")
        XCTAssertEqual(section.courseName, "新生研讨课")
        XCTAssertEqual(section.courseSeq, "02")
        XCTAssertEqual(section.teachers, "李四、王五")
        XCTAssertEqual(section.id, "2026-2027-1-1-GEN001-02")
    }

    func testSubjectAndClassOptions() {
        let subject = SubjectOption.fromJson(["subjectCode": "0701018", "subjectName": "数学双学士学位"])
        XCTAssertEqual(subject.code, "0701018")
        XCTAssertEqual(subject.name, "数学双学士学位")

        let classOption = ClassOption.fromJson(["classCode": "242010801", "className": "242010801"])
        XCTAssertEqual(classOption.code, "242010801")
    }
}
