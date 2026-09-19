import Foundation

// MARK: - 第二课堂数据模型（ccyl_models.dart）

struct CyclActivity: Identifiable, Equatable, Sendable {
    var id: String { activityId ?? activityLibraryId }
    var activityId: String?
    var activityLibraryId: String
    var orgNo: String
    var name: String
    var activityName: String
    var level: String
    var star: String
    var quality: [String]
    var classHour: Double
    var describe: String?
    var poster: String
    var startTime: String?
    var endTime: String?
    var enrollStartTime: String?
    var enrollEndTime: String?
    var quota: Int
    var activityTarget: String
    var activityTargetName: String?
    var isSignIn: String
    var isSignOut: String
    var mobile: String?
    var activityAddress: String?
    var activityLon: String?
    var activityLat: String?
    var status: String
    var statusName: String?
    var orgName: String
    var levelName: String?
    var starName: String?
    var qualityName: String?
    var doing: Bool
    var subscribed: Bool

    /// 状态展示：进行中 / 已结束
    var statusText: String { doing ? "进行中" : "已结束" }

    static func fromJson(_ json: [String: Any]) -> CyclActivity {
        CyclActivity(
            activityId: json["activityId"].map { SafeJSON.string($0, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 },
            activityLibraryId: SafeJSON.string(json["activityLibraryId"]),
            orgNo: SafeJSON.string(json["orgNo"]),
            name: SafeJSON.string(json["name"]),
            activityName: SafeJSON.string(json["activityName"]),
            level: SafeJSON.string(json["level"]),
            star: SafeJSON.string(json["star"]),
            quality: (json["quality"] as? [Any])?.map { SafeJSON.string($0, fallback: "") } ?? [],
            classHour: SafeJSON.double(json["classHour"]),
            describe: json["describe"].map { SafeJSON.string($0, fallback: "") },
            poster: SafeJSON.string(json["poster"]),
            startTime: json["startTime"].map { SafeJSON.string($0, fallback: "") },
            endTime: json["endTime"].map { SafeJSON.string($0, fallback: "") },
            enrollStartTime: json["enrollStartTime"].map { SafeJSON.string($0, fallback: "") },
            enrollEndTime: json["enrollEndTime"].map { SafeJSON.string($0, fallback: "") },
            quota: SafeJSON.int(json["quota"]),
            activityTarget: SafeJSON.string(json["activityTarget"]),
            activityTargetName: json["activityTargetName"].map { SafeJSON.string($0, fallback: "") },
            isSignIn: SafeJSON.string(json["isSignIn"], fallback: "0"),
            isSignOut: SafeJSON.string(json["isSignOut"], fallback: "0"),
            mobile: json["mobile"].map { SafeJSON.string($0, fallback: "") },
            activityAddress: json["activityAddress"].map { SafeJSON.string($0, fallback: "") },
            activityLon: json["activityLon"].map { SafeJSON.string($0, fallback: "") },
            activityLat: json["activityLat"].map { SafeJSON.string($0, fallback: "") },
            status: SafeJSON.string(json["status"]),
            statusName: json["statusName"].map { SafeJSON.string($0, fallback: "") },
            orgName: SafeJSON.string(json["orgName"]),
            levelName: json["levelName"].map { SafeJSON.string($0, fallback: "") },
            starName: json["starName"].map { SafeJSON.string($0, fallback: "") },
            qualityName: json["qualityName"].map { SafeJSON.string($0, fallback: "") },
            doing: json["doing"] as? Bool == true,
            subscribed: json["subscribed"] as? Bool == true
        )
    }
}

struct CyclOrg: Identifiable, Equatable, Sendable {
    var id: String { orgNo }
    var orgNo: String
    var orgName: String
    var parentNo: String?

    static func fromJson(_ json: [String: Any]) -> CyclOrg {
        CyclOrg(
            orgNo: SafeJSON.string(json["orgNo"]),
            orgName: SafeJSON.string(json["orgName"]),
            parentNo: json["parentNo"].map { SafeJSON.string($0, fallback: "") }
        )
    }
}

struct CyclScoreType: Identifiable, Equatable, Sendable {
    var id: String { "\(name)-\(value)" }
    var scoreTypeId: String?
    var groupId: String?
    var name: String
    var value: String
    var code: String?

    static func fromJson(_ json: [String: Any]) -> CyclScoreType {
        CyclScoreType(
            scoreTypeId: json["id"].map { SafeJSON.string($0, fallback: "") },
            groupId: json["groupId"].map { SafeJSON.string($0, fallback: "") },
            name: SafeJSON.string(json["name"]),
            value: SafeJSON.string(json["value"]),
            code: json["code"].map { SafeJSON.string($0, fallback: "") }
        )
    }
}

struct CyclDict: Identifiable, Equatable, Sendable {
    var id: String { code }
    var code: String
    var name: String
    var groupCode: String?

