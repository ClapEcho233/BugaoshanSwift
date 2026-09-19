import Combine
import Foundation

// MARK: - 地区模型（service_region_picker.dart 数据部分）

/// 地区节点（省/市/区县），对应办事大厅 dRegion 组件的节点结构。
/// children 兼容 list（本地/直辖市）与 dict（在线普通省，key 为序号）两种形式。
struct ServiceRegionNode: Identifiable, Equatable {
    var id: String { value }
    var label: String
    var value: String
    var children: [ServiceRegionNode]
    /// 原始 children 是否为 List（区分直辖市与普通省的可靠依据）
    var childrenIsList: Bool

    var hasChildren: Bool { !children.isEmpty }

    /// 是否直辖市（children 是 list 且所有子节点（区）无下级）。
    /// 普通省可能混入直筒子市（东莞/中山无区），不能只看子节点深浅。
    var isMunicipality: Bool {
        guard childrenIsList, !children.isEmpty else { return false }
        return !children.allSatisfy(\.hasChildren)
    }

    static func fromJson(_ json: [String: Any]) -> ServiceRegionNode {
        let rawChildren: Any? = json["children"]
        return ServiceRegionNode(
            // region_data.json（modood pcas-code）用 code/name；在线接口用 value/label
            label: ServiceFormDefinition.anyToString(json["name"] ?? json["label"] ?? ""),
            value: normalizeRegionCode(ServiceFormDefinition.anyToString(json["code"] ?? json["value"] ?? "")),
            children: parseChildren(rawChildren),
            childrenIsList: rawChildren is [Any]
        )
    }

    private static func parseChildren(_ raw: Any?) -> [ServiceRegionNode] {
        if let list = raw as? [Any] {
            return list.compactMap { $0 as? [String: Any] }.map(fromJson)
        }
        if let map = raw as? [String: Any] {
            return map.values.compactMap { $0 as? [String: Any] }.map(fromJson)
        }
        return []
    }
}

/// 行政区划代码补全为 6 位（2/4/6 位变长码 → 110000/110100/110101）
func normalizeRegionCode(_ code: String) -> String {
    let trimmed = code.trimmingCharacters(in: .whitespaces)
    if trimmed.count >= 6 { return trimmed }
    return trimmed.padding(toLength: 6, withPad: "0", startingAt: 0)
}

/// 已选地区
struct ServiceRegionSelection: Equatable {
    var province: ServiceRegionNode?
    var city: ServiceRegionNode?
    var area: ServiceRegionNode?
    var details: String = ""

    var isEmpty: Bool {
        province == nil && city == nil && area == nil && details.isEmpty
    }

    /// 组装 Region_80 提交结构
    func toRegionData() -> [String: Any] {
        let p = province?.label ?? ""
        let c = city?.label ?? ""
        let a = area?.label ?? ""
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = [String]()
        if !p.isEmpty { address.append(p) }
        if !c.isEmpty { address.append(c) }
        if !a.isEmpty { address.append(a) }
        if !d.isEmpty { address.append(d) }
        return [
            "province": ["label": p, "value": province?.value ?? ""],
            "city": ["label": c, "value": city?.value ?? ""],
            "area": ["label": a, "value": area?.value ?? ""],
            "details": d,
            "address": address.joined(separator: "/"),
        ]
    }

    var displayText: String {
        var parts = [String]()
        if let province { parts.append(province.label) }
        if let city { parts.append(city.label) }
        if let area { parts.append(area.label) }
        if !details.isEmpty { parts.append(details) }
        return parts.joined(separator: "/")
    }
}

// MARK: - 表单控制器（service_form_controller.dart）

enum ServiceValidationKind: Equatable {
    case required
    case custom
}

struct ServiceValidationIssue {
    var fieldKey: String
    var kind: ServiceValidationKind
    var message: String?
}

/// 条件显示兜底规则（仅当服务端 ShowHide 未覆盖该字段时使用）
struct FieldVisibilityRule {
    var dependsOnKey: String
    var visibleWhenValues: Set<String>

    func isVisible(_ currentValue: Any?) -> Bool {
        guard let currentValue else { return false }
        return visibleWhenValues.contains(ServiceFormDefinition.anyToString(currentValue))
    }
}

