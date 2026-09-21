import Foundation

// MARK: - 报修模型（对应 lib/models/repair.dart；字段宽松解析）

struct RepairAddress: Identifiable, Equatable, Sendable {
    var id: String
    var areaName: String
    var addressDetail: String
    var phone: String
    var areaId: String
    var isCommon: Bool
    var userId: String

    var displayName: String {
        isCommon ? "\(areaName) / \(addressDetail)（默认）" : "\(areaName) / \(addressDetail)"
    }

    static func fromJson(_ json: [String: Any]) -> RepairAddress {
        RepairAddress(
            id: SafeJSON.string(json["id"]),
            areaName: SafeJSON.string(json["areaName"]),
            addressDetail: SafeJSON.string(json["addressDetail"]),
            phone: SafeJSON.string(json["phone"]),
            areaId: SafeJSON.string(json["areaId"]),
            isCommon: SafeJSON.string(json["isCommon"]) == "1",
            userId: SafeJSON.string(json["userId"] ?? json["createUser"])
        )
    }
}

/// 报修项目两级树（大类 → 叶子）
struct RepairProject: Identifiable, Equatable, Sendable {
    var id: String { value }
    var label: String
    var value: String
    var children: [RepairProject]

    static func fromJson(_ json: [String: Any]) -> RepairProject {
        RepairProject(
            label: SafeJSON.string(json["label"]),
            value: SafeJSON.string(json["value"]),
            children: ((json["children"] as? [[String: Any]]) ?? []).map(RepairProject.fromJson)
        )
    }
}

struct RepairAcceptDept: Equatable, Sendable {
    var deptId: String
    var deptName: String
    var payName: String

    static func fromJson(_ json: [String: Any]) -> RepairAcceptDept {
        RepairAcceptDept(
            deptId: SafeJSON.string(json["deptId"]),
            deptName: SafeJSON.string(json["deptName"]),
            payName: SafeJSON.string(json["payName"])
        )
    }
}

struct RepairAreaNode: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var parentName: String
    var children: [RepairAreaNode]

    var fullName: String { parentName.isEmpty ? name : "\(parentName)/\(name)" }

    static func fromJson(_ json: [String: Any]) -> RepairAreaNode {
        RepairAreaNode(
            id: SafeJSON.string(json["id"]),
            name: SafeJSON.string(json["name"]),
            parentName: SafeJSON.string(json["parentName"]),
            children: ((json["children"] as? [[String: Any]]) ?? []).map(RepairAreaNode.fromJson)
        )
    }
}

struct RepairEvaluateProject: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var weight: String
    var star: Int = 5

    static func fromJson(_ json: [String: Any]) -> RepairEvaluateProject {
        RepairEvaluateProject(
            id: SafeJSON.string(json["id"]),
            name: SafeJSON.string(json["name"]),
            weight: SafeJSON.string(json["weight"])
        )
    }
}

// MARK: - 工单

struct RepairTicket: Identifiable, Equatable, Sendable {
    var id: String { activeId }
    var activeId: String
    var areaName: String
    var projectName: String
    var serviceUnit: String
    var content: String
    var status: String
    var createTime: Int
    var activeTime: String

    /// 排序键：activeTime（YYYY-MM-DD HH:mm:ss 字典序）优先，回退 createTime
    var sortKey: String {
        activeTime.isEmpty
            ? String(format: "%010d", min(createTime, 9999999999))
            : activeTime
    }

    static func fromJson(_ json: [String: Any]) -> RepairTicket {
        // activeId 缺失/为空时回退列表行自身的 id（对应 Flutter 版
        // json['activeId'] ?? json['id'] ?? ''）：历史工单（已关闭等）
        // 没有进行中的动态，后端只返回 id，没有 activeId。
        let rawActiveId = SafeJSON.string(json["activeId"])
        let activeId = rawActiveId.isEmpty ? SafeJSON.string(json["id"]) : rawActiveId
        return RepairTicket(
            activeId: activeId,
            areaName: SafeJSON.string(json["areaName"]),
            projectName: SafeJSON.string(json["projectName"]),
            serviceUnit: SafeJSON.string(json["serviceUnit"]),
            content: Self.parseContent(SafeJSON.string(json["content"])),
            status: SafeJSON.string(json["status"]),
            createTime: SafeJSON.int(json["createTime"]),
            activeTime: SafeJSON.string(json["activeTime"])
        )
    }

