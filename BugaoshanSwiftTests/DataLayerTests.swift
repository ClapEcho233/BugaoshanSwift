import Foundation
import XCTest
@testable import BugaoshanSwift

/// 数据层测试：Course 冲突/周界、ScheduleConfig 兼容解析、周次解析、数据库 CRUD。
final class DataLayerTests: XCTestCase {

    // MARK: - WeekParser

    func testParseWeeks() {
        var r = WeekParser.parseWeeks("1-10周")
        XCTAssertEqual(r, WeekParser.WeekRange(startWeek: 1, endWeek: 10, weekType: .every))
        r = WeekParser.parseWeeks("1-10,12周")
        XCTAssertEqual(r.startWeek, 1)
        XCTAssertEqual(r.endWeek, 12)
        r = WeekParser.parseWeeks("1-16(单)")
        XCTAssertEqual(r.weekType, .odd)
        XCTAssertEqual(r.startWeek, 1)
        XCTAssertEqual(r.endWeek, 16)
        r = WeekParser.parseWeeks("1-16(双)")
        XCTAssertEqual(r.weekType, .even)
        r = WeekParser.parseWeeks("第16周")
        XCTAssertEqual(r.startWeek, 16)
        XCTAssertEqual(r.endWeek, 16)
        r = WeekParser.parseWeeks("")
        XCTAssertEqual(r, WeekParser.WeekRange(startWeek: 1, endWeek: 20, weekType: .every))
    }