/// 每事项覆盖配置（服务端表达不了的部分）
struct ServiceAppOverrides {
    /// 条件显示兜底（key 为被控制字段）
    var visibility: [String: FieldVisibilityRule] = [:]
    /// DataSource → 配对 Input 兜底（正常由插件 resultKey 提供）
    var dataSourceTargets: [String: String] = [:]
    /// 字段标签兜底
    var fieldLabels: [String: String] = [:]
    /// 字段展示顺序（350 的 sort 异常修正）
    var fieldOrder: [String] = []
    /// 附加校验（如 350 返校晚于离校——服务端无对应 Validate 规则）
    var extraValidators: [(ServiceFormController) -> ServiceValidationIssue?] = []
}

/// 本地待上传文件（提交前逐个 uploadAttachment 换成 ServiceAttachment）
struct ServiceLocalFile: Identifiable, Equatable {
    var id = UUID()
    var fileName: String
    var data: Data
    var mimeType: String
}

/// 表单值类型约定：
/// input/multiInput/dataSource → String；radio/select/selectV2 → String（选项 value）；
/// checkbox → Set<String>；calendar → Date；region → ServiceRegionSelection；
/// file → [ServiceLocalFile | ServiceAttachment]（提交前上传替换）。
final class ServiceFormController: ObservableObject {

    let schema: ServiceFormSchema
    let overrides: ServiceAppOverrides

    @Published var values: [String: Any?] = [:]

    init(schema: ServiceFormSchema, overrides: ServiceAppOverrides = ServiceAppOverrides()) {
        self.schema = schema
        self.overrides = overrides
        seedFromPrefill()
    }

    /// 服务端预填播种（calendar 字符串宽容解析为 Date；空串不播种）
    private func seedFromPrefill() {
        for (key, value) in schema.data {
            if value is NSNull { continue }
            let plugin = schema.pluginByKey(key)
            if plugin?.type == .calendar {
                if let parsed = parseServiceDate(value) {
                    values[key] = parsed
                }
            } else if let s = value as? String, s.isEmpty {
                continue
            } else {
                values[key] = value
            }
        }
    }

    /// 提交成功后重置
    func resetToPrefill() {
        values = [:]
        seedFromPrefill()
    }

    /// 字段标签：服务端 label > override 兜底 > key
    func labelOf(_ plugin: ServiceFormPlugin) -> String {
        if !plugin.label.isEmpty { return plugin.label }
        return overrides.fieldLabels[plugin.key] ?? plugin.key
    }

    /// 展示顺序：override fieldOrder 优先，其余按 sort
    var displayPlugins: [ServiceFormPlugin] {
        let list = schema.editablePlugins
        guard !overrides.fieldOrder.isEmpty else { return list }
        var index: [String: Int] = [:]
        for (i, key) in overrides.fieldOrder.enumerated() {
            index[key] = i
        }
        return list.sorted { a, b in
            let ai = index[a.key] ?? Int.max
            let bi = index[b.key] ?? Int.max
            if ai != bi { return ai < bi }
            return a.sort < b.sort
        }
    }

    // MARK: - ShowHide 引擎

    /// 跑一遍 ShowHide：按条件顺序求值，命中条件的动作按序应用（后者覆盖前者）。
    private func evalShowHide() -> (visibility: [String: Bool], required: [String: Bool]) {
        var vis: [String: Bool] = [:]
        var req: [String: Bool] = [:]
        for plugin in schema.activeShowHidePlugins {
            guard let rule = plugin.showHideRule else { continue }
            for (i, condition) in rule.conditions.enumerated() {
                let hit = evalServiceShowHideExpression(condition.expression) { key in
                    self.values[key] ?? nil
                }
                guard hit == true else { continue }
                guard let control = rule.controls[String(i)] else { continue }
                for target in control.targets {
                    if let isShow = control.isShow { vis[target] = isShow }
                    if let isRequired = control.isRequired { req[target] = isRequired }
                }
            }
        }
        return (vis, req)
    }

