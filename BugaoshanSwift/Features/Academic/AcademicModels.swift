import Foundation

// MARK: - 空闲教室模型（对应 classroom_model.dart）

enum ClassroomPeriodStatus: Equatable, Sendable {
    case free, inClass, exam, experiment, borrowed

    var label: String {
        switch self {
        case .free: return "空闲"
        case .inClass: return "上课"
        case .exam: return "考试"
        case .experiment: return "实验"
        case .borrowed: return "借用"
        }
    }
}

struct ClassroomCampus: Equatable, Sendable {
    var campusName: String
    var campusNumber: String
}

struct ClassroomBuilding: Identifiable, Equatable, Sendable {
    var id: String { "\(campusNumber)-\(teachingBuildingNumber)" }
    var campusNumber: String
    var teachingBuildingNumber: String
    var teachingBuildingName: String
}

struct ClassroomType: Equatable, Sendable {
    var code: String
    var name: String
}

struct ClassroomInfo: Identifiable, Equatable, Sendable {
    var id: String { "\(campusNumber)-\(teachingBuildingNumber)-\(classroomNumber)" }
    var classroomName: String
    var classroomStatusCode: String
    var classroomTypeCode: String
    var campusNumber: String
    var classroomNumber: String
    var teachingBuildingNumber: String
    var placeNum: Int
    var remark: String
    var sfkjy: String

    static func fromJson(_ json: [String: Any]) -> ClassroomInfo {
        let id = json["id"] as? [String: Any] ?? [:]
        return ClassroomInfo(
            classroomName: SafeJSON.string(json["classroomName"]),
            classroomStatusCode: SafeJSON.string(json["classroomStatusCode"]),
            classroomTypeCode: SafeJSON.string(json["classroomTypeCode"]),
            campusNumber: SafeJSON.string(id["campusNumber"]),
            classroomNumber: SafeJSON.string(id["classroomNumber"]),
            teachingBuildingNumber: SafeJSON.string(id["teachingBuildingNumber"]),
            placeNum: SafeJSON.int(json["placeNum"]),
            remark: SafeJSON.string(json["remark"]),
            sfkjy: SafeJSON.string(json["sfkjy"])
        )
    }
}

struct ClassroomTimeSlot: Equatable, Sendable {
    var classroomNumber: String
    var dayOfWeek: Int
    var sessionStart: Int
    var continuingSession: Int
    var occupancymoduleId: String

    var status: ClassroomPeriodStatus {
        switch occupancymoduleId {
        case "06": return .inClass
        case "07": return .exam
        case "14": return .experiment
        case "room": return .borrowed
        default: return .free
        }
    }

    static func fromJson(_ json: [String: Any]) -> ClassroomTimeSlot {
        let id = json["id"] as? [String: Any] ?? [:]
        return ClassroomTimeSlot(
            classroomNumber: SafeJSON.string(id["classroomNumber"]),
            dayOfWeek: SafeJSON.int(id["xq"]),
            sessionStart: SafeJSON.int(id["sessionstart"]),
            continuingSession: SafeJSON.int(json["continuingsession"], fallback: 1),
            occupancymoduleId: SafeJSON.string(json["occupancymoduleId"])
        )
    }
}

struct ClassroomQueryResult: Equatable, Sendable {
    var classrooms: [ClassroomInfo]
    var classroomTime: [ClassroomTimeSlot]
    var date: String
    var jxzc: Int

    static func fromJson(_ json: [String: Any]) -> ClassroomQueryResult {
        ClassroomQueryResult(
            classrooms: (json["classrooms"] as? [[String: Any]] ?? []).map(ClassroomInfo.fromJson),
            classroomTime: (json["classroomTime"] as? [[String: Any]] ?? []).map(ClassroomTimeSlot.fromJson),
            date: SafeJSON.string(json["date"]),
            jxzc: SafeJSON.int(json["jxzc"])
        )
    }

    func slotsFor(classroomNumber: String) -> [ClassroomTimeSlot] {
        classroomTime.filter { $0.classroomNumber == classroomNumber }
    }

    /// 节次 → 状态（展开连续节次占用）
    func periodStatusMap(classroomNumber: String) -> [Int: ClassroomPeriodStatus] {
        var map: [Int: ClassroomPeriodStatus] = [:]
        for slot in slotsFor(classroomNumber: classroomNumber) where slot.status != .free {
            for section in slot.sessionStart..<(slot.sessionStart + slot.continuingSession) {
                map[section] = slot.status
            }
        }
        return map
    }
}

// MARK: - 培养方案模型（对应 train_program.dart）

struct TrainProgram: Identifiable, Equatable, Sendable {
    var id: String { fajhh }
    var fajhh: String    // 方案计划号
    var nj: String       // 年级
    var xsh: String      // 学院号
    var famc: String     // 方案名称
    var jhmc: String     // 计划名称
    var xwdm: String     // 学位代码
    var xdlx: String     // 学点类型

    static func fromJson(_ json: [String: Any]) -> TrainProgram {
        TrainProgram(
            fajhh: SafeJSON.string(json["fajhh"]),
            nj: SafeJSON.string(json["nj"]),
            xsh: SafeJSON.string(json["xsh"]),
            famc: SafeJSON.string(json["famc"]),
            jhmc: SafeJSON.string(json["jhmc"]),
            xwdm: SafeJSON.string(json["xwdm"]),
            xdlx: SafeJSON.string(json["xdlx"])
        )
    }
}

struct TrainProgramCourse: Identifiable, Equatable, Sendable {
    var id: String { "\(kch)-\(kxh)" }
    var kch: String
    var kcm: String
    var kxh: String
    var xf: String
    var zxs: String
    var khfs: String   // 考核方式
    var kcgsdmName: String
    var xqm: String

    static func fromJson(_ json: [String: Any]) -> TrainProgramCourse {
        TrainProgramCourse(
            kch: SafeJSON.string(json["kch"]),
            kcm: SafeJSON.string(json["kcm"]),
            kxh: SafeJSON.string(json["kxh"]),
            xf: SafeJSON.string(json["xf"]),
            zxs: SafeJSON.string(json["zxs"]),
            khfs: SafeJSON.string(json["khfs"]),
            kcgsdmName: SafeJSON.string(json["kcgsdmName"] ?? json["kclbdmName"]),
            xqm: SafeJSON.string(json["xqm"])
        )
    }
}

struct College: Identifiable, Equatable, Sendable {
    var id: String { value }
    var value: String
    var name: String
}

struct Grade: Identifiable, Equatable, Sendable {
    var id: String { value }
    var value: String
    var label: String
}