    /// content 是 JSON 字符串：兼容 Map / JSON 串 / 最多 5 层转义嵌套 /
    /// 值内裸控制字符（issue #273：后端不转义用户输入的换行）。
    /// 展示优先「故障描述」，缺失则以 · 拼接其余字段，绝不展示原始 JSON。
    static func parseContent(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        // 先尝试原样解析；失败则转义字符串值内的控制字符后重试（最多 5 层嵌套）
        var attempts = [raw]
        var escaped = raw
        for _ in 0..<5 {
            escaped = escapeRawControlChars(escaped)
            attempts.append(escaped)
            if escaped == raw { break }
        }
        for attempt in attempts {
            if let data = attempt.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return describeContent(obj)
            }
        }
        // 非 JSON → 原文展示
        return raw
    }

    private static func escapeRawControlChars(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        for char in text {
            if escaped {
                out.append(char)
                escaped = false
                continue
            }
            if char == "\\" && inString {
                out.append(char)
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                out.append(char)
                continue
            }
            if inString {
                switch char {
                case "\n": out.append("\\n")
                case "\r": out.append("\\r")
                case "\t": out.append("\\t")
                default:
                    if char.asciiValue.map({ $0 < 0x20 }) == true {
                        out += String(format: "\\u%04x", char.asciiValue!)
                    } else {
                        out.append(char)
                    }
                }
            } else {
                out.append(char)
            }
        }
        return out
    }

    private static func describeContent(_ obj: [String: Any]) -> String {
        let description = SafeJSON.string(obj["故障描述"])
        if !description.isEmpty {
            return description
        }
        var parts: [String] = []
        for key in ["故障地点", "维修项目", "服务单位"] {
            let value = SafeJSON.string(obj[key])
            if !value.isEmpty {
                parts.append(value)
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct RepairLogItem: Identifiable, Equatable, Sendable {
    var id: String { "\(statusName)-\(content)-\(createTime)" }
    var statusName: String
    var content: String
    var createTime: Int

    static func fromJson(_ json: [String: Any]) -> RepairLogItem {
        RepairLogItem(
            statusName: SafeJSON.string(json["statusName"]),
            content: SafeJSON.string(json["content"]),
            createTime: SafeJSON.int(json["createTime"])
        )
    }
}

struct RepairTicketDetail: Equatable, Sendable {
    var id: String
    var serialNumber: String
    var projectName: String
    var content: String
    var areaName: String
    var address: String
    var acceptDeptName: String
    var payName: String
    var bookTimeString: String
    var status: String
    var ifCommont: Bool
    var ifComplete: Bool
    var logs: [RepairLogItem]
    var finishedInfoRepairId: String
    var finishedCompleteTime: String

    /// status == '4' 且未评价 → 可评价
    var canEvaluate: Bool { status == "4" && !ifCommont }

    static func fromJson(_ json: [String: Any]) -> RepairTicketDetail {
        let finished = json["finishedInfo"] as? [String: Any]
        return RepairTicketDetail(
            id: SafeJSON.string(json["id"]),
            serialNumber: SafeJSON.string(json["serialNumber"]),
            projectName: SafeJSON.string(json["projectName"]),
            content: RepairTicket.parseContent(SafeJSON.string(json["content"])),
            areaName: SafeJSON.string(json["areaName"]),
            address: SafeJSON.string(json["address"]),
            acceptDeptName: SafeJSON.string(json["acceptDeptName"]),
            payName: SafeJSON.string(json["payName"]),
            bookTimeString: SafeJSON.string(json["bookTimeString"]),
            status: SafeJSON.string(json["status"]),
            ifCommont: SafeJSON.string(json["ifCommont"]) != "0",
            ifComplete: SafeJSON.string(json["ifComplete"]) != "0",
            logs: ((json["logs"] as? [[String: Any]]) ?? []).map(RepairLogItem.fromJson),
            finishedInfoRepairId: SafeJSON.string(finished?["repairId"]),
            finishedCompleteTime: finished.map { SafeJSON.string($0["completeTime"]) } ?? ""
        )
    }
}