    /// 字段当前是否显示（ShowHide → override 兜底 → 恒显示）
    func isFieldVisible(_ plugin: ServiceFormPlugin) -> Bool {
        let (vis, _) = evalShowHide()
        if let dyn = vis[plugin.key] { return dyn }
        guard let rule = overrides.visibility[plugin.key] else { return true }
        return rule.isVisible(values[rule.dependsOnKey] ?? nil)
    }

    /// 字段当前是否必填（ShowHide → auth require）
    func isFieldRequired(_ fieldKey: String) -> Bool {
        let (_, req) = evalShowHide()
        if let dyn = req[fieldKey] { return dyn }
        return schema.isRequired(fieldKey)
    }

    // MARK: - 校验

    /// 提交前校验：可见可编辑字段的动态必填 + Validate 日期顺序 + 附加校验。
    func validate() -> ServiceValidationIssue? {
        for plugin in schema.editablePlugins {
            guard isFieldRequired(plugin.key), isFieldVisible(plugin) else { continue }
            if Self.isEmptyValue(plugin, values[plugin.key] ?? nil) {
                return ServiceValidationIssue(fieldKey: plugin.key, kind: .required)
            }
        }
        for rule in schema.dateOrderRules {
            if let a = (values[rule.firstKey] ?? nil) as? Date,
               let b = (values[rule.secondKey] ?? nil) as? Date,
               a > b {
                return ServiceValidationIssue(
                    fieldKey: rule.secondKey, kind: .custom, message: rule.message
                )
            }
        }
        for validator in overrides.extraValidators {
            if let issue = validator(self) {
                return issue
            }
        }
        return nil
    }

