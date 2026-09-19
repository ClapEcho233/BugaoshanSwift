import Foundation
import GRDB

/// 电费/水量余额采样记录
struct BalanceRecord: Equatable, Sendable {
    var id: Int64?
    var roomKey: String
    var balanceType: Int
    /// UTC 毫秒
    var timestamp: Int64
    var balance: Double
    var price: Double

    var date: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}

/// 本地数据库（对应 lib/services/database_service.dart）。
/// - schema 与 Flutter 版逐字一致（bugaoshan.db，v2，App Group 内）
/// - schedules 行 = ScheduleConfig JSON blob；courses 逐列；week_type 存枚举序号
/// - 内存缓存：currentScheduleId / schedules 全表 / 当前课表课程
actor DatabaseService {

    static let metadataKeyCurrentScheduleId = "currentScheduleId"
    static let dbFileName = "bugaoshan.db"

    private var dbQueue: DatabaseQueue?
    private(set) var currentScheduleId: String = ""
    private(set) var schedulesCache: [ScheduleConfig] = []
    private(set) var coursesCache: [Course] = []

    private let log: AuthLogger

    init(log: AuthLogger = .shared) {
        self.log = log
    }

    // MARK: - 打开

    /// App Group 容器（小组件共享）；失败回退 Application Support
    static func databaseURL() -> URL? {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupId) {
            let url = groupURL.appendingPathComponent(dbFileName)
            // 旧位置迁移（首次）：AppSupport 下存在且 Group 下不存在 → 复制
            let fm = FileManager.default
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let legacy = appSupport.appendingPathComponent(dbFileName)
                if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: url.path) {
                    try? fm.copyItem(at: legacy, to: url)
                }
            }
            return url
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(dbFileName)
    }

    func open() throws {
        guard dbQueue == nil else { return }
        guard let url = Self.databaseURL() else {
            throw SCUError.service("无法定位数据库目录")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = false   // 与 sqflite 默认一致，级联手动维护
        let queue = try DatabaseQueue(path: url.path, configuration: config)

        try queue.write { db in
            try Self.createTables(db)
        }
        dbQueue = queue
        try reloadCaches()
    }

    /// 测试用：临时路径打开
    func open(atPath path: String) throws {
        guard dbQueue == nil else { return }
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try Self.createTables(db)
        }
        dbQueue = queue
        try reloadCaches()
    }

    private static func createTables(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """)
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS schedules (
          id TEXT PRIMARY KEY,
          config_json TEXT NOT NULL
        )
        """)
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS courses (
          id TEXT PRIMARY KEY,
          schedule_id TEXT NOT NULL,
          name TEXT,
          teacher TEXT,
          location TEXT,
          campus TEXT NOT NULL DEFAULT '',
          start_week INTEGER,
          end_week INTEGER,
          day_of_week INTEGER,
          start_section INTEGER,
          end_section INTEGER,
          color_value INTEGER,
          week_type INTEGER,
          FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE CASCADE
        )
        """)
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS balance_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          room_key TEXT NOT NULL,
          balance_type INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          balance REAL NOT NULL,
          price REAL NOT NULL
        )
        """)
        try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_balance_records_lookup
        ON balance_records(room_key, balance_type, timestamp)
        """)
    }

    private func reloadCaches() throws {
        guard let dbQueue else { return }
        currentScheduleId = try dbQueue.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM metadata WHERE key = ?",
                arguments: [Self.metadataKeyCurrentScheduleId]
            ) ?? ""
        }
        schedulesCache = try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT config_json FROM schedules")
                .compactMap { ScheduleConfig.from(jsonString: $0) }
        }
        if !schedulesCache.isEmpty && !schedulesCache.contains(where: { $0.id == currentScheduleId }) {
            currentScheduleId = ""
        }
        coursesCache = currentScheduleId.isEmpty ? [] : try fetchCourses(scheduleId: currentScheduleId)
    }

    // MARK: - 课表

    func switchSchedule(id: String) throws {
        guard schedulesCache.contains(where: { $0.id == id }) else { return }
        currentScheduleId = id
        try dbQueue?.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)",
                arguments: [Self.metadataKeyCurrentScheduleId, id]
            )
        }
        coursesCache = try fetchCourses(scheduleId: id)
    }

    func getAllSchedules() -> [ScheduleConfig] {
        schedulesCache
    }

    /// 找不到当前 id 时回退第一个
    func getScheduleConfig() -> ScheduleConfig? {
        if let current = schedulesCache.first(where: { $0.id == currentScheduleId }) {
            return current
        }
        return schedulesCache.first
    }

    func saveScheduleConfig(_ config: ScheduleConfig) throws {
        guard let dbQueue else { return }
        let json = config.toJsonString()
        try dbQueue.write { db in
            let exists = try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM schedules WHERE id = ?)",
                arguments: [config.id]) ?? false
            if exists {
                try db.execute(
                    sql: "UPDATE schedules SET config_json = ? WHERE id = ?",
                    arguments: [json, config.id]
                )
            } else {
                try db.execute(
                    sql: "INSERT INTO schedules(id, config_json) VALUES (?, ?)",
                    arguments: [config.id, json]
                )
            }
        }
        if let index = schedulesCache.firstIndex(where: { $0.id == config.id }) {
            schedulesCache[index] = config
        } else {
            schedulesCache.append(config)
        }
    }

    func addSchedule(_ config: ScheduleConfig) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO schedules(id, config_json) VALUES (?, ?)",
                arguments: [config.id, config.toJsonString()]
            )
        }
        schedulesCache.append(config)
    }

    func deleteSchedule(id: String) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM courses WHERE schedule_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM schedules WHERE id = ?", arguments: [id])
        }
        schedulesCache.removeAll { $0.id == id }
        if currentScheduleId == id {
            if let first = schedulesCache.first {
                try switchSchedule(id: first.id)
            } else {
                currentScheduleId = ""
                try dbQueue.write { db in
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO metadata(key, value) VALUES (?, ?)",
                        arguments: [Self.metadataKeyCurrentScheduleId, ""]
                    )
                }
                coursesCache = []
            }
        }
    }

    // MARK: - 课程

    func getCourses(scheduleId: String? = nil) -> [Course] {
        guard let scheduleId else { return coursesCache }
        guard scheduleId == currentScheduleId else { return [] }
        return coursesCache
    }

    func getCoursesAsync(scheduleId: String) throws -> [Course] {
        try fetchCourses(scheduleId: scheduleId)
    }

    private func fetchCourses(scheduleId: String) throws -> [Course] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT * FROM courses WHERE schedule_id = ?",
                arguments: [scheduleId]
            )
            return rows.map(Self.course(fromRow:))
        }
    }

    func addCourse(_ course: Course) throws {
        guard let dbQueue, !currentScheduleId.isEmpty else { return }
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO courses(id, schedule_id, name, teacher, location, campus,
                    start_week, end_week, day_of_week, start_section, end_section,
                    color_value, week_type)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: Self.arguments(course: course, scheduleId: currentScheduleId)
            )
        }
        coursesCache = try fetchCourses(scheduleId: currentScheduleId)
    }

    /// 「更新课表」场景：整表替换
    func replaceScheduleCourses(scheduleId: String, courses: [Course]) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM courses WHERE schedule_id = ?", arguments: [scheduleId])
            for course in courses {
                try db.execute(
                    sql: """
                    INSERT INTO courses(id, schedule_id, name, teacher, location, campus,
                        start_week, end_week, day_of_week, start_section, end_section,
                        color_value, week_type)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: Self.arguments(course: course, scheduleId: scheduleId)
                )
            }
        }
        if scheduleId == currentScheduleId {
            coursesCache = try fetchCourses(scheduleId: scheduleId)
        }
    }

    func updateCourse(_ course: Course) throws {
        guard let dbQueue else { return }
        var values: [DatabaseValue] = []
        values.append(course.name.databaseValue)
        values.append(course.teacher.databaseValue)
        values.append(course.location.databaseValue)
        values.append(course.campus.databaseValue)
        values.append(course.startWeek.databaseValue)
        values.append(course.endWeek.databaseValue)
        values.append(course.dayOfWeek.databaseValue)
        values.append(course.startSection.databaseValue)
        values.append(course.endSection.databaseValue)
        values.append(course.colorValue.databaseValue)
        values.append(course.weekType.rawValue.databaseValue)
        values.append(course.id.databaseValue)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE courses SET name = ?, teacher = ?, location = ?, campus = ?,
                    start_week = ?, end_week = ?, day_of_week = ?, start_section = ?,
                    end_section = ?, color_value = ?, week_type = ?
                WHERE id = ?
                """,
                arguments: StatementArguments(values)
            )
        }
        if !course.id.isEmpty, !currentScheduleId.isEmpty,
           coursesCache.contains(where: { $0.id == course.id }) {
            coursesCache = try fetchCourses(scheduleId: currentScheduleId)
        }
    }

    func deleteCourse(id: String) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM courses WHERE id = ?", arguments: [id])
        }
        coursesCache.removeAll { $0.id == id }
    }

    /// 纯内存：缓存任一课程冲突
    func hasConflict(_ course: Course, excludeId: String? = nil) -> Bool {
        coursesCache.contains { $0.conflicts(with: course, excludeId: excludeId) }
    }

    /// 危险区：清空全部课表数据
    func clearAllCourseData() throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM courses")
            try db.execute(sql: "DELETE FROM schedules")
            try db.execute(sql: "DELETE FROM metadata")
        }
        schedulesCache = []
        coursesCache = []
        currentScheduleId = ""
    }

    // MARK: - 余额记录

    @discardableResult
    func insertBalanceRecord(_ record: BalanceRecord) throws -> Int64 {
        guard let dbQueue else { return 0 }
        return try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO balance_records(room_key, balance_type, timestamp, balance, price)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [record.roomKey, record.balanceType, record.timestamp, record.balance, record.price]
            )
            return db.lastInsertedRowID
        }
    }

    func getBalanceRecords(
        roomKey: String, balanceType: Int,
        since: Int64? = nil, until: Int64? = nil
    ) throws -> [BalanceRecord] {
        guard let dbQueue else { return [] }
        var sql = """
        SELECT * FROM balance_records
        WHERE room_key = ? AND balance_type = ?
        """
        var args: [DatabaseValue] = [roomKey.databaseValue, balanceType.databaseValue]
        if let since {
            sql += " AND timestamp >= ?"
            args.append(since.databaseValue)
        }
        if let until {
            sql += " AND timestamp <= ?"
            args.append(until.databaseValue)
        }
        sql += " ORDER BY timestamp ASC"
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
                .map { row in
                    BalanceRecord(
                        id: row["id"],
                        roomKey: row["room_key"],
                        balanceType: row["balance_type"],
                        timestamp: row["timestamp"],
                        balance: row["balance"],
                        price: row["price"]
                    )
                }
        }
    }

    func deleteBalanceRecordsBefore(threshold: Int64) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM balance_records WHERE timestamp < ?", arguments: [threshold])
        }
    }

    func deleteBalanceRecordsByRoom(roomKey: String) throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM balance_records WHERE room_key = ?", arguments: [roomKey])
        }
    }

    // MARK: - 行映射

    private static func arguments(course: Course, scheduleId: String) -> StatementArguments {
        var values: [DatabaseValue] = []
        values.append(course.id.databaseValue)
        values.append(scheduleId.databaseValue)
        values.append(course.name.databaseValue)
        values.append(course.teacher.databaseValue)
        values.append(course.location.databaseValue)
        values.append(course.campus.databaseValue)
        values.append(course.startWeek.databaseValue)
        values.append(course.endWeek.databaseValue)
        values.append(course.dayOfWeek.databaseValue)
        values.append(course.startSection.databaseValue)
        values.append(course.endSection.databaseValue)
        values.append(course.colorValue.databaseValue)
        values.append(course.weekType.rawValue.databaseValue)
        return StatementArguments(values)
    }

    private static func course(fromRow row: Row) -> Course {
        var course = Course()
        course.id = (row["id"] as String?) ?? ""
        course.name = (row["name"] as String?) ?? ""
        course.teacher = (row["teacher"] as String?) ?? ""
        course.location = (row["location"] as String?) ?? ""
        course.campus = (row["campus"] as String?) ?? ""
        course.startWeek = (row["start_week"] as Int?) ?? 1
        course.endWeek = (row["end_week"] as Int?) ?? Course.defaultTotalWeeks
        course.dayOfWeek = (row["day_of_week"] as Int?) ?? 1
        course.startSection = (row["start_section"] as Int?) ?? 1
        course.endSection = (row["end_section"] as Int?) ?? 1
        course.colorValue = (row["color_value"] as Int?) ?? 0xFF2196F3
        let weekTypeRaw = (row["week_type"] as Int?) ?? 0
        course.weekType = WeekType(rawValue: weekTypeRaw) ?? .every
        return course
    }
}

// MARK: - ScheduleConfig JSON 便捷

extension ScheduleConfig {
    func toJsonString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func from(jsonString: String) -> ScheduleConfig? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ScheduleConfig.self, from: data)
    }
}