    static func fromJson(_ json: [String: Any]) -> CyclDict {
        CyclDict(
            code: SafeJSON.string(json["code"]),
            name: SafeJSON.string(json["name"]),
            groupCode: json["groupCode"].map { SafeJSON.string($0, fallback: "") }
        )
    }
}

struct CyclCredit: Identifiable, Equatable, Sendable {
    var id: String { creditId }
    var creditId: String
    var reportId: String?
    var userId: String
    var userName: String
    var activityName: String
    var activityType: String?
    var classHour: Double
    var scoreType: String
    var classCredit: String?
    var creditStatus: String
    var comment: String?
    var createTime: String
    var updateTime: String?
    var scoreTypeName: String
    var activityLevel: String?
    var activityLevelName: String?
    var activityStar: String?
    var creditStatusName: String

    static func fromJson(_ json: [String: Any]) -> CyclCredit {
        CyclCredit(
            creditId: SafeJSON.string(json["creditId"]),
            reportId: json["reportId"].map { SafeJSON.string($0, fallback: "") },
            userId: SafeJSON.string(json["userId"]),
            userName: SafeJSON.string(json["userName"]),
            activityName: SafeJSON.string(json["activityName"]),
            activityType: json["activityType"].map { SafeJSON.string($0, fallback: "") },
            classHour: SafeJSON.double(json["classHour"]),
            scoreType: SafeJSON.string(json["scoreType"]),
            classCredit: json["classCredit"].map { SafeJSON.string($0, fallback: "") },
            creditStatus: SafeJSON.string(json["creditStatus"]),
            comment: json["comment"].map { SafeJSON.string($0, fallback: "") },
            createTime: SafeJSON.string(json["createTime"]),
            updateTime: json["updateTime"].map { SafeJSON.string($0, fallback: "") },
            scoreTypeName: SafeJSON.string(json["scoreTypeName"]),
            activityLevel: json["activityLevel"].map { SafeJSON.string($0, fallback: "") },
            activityLevelName: json["activityLevelName"].map { SafeJSON.string($0, fallback: "") },
            activityStar: json["activityStar"].map { SafeJSON.string($0, fallback: "") },
            creditStatusName: SafeJSON.string(json["creditStatusName"])
        )
    }
}

struct CyclActivityLib: Identifiable, Equatable, Sendable {
    var id: String { activityLibraryId }
    var activityLibraryId: String
    var orgNo: String
    var name: String
    var level: String
    var star: String
    var activityType: String?
    var quality: [String]
    var classHour: Double
    var classCredit: String?
    var avgRank: String?
    var isPrize: String?
    var prizeClassHour: Int
    var describe: String?
    var scoringMode: String
    var creator: String
    var createTime: String
    var updater: String?
    var updateTime: String?
    var isDelete: Bool
    var liablePer: String
    var liablePerPhone: String
    var liableTer: String
    var liableTerPhone: String
    var instructorHour: Double
    var orgName: String
    var levelName: String?
    var starName: String?
    var activityTypeName: String?
    var doing: String?
    var subscribed: String?
    var scoreTypeNames: String?
    var qualityName: String?

    static func fromJson(_ json: [String: Any]) -> CyclActivityLib {
        CyclActivityLib(
            activityLibraryId: SafeJSON.string(json["activityLibraryId"]),
            orgNo: SafeJSON.string(json["orgNo"]),
            name: SafeJSON.string(json["name"]),
            level: SafeJSON.string(json["level"]),
            star: SafeJSON.string(json["star"]),
            activityType: json["activityType"].map { SafeJSON.string($0, fallback: "") },
            quality: (json["quality"] as? [Any])?.map { SafeJSON.string($0, fallback: "") } ?? [],
            classHour: SafeJSON.double(json["classHour"]),
            classCredit: json["classCredit"].map { SafeJSON.string($0, fallback: "") },
            avgRank: json["avgRank"].map { SafeJSON.string($0, fallback: "") },
            isPrize: json["isPrize"].map { SafeJSON.string($0, fallback: "") },
            prizeClassHour: SafeJSON.int(json["prizeClassHour"]),
            describe: json["describe"].map { SafeJSON.string($0, fallback: "") },
            scoringMode: SafeJSON.string(json["scoringMode"]),
            creator: SafeJSON.string(json["creator"]),
            createTime: SafeJSON.string(json["createTime"]),
            updater: json["updater"].map { SafeJSON.string($0, fallback: "") },
            updateTime: json["updateTime"].map { SafeJSON.string($0, fallback: "") },
            isDelete: json["isDelete"] as? Bool == true,
            liablePer: SafeJSON.string(json["liablePer"]),
            liablePerPhone: SafeJSON.string(json["liablePerPhone"]),
            liableTer: SafeJSON.string(json["liableTer"]),
            liableTerPhone: SafeJSON.string(json["liableTerPhone"]),
            instructorHour: SafeJSON.double(json["instructorHour"]),
            orgName: SafeJSON.string(json["orgName"]),
            levelName: json["levelName"].map { SafeJSON.string($0, fallback: "") },
            starName: json["starName"].map { SafeJSON.string($0, fallback: "") },
            activityTypeName: json["activityTypeName"].map { SafeJSON.string($0, fallback: "") },
            doing: json["doing"].map { SafeJSON.string($0, fallback: "") },
            subscribed: json["subscribed"].map { SafeJSON.string($0, fallback: "") },
            scoreTypeNames: json["scoreTypeNames"].map { SafeJSON.string($0, fallback: "") },
            qualityName: json["qualityName"].map { SafeJSON.string($0, fallback: "") }
        )
    }
}