    func testParseClassWeekSegments() {
        // 交替序列 → 单个 odd 区间
        var segs = ClassWeekParser.parseSegments("1010101010101010")
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].weekType, .odd)
        XCTAssertEqual(segs[0].startWeek, 1)
        XCTAssertEqual(segs[0].endWeek, 15)

        // 偶数周交替 → even
        segs = ClassWeekParser.parseSegments("0101010101010101")
        XCTAssertEqual(segs[0].weekType, .even)
        XCTAssertEqual(segs[0].startWeek, 2)

        // 连续 + 缺口 → 两个 every 段
        segs = ClassWeekParser.parseSegments("111111101111111")
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0], WeekParser.WeekRange(startWeek: 1, endWeek: 7, weekType: .every))
        XCTAssertEqual(segs[1], WeekParser.WeekRange(startWeek: 9, endWeek: 15, weekType: .every))

        // 全空 → []
        XCTAssertTrue(ClassWeekParser.parseSegments("0000").isEmpty)
        XCTAssertTrue(ClassWeekParser.parseSegments("").isEmpty)
    }

    // MARK: - Course

    func testCourseActiveInWeek() {
        let course = Course(
            id: "1", name: "测试", teacher: "", location: "", campus: "",
            startWeek: 2, endWeek: 10, dayOfWeek: 3,
            startSection: 1, endSection: 2,
            colorValue: 0, weekType: .odd
        )
        XCTAssertFalse(course.isActive(inWeek: 1))
        XCTAssertTrue(course.isActive(inWeek: 3))
        XCTAssertFalse(course.isActive(inWeek: 4))
        XCTAssertFalse(course.isActive(inWeek: 11))
    }

    func testCourseConflicts() {
        let base = Course(
            id: "a", name: "A", teacher: "", location: "", campus: "",
            startWeek: 1, endWeek: 16, dayOfWeek: 1,
            startSection: 1, endSection: 2, colorValue: 0, weekType: .every
        )
        // 同天同节 → 冲突
        let same = base.with(id: "b")
        XCTAssertTrue(base.conflicts(with: same))
        // 不同天 → 不冲突
        var otherDay = base.with(id: "c")
        otherDay.dayOfWeek = 2
        XCTAssertFalse(base.conflicts(with: otherDay))
        // 节次错开 → 不冲突
        var later = base.with(id: "d")
        later.startSection = 3
        later.endSection = 4
        XCTAssertFalse(base.conflicts(with: later))
        // 周不重叠 → 不冲突
        var nextSemester = base.with(id: "e")
        nextSemester.startWeek = 20
        nextSemester.endWeek = 22
        XCTAssertFalse(base.conflicts(with: nextSemester))
        // 单双周互斥 → 不冲突
        var odd = base.with(id: "f")
        odd.weekType = .odd
        var even = base.with(id: "g")
        even.weekType = .even
        XCTAssertFalse(odd.conflicts(with: even))
        // excludeId
        XCTAssertFalse(base.conflicts(with: base.with(id: "b"), excludeId: "b"))
    }

    // MARK: - ScheduleConfig 周计算（周日语义）

    func testGetCurrentWeek() {
        var config = ScheduleConfig()
        // 2026-09-14 是周一
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-14")!
        XCTAssertEqual(config.getCurrentWeek(from: ScheduleConfig.parseDate("2026-09-14")!), 1)
        XCTAssertEqual(config.getCurrentWeek(from: ScheduleConfig.parseDate("2026-09-20")!), 1)  // 周日仍在第 1 周
        XCTAssertEqual(config.getCurrentWeek(from: ScheduleConfig.parseDate("2026-09-21")!), 2)
        XCTAssertEqual(config.getCurrentWeek(from: ScheduleConfig.parseDate("2026-12-28")!), 16)
        // 学期前 → 1
        XCTAssertEqual(config.getCurrentWeek(from: ScheduleConfig.parseDate("2026-09-01")!), 1)
    }

    /// 起点为周日（2026-09-13 周日）：周日属于第 1 教学周
    func testSundayStartSemester() {
        var config = ScheduleConfig()
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-13")!
        // 第 1 周的周一 = 9-14
        let monday = config.dateForCourseDay(week: 1, dayOfWeek: 1)
        XCTAssertEqual(ScheduleConfig.formatDate(monday), "2026-09-14")
        // 第 1 周的周日 = 9-13（起点当天）
        let sunday = config.dateForCourseDay(week: 1, dayOfWeek: 7)
        XCTAssertEqual(ScheduleConfig.formatDate(sunday), "2026-09-13")
        // 第 2 周的周日 = 9-20
        let sunday2 = config.dateForCourseDay(week: 2, dayOfWeek: 7)
        XCTAssertEqual(ScheduleConfig.formatDate(sunday2), "2026-09-20")
    }

    /// 起点为周一：周日挂在同一教学周（= 本周周一前一天）
    func testMondayStartSemester() {
        var config = ScheduleConfig()
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-14")!
        let sunday = config.dateForCourseDay(week: 1, dayOfWeek: 7)
        XCTAssertEqual(ScheduleConfig.formatDate(sunday), "2026-09-13")
        let wednesday = config.dateForCourseDay(week: 3, dayOfWeek: 3)
        XCTAssertEqual(ScheduleConfig.formatDate(wednesday), "2026-09-30")
    }

    // MARK: - ScheduleConfig JSON 兼容

    func testScheduleConfigRoundTrip() throws {
        var config = ScheduleConfig()
        config.id = "s1"
        config.semesterName = "2026-2027学年秋季学期"
        config.semesterStartDate = ScheduleConfig.parseDate("2026-09-14")!
        config.totalWeeks = 18
        let json = config.toJsonString()
        let decoded = try XCTUnwrap(ScheduleConfig.from(jsonString: json))
        XCTAssertEqual(decoded.id, "s1")
        XCTAssertEqual(decoded.semesterName, "2026-2027学年秋季学期")
        XCTAssertEqual(ScheduleConfig.formatDate(decoded.semesterStartDate), "2026-09-14")
        XCTAssertEqual(decoded.totalWeeks, 18)
        XCTAssertEqual(decoded.timeSlots, config.timeSlots)
    }

    func testScheduleConfigLegacyCompat() throws {
        // 旧格式：semesterEndDate + sectionsPerDay
        let legacy = """
        {"id":"old","semesterName":"旧","semesterStartDate":"2025-09-01",
         "semesterEndDate":"2026-01-11","sectionsPerDay":12,
         "courseDuration":45,"breakDuration":10,"autoSyncTime":true}
        """
        let decoded = try XCTUnwrap(ScheduleConfig.from(jsonString: legacy))
        // 2025-09-01 → 2026-01-11 = 132 天 = 19 周差 5 天 → ceil = 19
        XCTAssertEqual(decoded.totalWeeks, 19)
        XCTAssertEqual(decoded.morningSections, 4)
        XCTAssertEqual(decoded.afternoonSections, 5)
        XCTAssertEqual(decoded.eveningSections, 3)
        XCTAssertEqual(decoded.timeSlots.count, 12)
    }

    func testCampusPresetsAndDominant() {
        XCTAssertEqual(ScheduleConfig.jiangAnTimeSlots.count, 12)
        XCTAssertEqual(ScheduleConfig.wangJiangHuaXiTimeSlots.count, 12)
        XCTAssertTrue(ScheduleConfig.isPresetTimeSlots(ScheduleConfig.jiangAnTimeSlots))
        XCTAssertFalse(ScheduleConfig.isPresetTimeSlots([]))

        let courses = [
            Course(id: "1", name: "高数", teacher: "", location: "江安 一教", campus: "江安校区",
                   startWeek: 1, endWeek: 16, dayOfWeek: 1, startSection: 1, endSection: 2, colorValue: 0, weekType: .every),
            Course(id: "2", name: "高数", teacher: "", location: "江安 一教", campus: "江安校区",
                   startWeek: 1, endWeek: 16, dayOfWeek: 3, startSection: 1, endSection: 2, colorValue: 0, weekType: .every),
            Course(id: "3", name: "英语", teacher: "", location: "望江 东区", campus: "",
                   startWeek: 1, endWeek: 16, dayOfWeek: 5, startSection: 1, endSection: 2, colorValue: 0, weekType: .every),
        ]
        // 高数去重后只算一次 → 江安 1 : 望江 1 并列 → nil
        XCTAssertNil(ScheduleConfig.dominantCampus(ofCourses: courses))
        let moreJiangAn = courses + [
            Course(id: "4", name: "体育", teacher: "", location: "江安 体院", campus: "",
                   startWeek: 1, endWeek: 16, dayOfWeek: 2, startSection: 3, endSection: 4, colorValue: 0, weekType: .every),
        ]
        XCTAssertEqual(ScheduleConfig.dominantCampus(ofCourses: moreJiangAn), "江安")

        var config = ScheduleConfig()
        ScheduleConfig.applyCampusTimeSlots(&config, courses: moreJiangAn)
        XCTAssertEqual(config.timeSlots, ScheduleConfig.jiangAnTimeSlots)
    }

    // MARK: - AcademicCalendar

    func testAcademicCalendarSemester() {
        let semester = AcademicCalendarSemester(
            name: "2026-2027学年秋季学期",
            startDate: ScheduleConfig.parseDate("2026-09-14")!,
            totalWeeks: 18
        )
        XCTAssertEqual(semester.getCurrentWeek(on: ScheduleConfig.parseDate("2026-09-14")!), 1)
        XCTAssertEqual(semester.getCurrentWeek(on: ScheduleConfig.parseDate("2027-01-17")!), 18)
        XCTAssertNil(semester.getCurrentWeek(on: ScheduleConfig.parseDate("2027-01-18")!))
        XCTAssertNil(semester.getCurrentWeek(on: ScheduleConfig.parseDate("2026-09-01")!))
        // endDate = start + 18*7 - 1
        XCTAssertEqual(ScheduleConfig.formatDate(semester.endDate), "2027-01-17")
    }

    func testAcademicCalendarJsonRoundTrip() throws {
        let json = """
        {"semesters":[{"name":"2026-2027学年秋季学期","startDate":"2026-09-14","totalWeeks":18,
          "events":[{"date":"2026-10-01","endDate":"2026-10-07","label":"国庆节假期","tag":"holiday"}]}]}
        """
        let data = try XCTUnwrap(AcademicCalendarData.from(jsonString: json))
        XCTAssertEqual(data.semesters.count, 1)
        XCTAssertEqual(data.semesters[0].events[0].label, "国庆节假期")
        XCTAssertTrue(data.semesters[0].events[0].isActive(on: ScheduleConfig.parseDate("2026-10-03")!))
    }

    // MARK: - DatabaseService

    func testDatabaseCrud() async throws {
        let service = DatabaseService()
        let tmp = NSTemporaryDirectory() + "test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try await service.open(atPath: tmp)

        // 新安装：无课表，currentScheduleId 为空
        let empty = await service.getAllSchedules()
        XCTAssertTrue(empty.isEmpty)
        let currentNil = await service.getScheduleConfig()
        XCTAssertNil(currentNil)

        // 建两个课表
        var s1 = ScheduleConfig()
        s1.id = "s1"
        s1.semesterName = "学期一"
        try await service.addSchedule(s1)
        var s2 = ScheduleConfig()
        s2.id = "s2"
        try await service.addSchedule(s2)

        try await service.switchSchedule(id: "s1")
        let currentId = await service.currentScheduleId
        XCTAssertEqual(currentId, "s1")

        // 加课程
        let course = Course(
            id: Course.generateId(), name: "高数(1)", teacher: "张三", location: "一教B101",
            campus: "江安校区", startWeek: 1, endWeek: 16, dayOfWeek: 1,
            startSection: 1, endSection: 2, colorValue: 0xFF2196F3, weekType: .every
        )
        try await service.addCourse(course)
        var courses = await service.getCourses()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].campus, "江安校区")

        // 冲突检测
        let conflicting = course.with(id: Course.generateId())
        let hasConflict = await service.hasConflict(conflicting)
        XCTAssertTrue(hasConflict)
        // excludeId（更新自身不冲突）
        let selfConflict = await service.hasConflict(courses[0], excludeId: courses[0].id)
        XCTAssertFalse(selfConflict)

        // 更新课程
        var updated = courses[0]
        updated.location = "二教C202"
        try await service.updateCourse(updated)
        courses = await service.getCourses()
        XCTAssertEqual(courses[0].location, "二教C202")

        // 整表替换
        try await service.replaceScheduleCourses(scheduleId: "s1", courses: [course, course.with(id: "x2")])
        courses = await service.getCourses()
        XCTAssertEqual(courses.count, 2)

        // 切换课表 → 当前课程缓存切换
        try await service.switchSchedule(id: "s2")
        courses = await service.getCourses()
        XCTAssertTrue(courses.isEmpty)
        // 跨课表读取
        let cross = try await service.getCoursesAsync(scheduleId: "s1")
        XCTAssertEqual(cross.count, 2)

        // 删除当前课表 → 自动切到剩余第一个
        try await service.deleteSchedule(id: "s2")
        let afterDelete = await service.currentScheduleId
        XCTAssertEqual(afterDelete, "s1")

        // 清空
        try await service.clearAllCourseData()
        let afterClear = await service.getAllSchedules()
        XCTAssertTrue(afterClear.isEmpty)
    }

    func testBalanceRecords() async throws {
        let service = DatabaseService()
        let tmp = NSTemporaryDirectory() + "test-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        try await service.open(atPath: tmp)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        try await service.insertBalanceRecord(BalanceRecord(
            id: nil, roomKey: "room1", balanceType: 0, timestamp: now - 1000, balance: 12.5, price: 0.55))
        try await service.insertBalanceRecord(BalanceRecord(
            id: nil, roomKey: "room1", balanceType: 0, timestamp: now, balance: 11.8, price: 0.55))
        try await service.insertBalanceRecord(BalanceRecord(
            id: nil, roomKey: "room2", balanceType: 0, timestamp: now, balance: 5.0, price: 0.55))

        let room1 = try await service.getBalanceRecords(roomKey: "room1", balanceType: 0)
        XCTAssertEqual(room1.count, 2)
        XCTAssertEqual(room1[0].balance, 12.5)  // ASC 排序

        let since = try await service.getBalanceRecords(roomKey: "room1", balanceType: 0, since: now - 500)
        XCTAssertEqual(since.count, 1)

        try await service.deleteBalanceRecordsBefore(threshold: now - 500)
        let afterDelete = try await service.getBalanceRecords(roomKey: "room1", balanceType: 0)
        XCTAssertEqual(afterDelete.count, 1)

        try await service.deleteBalanceRecordsByRoom(roomKey: "room1")
        let afterRoomDelete = try await service.getBalanceRecords(roomKey: "room1", balanceType: 0)
        XCTAssertTrue(afterRoomDelete.isEmpty)
    }
}

// MARK: - 测试辅助

extension Course {
    func with(id: String) -> Course {
        var copy = self
        copy.id = id
        return copy
    }
}