    static func isEmptyValue(_ plugin: ServiceFormPlugin, _ v: Any?) -> Bool {
        switch plugin.type {
        case .radio, .select, .selectV2:
            return v == nil || ServiceFormDefinition.anyToString(v ?? "").isEmpty
        case .checkbox:
            return v == nil || (v as? Set<String>)?.isEmpty != false
        case .input, .multiInput, .dataSource:
            return v == nil || ServiceFormDefinition.anyToString(v ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .region:
            return v == nil || (v as? ServiceRegionSelection)?.isEmpty != false
        case .file:
            return v == nil || (v as? [Any])?.isEmpty != false
        case .calendar:
            return v == nil
        default:
            return v == nil
        }
    }

    static func hasValue(_ plugin: ServiceFormPlugin, _ v: Any?) -> Bool {
        !isEmptyValue(plugin, v)
    }

    // MARK: - DataSource 分发

    /// 取数结果分发：setplugin 按 mapConfig 多列分发；否则 name 写入本字段与
    /// resultKey 配对字段。
    func applyDataSourceValue(_ plugin: ServiceFormPlugin, _ listValue: Any?) {
        guard let ref = plugin.dataSource else { return }
        if ref.isSetPlugin {
            guard let list = listValue as? [String: Any] else { return }
            for (targetKey, column) in ref.mapConfig {
                guard let raw = list[column],
                      !ServiceFormDefinition.anyToString(raw).isEmpty else { continue }
                let target = schema.pluginByKey(targetKey)
                if target?.type == .calendar {
                    if let parsed = parseServiceDate(raw) {
                        values[targetKey] = parsed
                    }
                } else {
                    values[targetKey] = ServiceFormDefinition.anyToString(raw)
                }
            }
            return
        }
        let name = listValue.map { ServiceFormDefinition.anyToString($0) } ?? ""
        guard !name.isEmpty else { return }
        values[plugin.key] = name
        var target: String?
        if !ref.resultKey.isEmpty {
            target = ref.resultKey
        } else {
            target = overrides.dataSourceTargets[plugin.key]
        }
        if let target, !target.isEmpty {
            values[target] = name
        }
    }

    // MARK: - 组装提交体

    /// 单表单字段 Map（规则复现 350 已验证 payload + 337/356/357 校准）：
    /// 1. 占位类型 → ''/[]；2. DataSource 有值 → {list:name}+配对，空 → 整对省略；
    /// 3. 只读/隐藏/User：有值序列化、空 → 占位；4. 可编辑：可见序列化、隐藏空值。
    func buildFormFields() -> [String: Any] {
        var result: [String: Any] = [:]
        var omitted = Set<String>()

        for key in schema.auth.keys {
            let plugin = schema.pluginByKey(key)
            let type = plugin?.type ?? serviceFieldTypeFromKey(key)
            let v = values[key] ?? nil

            if ServiceFormSchema.placeholderTypes.contains(type) {
                result[key] = ServiceFormSchema.placeholderValueFor(type)
                continue
            }

            if type == .dataSource {
                let name = v.map { ServiceFormDefinition.anyToString($0) } ?? ""
                let target: String?
                if let ref = plugin?.dataSource, !ref.resultKey.isEmpty {
                    target = ref.resultKey
                } else {
                    target = overrides.dataSourceTargets[key]
                }
                if !name.isEmpty {
                    result[key] = ["list": name]
                    if let target, !target.isEmpty, plugin?.dataSource?.isSetPlugin != true {
                        result[target] = name
                    }
                } else {
                    // 取数为空：整对省略（350 已验证）
                    omitted.insert(key)
                    if let target, !target.isEmpty {
                        omitted.insert(target)
                    }
                }
                continue
            }

            guard let plugin else {
                // 孤儿 auth key 按前缀规则占位兜底
                result[key] = ServiceFormSchema.placeholderValueFor(type)
                continue
            }

            if schema.isReadOnly(key) || schema.isSuppressed(key) || type == .user {
                result[key] = Self.hasValue(plugin, v)
                    ? serializeServiceFieldValue(plugin, v)
                    : ServiceFormSchema.placeholderValueFor(type)
                continue
            }

            if !isFieldVisible(plugin) {
                result[key] = ServiceFormSchema.placeholderValueFor(type)
                continue
            }
            result[key] = serializeServiceFieldValue(plugin, v)
        }

        for key in omitted {
            result.removeValue(forKey: key)
        }
        return result
    }

    /// 完整 form_data（外层以 formId 包装）
    func buildFormData() -> [String: Any] {
        [schema.formId: buildFormFields()]
    }
}

// MARK: - 类型感知序列化（复现 350 抓包结构）

/// radio/select → {"value","name"}；selectV2/checkbox → [{value,name}]；
/// calendar → UTC ISO 8601；region → toRegionData；file → [{name,url,id}]；
/// dataSource → {"list":name}；其余字符串；空值 ''（数组型 []）。
func serializeServiceFieldValue(_ plugin: ServiceFormPlugin, _ value: Any?) -> Any {
    func optionName(_ v: String) -> String {
        plugin.options.first { $0.value == v }?.label ?? ""
    }

    switch plugin.type {
    case .radio, .select:
        let v = value.map { ServiceFormDefinition.anyToString($0) } ?? ""
        if v.isEmpty { return "" }
        return ["value": v, "name": optionName(v)]
    case .selectV2:
        let v = value.map { ServiceFormDefinition.anyToString($0) } ?? ""
        if v.isEmpty { return [Any]() }
        return [["value": v, "name": optionName(v)]]
    case .checkbox:
        let selected = value as? Set<String> ?? []
        return selected.map { ["value": $0, "name": optionName($0)] }
    case .calendar:
        guard let date = value as? Date else { return "" }
        return ServiceFormController.utcIso8601(date)
    case .region:
        guard let selection = value as? ServiceRegionSelection, !selection.isEmpty else { return "" }
        return selection.toRegionData()
    case .file:
        guard let list = value as? [Any] else { return [Any]() }
        return list.compactMap { item -> [String: Any]? in
            if let attachment = item as? ServiceAttachment {
                return attachment.toFormData()
            }
            return nil
        }
    case .dataSource:
        let name = value.map { ServiceFormDefinition.anyToString($0) } ?? ""
        return name.isEmpty ? "" : ["list": name]
    case .input, .multiInput, .user:
        return value.map { ServiceFormDefinition.anyToString($0) } ?? ""
    default:
        return value.map { ServiceFormDefinition.anyToString($0) } ?? ""
    }
}

extension ServiceFormController {
    /// Dart DateTime.toUtc().toIso8601String()：'2026-08-10T00:00:00.000Z'
    static func utcIso8601(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
