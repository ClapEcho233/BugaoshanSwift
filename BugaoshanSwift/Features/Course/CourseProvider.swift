import Foundation
import Combine
import SwiftUI

/// 课表数据 Provider（对应 lib/providers/course_provider.dart）：
/// 本地 DB 读写，无认证依赖。配置/课程变更自动持久化。
@MainActor
final class CourseProvider: ObservableObject {

    // MARK: - 状态

    @Published private(set) var schedules: [ScheduleConfig] = []
    @Published private(set) var config: ScheduleConfig?
    @Published private(set) var courses: [Course] = []
    @Published var loadError: String?
    /// 首次加载是否完成：未完成前 UI 显示中性占位而非「导入课表」空态，
    /// 避免 tab 切换/首启时空态闪现
    @Published private(set) var hasLoaded = false

    private var database: DatabaseService
    private(set) var currentScheduleId = ""

    init(database: DatabaseService) {
        self.database = database
    }

    /// SwiftUI 视图在 init 期拿不到 environment 时的重新挂接
    func attach(database: DatabaseService) {
        self.database = database
    }

    var hasSchedule: Bool { config != nil }

    /// 当前教学周（按课表配置计算）
    var currentWeek: Int {
        config?.getCurrentWeek() ?? 1
    }

    // MARK: - 加载

    func reload() async {
        do {
            schedules = await database.getAllSchedules()
            config = await database.getScheduleConfig()
            currentScheduleId = await database.currentScheduleId
            courses = await database.getCourses()
            loadError = nil
            WidgetUpdateService.reloadTimelines()
        } catch {
            loadError = error.localizedDescription
        }
        hasLoaded = true
    }

    func switchSchedule(id: String) async {
        do {
            try await database.switchSchedule(id: id)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - 课程 CRUD

    func addCourse(_ course: Course) async -> Bool {
        do {
            var toAdd = course
            if toAdd.id.isEmpty {
                toAdd.id = Course.generateId()
            }
            try await database.addCourse(toAdd)
            await reload()
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    func updateCourse(_ course: Course) async -> Bool {
        do {
            try await database.updateCourse(course)
            await reload()
            return true
        } catch {
            loadError = error.localizedDescription
            return false
        }
    }

    func deleteCourse(id: String) async {
        do {
            try await database.deleteCourse(id: id)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func hasConflict(_ course: Course, excludeId: String? = nil) async -> Bool {
        await database.hasConflict(course, excludeId: excludeId)
    }

    // MARK: - 课表 CRUD

    func createSchedule(name: String, totalWeeks: Int = 20) async {
        var config = ScheduleConfig(id: String(Int(Date().timeIntervalSince1970 * 1000)))
        config.semesterName = name
        config.totalWeeks = totalWeeks
        do {
            try await database.addSchedule(config)
            try await database.switchSchedule(id: config.id)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func saveConfig(_ newConfig: ScheduleConfig) async {
        do {
            try await database.saveScheduleConfig(newConfig)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteSchedule(id: String) async {
        do {
            try await database.deleteSchedule(id: id)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - 导出（分享文件格式，也是跨 App 迁移路径）

    func exportCurrentSchedule() -> String? {
        guard let config else { return nil }
        struct Export: Codable {
            let config: ScheduleConfig
            let courses: [Course]
        }
        let export = Export(config: config, courses: courses)
        guard let data = try? JSONEncoder().encode(export) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 解析分享导入格式 {"config":…,"courses":[…]}（宽松）
    static func parseShareImport(_ jsonString: String) -> (ScheduleConfig, [Course])? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        struct Import: Codable {
            var config: ScheduleConfig?
            var courses: [Course]?
        }
        guard let importData = try? JSONDecoder().decode(Import.self, from: data),
              var config = importData.config else { return nil }
        // 新 id，避免覆盖
        config.id = String(Int(Date().timeIntervalSince1970 * 1000))
        return (config, importData.courses ?? [])
    }

    /// 导入（分享文件路径：regenerate 空/重复 id，自动套校区时间表）
    func importSchedule(config: inout ScheduleConfig, courses: [Course], nameConflictPolicy: @escaping (String) async -> ImportConflictResolution) async {
        ScheduleConfig.applyCampusTimeSlots(&config, courses: courses)
        // 同名课表冲突处理
        var targetId: String? = nil
        if let existing = schedules.first(where: { $0.semesterName == config.semesterName }) {
            switch await nameConflictPolicy(existing.semesterName) {
            case .cancel:
                return
            case .addWithSuffix:
                config.semesterName += "（新）"
            case .updateExisting(let id):
                targetId = id
            }
        }
        do {
            if let targetId {
                try await database.replaceScheduleCourses(scheduleId: targetId, courses: courses)
                try await database.saveScheduleConfig(config)
            } else {
                try await database.addSchedule(config)
                let newCourses = courses.map { $0.id.isEmpty ? $0.generatedId : $0 }
                try await database.replaceScheduleCourses(scheduleId: config.id, courses: newCourses)
            }
            try await database.switchSchedule(id: config.id)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

enum ImportConflictResolution {
    case cancel
    case addWithSuffix
    case updateExisting(String)
}
