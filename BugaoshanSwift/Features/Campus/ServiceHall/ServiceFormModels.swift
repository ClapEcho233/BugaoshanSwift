import Foundation

// MARK: - 字段类型（service_field_type.dart）

/// 字段类型。优先插件声明的组件类型（`type` 如 dRadio），缺失时按 key 前缀推断。
enum ServiceFieldType: String, Equatable, Sendable, CaseIterable {
    case input, multiInput, radio, select
    case selectV2    // 新下拉（dSelectV2）：提交 [{value, name}] 数组（单选也是数组）
    case checkbox
    case calendar
    case region
    case file        // 附件/图片上传（dFile/dXImage）：提交 [{name, url, id}]
    case dataSource
    case user
    case showHide, variate, validate, conversion, repeatTable
    case text        // 静态说明文字（dOneInput / Text_）：只读展示
    case image       // 静态图片：占位不渲染
    case table       // 布局容器：占位不渲染
    case unknown
}

/// key 前缀 → 类型（key 形如 Radio_30）
private let prefixTypes: [(String, ServiceFieldType)] = [
    ("Input_", .input), ("MultiInput_", .multiInput), ("MultiText_", .multiInput),
    ("Radio_", .radio), ("Select_", .select), ("SelectV2_", .selectV2),
    ("Checkbox_", .checkbox), ("Calendar_", .calendar), ("Region_", .region),
    ("File_", .file), ("Ximage_", .file), ("DataSource_", .dataSource),
    ("User_", .user), ("ShowHide_", .showHide), ("Variate_", .variate),
    ("Validate_", .validate), ("Conversion_", .conversion),
    ("RepeatTable_", .repeatTable), ("Text_", .text), ("Image_", .image),
    ("Table_", .table),
]

/// 组件名（去 d 前缀、小写）→ 类型
private let componentTypes: [String: ServiceFieldType] = [
    "input": .input, "integerinput": .input, "numericinput": .input, "phonenumber": .input,
    "multitext": .multiInput, "multiinputs": .multiInput,
    "radio": .radio, "select": .select, "selectv2": .selectV2, "checkbox": .checkbox,
    "calendar": .calendar, "region": .region, "file": .file, "ximage": .file,
    "datasource": .dataSource, "user": .user, "showhide": .showHide, "variate": .variate,
    "validate": .validate, "conversion": .conversion, "repeattable": .repeatTable,
    "oneinput": .text, "text": .text, "show": .text, "image": .image, "table": .table,
]

func serviceFieldTypeFromKey(_ key: String) -> ServiceFieldType {
    for (prefix, type) in prefixTypes where key.hasPrefix(prefix) {
        return type
    }
    return .unknown
}

/// 解析字段类型：优先组件声明（如 dRadio，大小写不敏感），缺失/不认识按 key 前缀推断。
func resolveServiceFieldType(_ declaredType: String?, _ key: String) -> ServiceFieldType {
    if var name = declaredType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
       !name.isEmpty {
        if name.hasPrefix("d"), name.count > 1 {
            name.removeFirst()
        }
        if let type = componentTypes[name] {
            return type
        }
    }
    return serviceFieldTypeFromKey(key)
}

// MARK: - 表单定义（service_form_models.dart）

/// `/site/form/start-data` 响应：字段 key → 权限/预填值。
/// 字段的中文标签和选项不在本接口，需由 get-formv 合并。
struct ServiceFormDefinition {
    /// 当前生效表单 id（元素是 int，如 1419）
    var currform: [Any]
    /// 字段 key → 权限（require/writable/readable/front_readonly）
    var auth: [String: String]
    /// 字段 key → 预填值（学号、姓名等）
    var data: [String: Any]

    static func fromJson(_ json: [String: Any]) -> ServiceFormDefinition {
        // currform 元素是 int 而 auth/data 的 key 是 String，必须转字符串再查
        let currformList = json["currform"] as? [Any] ?? []
        let rawFormId: Any? = currformList.first
        let formId = rawFormId.map { ServiceFormDefinition.anyToString($0) }

        var authMap: [String: String] = [:]
        var dataMap: [String: Any] = [:]
        if let formId,
           let authAll = json["auth"] as? [String: Any],
           let inner = authAll[formId] as? [String: Any] {
            for (k, v) in inner {
                authMap[k] = ServiceFormDefinition.anyToString(v)
            }
        }
        if let formId,
           let dataAll = json["data"] as? [String: Any],
           let inner = dataAll[formId] as? [String: Any] {
            dataMap = inner
        }
        return ServiceFormDefinition(currform: currformList, auth: authMap, data: dataMap)
    }

    static func anyToString(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return "\(value)"
    }

    func isRequired(_ fieldKey: String) -> Bool { auth[fieldKey] == "require" }

    func isReadOnly(_ fieldKey: String) -> Bool {
        let a = auth[fieldKey]
        return a == "readable" || a == "front_readonly" || a == "readonly"
    }

    /// 需要用户填写的字段（非只读且无预填）
    var editableFields: [String] {
        auth.keys.filter { key in
            !isReadOnly(key) && !ServiceFormDefinition.hasValue(data[key])
        }
    }

    /// 服务端带出、不可改的字段
    var prefilledFields: [String] {
        auth.keys.filter { isReadOnly($0) && ServiceFormDefinition.hasValue(data[$0]) }
    }

    static func hasValue(_ v: Any?) -> Bool {
        guard let v else { return false }
        return !anyToString(v).isEmpty
    }
}

// MARK: - 选项 / 附件（service_form_fields.dart / ServiceAttachment）

struct ServiceFieldOption: Equatable, Sendable {
    var value: String
    var label: String
}

/// 上传附件信息（File 字段提交数组元素）
struct ServiceAttachment: Equatable, Codable, Sendable {
    var name: String
    var url: String
    var id: String

    func toFormData() -> [String: Any] { ["name": name, "url": url, "id": id] }
}

// MARK: - DataSource 取数配置（service_plugin_models.dart）

/// DataSource 字段的取数配置，全部来自插件自身配置，绝不按事项硬编码。
struct ServiceDataSourceRef: Equatable, Sendable {
    var id: String                 // attr.data.sourceid
    var formVersionId: String      // form 的 version_id，如 2357
    var component: String          // 插件 key，如 DataSource_85
    var formId: String             // 所属表单 id，如 1419
    var resultKey: String = ""     // 普通值=结果写入的字段；'setplugin'=按 mapConfig 分发
    var mapConfig: [String: String] = [:]
    var configure: [String: String] = [:]

    var isSetPlugin: Bool { resultKey == "setplugin" }
}

/// Validate 插件的日期顺序校验：dateDayMinus(A,B)<0 → A 早于等于 B 为合法
struct ServiceDateOrderRule: Equatable, Sendable {
    var firstKey: String
    var secondKey: String
    var message: String

    static func tryParse(rule: Any?, alert: Any?) -> ServiceDateOrderRule? {
        guard let ruleString = rule as? String, !ruleString.isEmpty else { return nil }
        guard let m = RegexHelper.firstMatch(
            #"^\s*\{f_dateDayMinus\}\(\s*\{p_([A-Za-z0-9_]+)\}\s*,\s*\{p_([A-Za-z0-9_]+)\}\s*\)\s*<\s*0\s*$"#,
            in: ruleString
        ) else { return nil }
        return ServiceDateOrderRule(
            firstKey: m[1],
            secondKey: m[2],
            message: alert as? String ?? ""
        )
    }
}

// MARK: - ShowHide 规则（service_showhide_rule.dart）

struct ServiceShowHideCondition: Equatable, Sendable {
    var name: String
    var expression: String
}

/// 条件命中后的动作：按条件顺序应用，后者覆盖前者。
struct ServiceShowHideControl: Equatable, Sendable {
    var isShow: Bool?          // isShow 1/0；nil 不动
    var isRequired: Bool?      // isRequired 1 → 必填；nil 不动
    var clearWhenHidden: Bool  // isEmpty 1 → 清空（提交统一空值，仅记录）
    var targets: [String]
}

struct ServiceShowHideRule: Equatable, Sendable {
    var conditions: [ServiceShowHideCondition]
    var controls: [String: ServiceShowHideControl]

    /// 从 ShowHide 插件 attr.data 解析；结构不符返回 nil。
    /// conditions 可能是 List 或 Map（{"0": {...}}）；controls 目前只处理 List。
    static func tryParse(_ attrData: [String: Any]) -> ServiceShowHideRule? {
        guard let rawConds = attrData["conditions"],
              let rawControls = attrData["controls"] else { return nil }

        var conditions: [ServiceShowHideCondition] = []
        if let condList = rawConds as? [[String: Any]] {
            conditions = condList.map {
                ServiceShowHideCondition(
                    name: ServiceFormDefinition.anyToString($0["name"] ?? ""),
                    expression: ServiceFormDefinition.anyToString($0["expression"] ?? "")
                )
            }
        } else if let condMap = rawConds as? [String: Any] {
            conditions = condMap.values.compactMap { v in
                guard let item = v as? [String: Any] else { return nil }
                return ServiceShowHideCondition(
                    name: ServiceFormDefinition.anyToString(item["name"] ?? ""),
                    expression: ServiceFormDefinition.anyToString(item["expression"] ?? "")
                )
            }
        }
        guard !conditions.isEmpty else { return nil }

        var controls: [String: ServiceShowHideControl] = [:]
        if let controlList = rawControls as? [[String: Any]] {
            for c in controlList {
                guard let conkey = c["conkey"] as? String,
                      let setInfo = c["setInfo"] as? [String: Any] else { continue }
                controls[conkey] = parseControl(setInfo)
            }
        }
        return ServiceShowHideRule(conditions: conditions, controls: controls)
    }

    private static func parseControl(_ setInfo: [String: Any]) -> ServiceShowHideControl {
        let isShow = toInt(setInfo["isShow"], fallback: -1)
        let isRequired = toInt(setInfo["isRequired"], fallback: -1)
        let isEmpty = toInt(setInfo["isEmpty"], fallback: 0)
        let targets = (setInfo["plugins"] as? [Any])?.map(ServiceFormDefinition.anyToString) ?? []
        return ServiceShowHideControl(
            isShow: isShow == -1 ? nil : isShow == 1,
            isRequired: isRequired == -1 ? nil : isRequired == 1,
            clearWhenHidden: isEmpty == 1,
            targets: targets
        )
    }

    static func toInt(_ v: Any?, fallback: Int = 0) -> Int {
        if let n = v as? Int { return n }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? fallback }
        if let n = v as? NSNumber { return n.intValue }
        return fallback
    }
}

/// 求值 ShowHide 条件表达式。返回 nil = 形态未支持（按不命中处理；
/// "默认 true" 基准条件总可求值，字段不会卡在未知状态）。
func evalServiceShowHideExpression(
    _ expression: String,
    valueOf: (String) -> Any?
) -> Bool? {
    let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    if expr.isEmpty { return nil }
    if expr == "true" { return true }
    if expr == "false" { return false }

    // || 复合（实表只出现 ||，逐段求值；有未知段不妄断）
    if expr.contains("||") {
        for part in expr.components(separatedBy: "||") {
            let r = evalServiceShowHideExpression(part, valueOf: valueOf)
            if r == true { return true }
            if r == nil { return nil }
        }
        return false
    }

    func norm(_ v: Any?) -> String {
        guard let v else { return "" }
        return ServiceFormDefinition.anyToString(v).trimmingCharacters(in: .whitespaces)
    }

    func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2 {
            if (t.hasPrefix("'") && t.hasSuffix("'")) || (t.hasPrefix("\"") && t.hasSuffix("\"")) {
                return String(t.dropFirst().dropLast())
            }
        }
        return t
    }

    // {p_K}=='' / {p_K}!=''
    if let m = RegexHelper.firstMatch(#"^\{p_([A-Za-z0-9_]+)\}\s*(==|!=)\s*''$"#, in: expr) {
        let empty = norm(valueOf(m[1])).isEmpty
        return m[2] == "==" ? empty : !empty
    }

    // {p_K}.indexOf(v)!==-1 / ==-1
    if let m = RegexHelper.firstMatch(
        #"^\{p_([A-Za-z0-9_]+)\}\.indexOf\(([^)]+)\)\s*(!==-1|==-1)$"#, in: expr
    ) {
        let v = norm(valueOf(m[1]))
        let needle = unquote(m[2])
        let hit = !needle.isEmpty && v.contains(needle)
        return m[3] == "!==-1" ? hit : !hit
    }

    // {p_K}.includes('s')
    if let m = RegexHelper.firstMatch(
        #"^\{p_([A-Za-z0-9_]+)\}\.includes\(([^)]+)\)$"#, in: expr
    ) {
        return norm(valueOf(m[1])).contains(unquote(m[2]))
    }

    // {p_K}[0].value==v / {p_K}[0]==v（SelectV2；值存为单个 value 字符串）
    if let m = RegexHelper.firstMatch(
        #"^\{p_([A-Za-z0-9_]+)\}\[0\](?:\.value)?\s*(==|!=)\s*(\S+)$"#, in: expr
    ) {
        let v = norm(valueOf(m[1]))
        let hit = v == unquote(m[3])
        return m[2] == "==" ? hit : !hit
    }

    // new Date({p_K}) <= new Date('yyyy-MM-dd')
    if let m = RegexHelper.firstMatch(
        #"^new Date\(\{p_([A-Za-z0-9_]+)\}\)\s*(<=|>=|<|>)\s*new Date\('([^']+)'\)$"#, in: expr
    ) {
        guard let a = parseServiceDate(valueOf(m[1])),
              let b = parseServiceDate(m[3]) else { return nil }
        switch m[2] {
        case "<=": return a <= b
        case ">=": return a >= b
        case "<": return a < b
        case ">": return a > b
        default: return nil
        }
    }

    // {p_K}==v / {p_K}!=v（放最后，避免吞掉上面的形态）
    if let m = RegexHelper.firstMatch(
        #"^\{p_([A-Za-z0-9_]+)\}\s*(==|!=)\s*(\S+)$"#, in: expr
    ) {
        let v = norm(valueOf(m[1]))
        let hit = v == unquote(m[3])
        return m[2] == "==" ? hit : !hit
    }

    return nil
}

/// 宽松解析服务端日期（'2026-08-10'、'2026-08-10T17:10:21+' 截断时区等）
func parseServiceDate(_ raw: Any?) -> Date? {
    guard let raw else { return nil }
    if let date = raw as? Date { return date }
    let s = ServiceFormDefinition.anyToString(raw).trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    guard let m = RegexHelper.firstMatch(
        #"^(\d{4}-\d{2}-\d{2})(?:[T ](\d{2}:\d{2}(?::\d{2})?))?"#, in: s
    ) else { return nil }
    var candidate = m[1]
    if m.count > 2 {
        candidate += "T" + m[2]
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = m.count > 2 ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    if let date = formatter.date(from: candidate) { return date }
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.date(from: candidate)
}

// MARK: - 插件模型（service_plugin_models.dart）

/// 单个表单字段（插件）。attr / attr.data 可能双重编码为 JSON 字符串，两层均解码。
struct ServiceFormPlugin: Equatable, Sendable {
    var key: String
    var type: ServiceFieldType
    var label: String          // 插件顶层 description（attr.data.name 是绑定表达式名，仅兜底）
    var sort: Int
    var options: [ServiceFieldOption]
    var hint: String?
    var maxCount: Int          // attr.data.maxNum；0/缺省 → 3
    var dataSource: ServiceDataSourceRef?
    var dateOrderRule: ServiceDateOrderRule?
    var showHideRule: ServiceShowHideRule?
    var raw: [String: Any]     // attr.data 原始配置

    static func == (lhs: ServiceFormPlugin, rhs: ServiceFormPlugin) -> Bool {
        lhs.key == rhs.key && lhs.type == rhs.type && lhs.sort == rhs.sort
    }

    /// 解析单个插件 JSON；fallbackKey 为 plugins map 外层 key 兜底。
    /// 解析不出 key 时抛 FormatError（由调用方走 fallback）。
    static func fromJson(
        _ json: [String: Any],
        formId: String,
        formVersionId: String = "",
        fallbackKey: String? = nil
    ) throws -> ServiceFormPlugin {
        let key = firstString(json, ["key", "dataid", "id"]) ?? (fallbackKey ?? "")
        guard !key.isEmpty else {
            throw SCUError.service("插件缺少 key")
        }

        // attr 可能是字符串（二次编码）或对象；attr.data 同理
        var attrMap: [String: Any] = [:]
        if let attrDecoded = decodeJsonString(json["attr"]) as? [String: Any] {
            attrMap = attrDecoded
        } else if let attr = json["attr"] as? [String: Any] {
            attrMap = attr
        }
        var data: [String: Any] = [:]
        if let dataDecoded = decodeJsonString(attrMap["data"]) as? [String: Any] {
            data = dataDecoded
        } else if let d = attrMap["data"] as? [String: Any] {
            data = d
        }

        let declaredType = firstString(json, ["type", "component"])
        let type = resolveServiceFieldType(declaredType, key)

        let label = firstString(json, ["description", "label", "title"])
            ?? firstString(data, ["label", "title", "name"])
            ?? ""

        let sort = ServiceShowHideRule.toInt(json["sort"] ?? data["sort"])
        let options = parseOptions(data)
        let hint = firstString(data, ["placeholder", "hint", "tip"])
        // maxNum 可能是数字或字符串；0/非法 → 默认 3（不要用 limitval，那是 Region 层级深度）
        let maxNum = ServiceShowHideRule.toInt(data["maxNum"] ?? data["maxCount"], fallback: 0)

        var dsRef: ServiceDataSourceRef?
        if type == .dataSource {
            let sourceId = firstString(data, ["sourceid", "source_id", "data_source_id", "dataSourceId"]) ?? ""
            if !sourceId.isEmpty {
                dsRef = ServiceDataSourceRef(
                    id: sourceId,
                    formVersionId: formVersionId,
                    component: key,
                    formId: formId,
                    resultKey: firstString(data, ["resultKey"]) ?? "",
                    mapConfig: parseMapConfig(data["mapConfig"]),
                    configure: parseSourceConfig(data["sourceConfig"])
                )
            }
        }

        var dateOrderRule: ServiceDateOrderRule?
        if type == .validate {
            dateOrderRule = ServiceDateOrderRule.tryParse(rule: data["rule"], alert: data["alert"])
        }

        var showHideRule: ServiceShowHideRule?
        if type == .showHide {
            showHideRule = ServiceShowHideRule.tryParse(data)
        }

        return ServiceFormPlugin(
            key: key,
            type: type,
            label: label,
            sort: sort,
            options: options,
            hint: hint,
            maxCount: maxNum > 0 ? maxNum : 3,
            dataSource: dsRef,
            dateOrderRule: dateOrderRule,
            showHideRule: showHideRule,
            raw: data
        )
    }

    // MARK: 解析工具

    static func firstString(_ map: [String: Any], _ keys: [String]) -> String? {
        for k in keys {
            let v = map[k]
            if let s = v as? String, !s.isEmpty { return s }
            if let n = v as? NSNumber { return n.stringValue }
        }
        return nil
    }

    /// 若是 JSON 字符串则解码为对象，否则原样返回
    static func decodeJsonString(_ raw: Any?) -> Any? {
        guard let s = raw as? String,
              let data = s.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return raw
        }
        return decoded
    }

    private static func parseOptions(_ data: [String: Any]) -> [ServiceFieldOption] {
        for k in ["options", "items", "list", "option"] {
            guard let raw = data[k] as? [[String: Any]] else { continue }
            var result: [ServiceFieldOption] = []
            for item in raw {
                let label = firstString(item, ["name", "label", "title"])
                let value = firstString(item, ["value", "id"])
                if let label, let value {
                    result.append(ServiceFieldOption(value: value, label: label))
                }
            }
            if !result.isEmpty { return result }
        }
        return []
    }

    /// mapConfig 真实形态 {User_156: {key: "grade"}}；空 List 按空处理
    private static func parseMapConfig(_ raw: Any?) -> [String: String] {
        guard let map = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in map {
            if let inner = v as? [String: Any], let key = inner["key"] {
                result[k] = ServiceFormDefinition.anyToString(key)
            }
        }
        return result
    }

    /// sourceConfig 结构 {key: {value: ...}}
    private static func parseSourceConfig(_ raw: Any?) -> [String: String] {
        guard let map = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in map {
            if let inner = v as? [String: Any], let value = inner["value"] {
                result[k] = ServiceFormDefinition.anyToString(value)
            } else if !(v is NSNull) {
                result[k] = ServiceFormDefinition.anyToString(v)
            }
        }
        return result
    }
}

// MARK: - 可渲染 Schema

/// 完整可渲染 schema = get-formv 插件定义 + start-data 权限/预填。
struct ServiceFormSchema {
    var appId: String
    var formId: String
    var formVersionId: String
    var plugins: [ServiceFormPlugin]   // sort 升序
    var auth: [String: String]
    var data: [String: Any]

    /// 占位类型：不渲染、提交时按规则给 '' 或 []
    static let placeholderTypes: Set<ServiceFieldType> = [
        .showHide, .variate, .validate, .conversion, .repeatTable,
        .text, .image, .table, .unknown,
    ]

    /// 占位字段提交空值：conversion/repeatTable/selectV2/checkbox/file → []
    static func placeholderValueFor(_ type: ServiceFieldType) -> Any {
        switch type {
        case .conversion, .repeatTable, .selectV2, .checkbox, .file:
            return [Any]()
        default:
            return ""
        }
    }

    func isRequired(_ fieldKey: String) -> Bool { auth[fieldKey] == "require" }

    func isReadOnly(_ fieldKey: String) -> Bool {
        let a = auth[fieldKey]
        return a == "readable" || a == "front_readonly" || a == "readonly"
    }

    /// hidden/forbidden：不渲染，提交按占位规则给空值（DataSource 写入的除外）
    func isSuppressed(_ fieldKey: String) -> Bool {
        let a = auth[fieldKey]
        return a == "hidden" || a == "forbidden"
    }

    /// 需要用户填写的字段（非占位、非只读、非隐藏、非自动取数类）
    var editablePlugins: [ServiceFormPlugin] {
        plugins.filter { p in
            !Self.placeholderTypes.contains(p.type)
                && p.type != .user
                && p.type != .dataSource
                && !isReadOnly(p.key)
                && !isSuppressed(p.key)
        }
    }

    /// 只读展示字段：User 类（身份预填）或只读且有预填值
    var readonlyInfoPlugins: [ServiceFormPlugin] {
        plugins.filter { p in
            (p.type == .user || isReadOnly(p.key))
                && !isSuppressed(p.key)
                && ServiceFormDefinition.hasValue(data[p.key])
        }
    }

    /// DataSource 字段（需取数，如辅导员）
    var dataSourcePlugins: [ServiceFormPlugin] {
        plugins.filter { $0.type == .dataSource && $0.dataSource != nil }
    }

    /// 可应用的 ShowHide 规则（readable 的是审批侧规则，不作用于发起节点）
    var activeShowHidePlugins: [ServiceFormPlugin] {
        plugins.filter { p in
            p.type == .showHide
                && p.showHideRule != nil
                && !isReadOnly(p.key)
                && !isSuppressed(p.key)
        }
    }

    var dateOrderRules: [ServiceDateOrderRule] {
        plugins.compactMap(\.dateOrderRule)
    }

    /// 至少一个可编辑字段才可渲染，否则调用方走 fallback
    var isRenderable: Bool { !editablePlugins.isEmpty }

    func pluginByKey(_ key: String) -> ServiceFormPlugin? {
        plugins.first { $0.key == key }
    }

    /// 从 get-formv 的 d 与 start-data 定义合并构建；解析失败/无插件抛错走 fallback。
    static func build(
        appId: String,
        formvD: [String: Any],
        startData: ServiceFormDefinition
    ) throws -> ServiceFormSchema {
        let formId = ServiceFormPlugin.firstString(formvD, ["id", "form_id", "formId"])
            ?? (startData.currform.first.map { ServiceFormDefinition.anyToString($0) } ?? "")
        let formVersionId = ServiceFormPlugin.firstString(
            formvD, ["form_version_id", "version_id", "formVersionId"]
        ) ?? ""

        let allPlugins = try parseFormPlugins(
            formvD, formId: formId, formVersionId: formVersionId
        )
        guard !allPlugins.isEmpty else {
            throw SCUError.service("get-formv 无可解析插件")
        }
        let sorted = allPlugins.sorted { $0.sort < $1.sort }

        return ServiceFormSchema(
            appId: appId,
            formId: formId,
            formVersionId: formVersionId,
            plugins: sorted,
            auth: startData.auth,
            data: startData.data
        )
    }

    /// plugins 为 JSON 字符串（二次编码），解码后 {nowNum, plugins: {K: P}, rtplugins}
    private static func parseFormPlugins(
        _ formvD: [String: Any],
        formId: String,
        formVersionId: String
    ) throws -> [ServiceFormPlugin] {
        var pluginsRaw: Any? = formvD["plugins"]
        if let decoded = ServiceFormPlugin.decodeJsonString(pluginsRaw) {
            pluginsRaw = decoded
        }
        if let map = pluginsRaw as? [String: Any], let inner = map["plugins"] {
            pluginsRaw = inner
        }

        var entries: [(String?, [String: Any])] = []
        if let list = pluginsRaw as? [[String: Any]] {
            for item in list {
                entries.append((nil, item))
            }
        } else if let map = pluginsRaw as? [String: Any] {
            for (k, v) in map {
                if let item = v as? [String: Any] {
                    entries.append((k, item))
                }
            }
        }
        return try entries.map { fallbackKey, json in
            try ServiceFormPlugin.fromJson(
                json,
                formId: formId,
                formVersionId: formVersionId,
                fallbackKey: fallbackKey
            )
        }
    }
}

// MARK: - 350 硬编码兜底（service_form_fields.dart）

/// 请假表单字段元数据（app_id=350 真实表单，引擎解析失败时的兜底）。
enum ServiceFormFields {
    static let leaveDateKey = "Calendar_25"
    static let returnDateKey = "Calendar_26"
    static let detailKey = "MultiInput_40"
    static let regionKey = "Region_80"

    static let campusOptions: [ServiceFieldOption] = [
        ServiceFieldOption(value: "1", label: "望江校区"),
        ServiceFieldOption(value: "2", label: "华西校区"),
        ServiceFieldOption(value: "3", label: "江安校区"),
    ]

    static let reasonOptions: [ServiceFieldOption] = [
        ServiceFieldOption(value: "1", label: "实习"),
        ServiceFieldOption(value: "2", label: "求职"),
        ServiceFieldOption(value: "3", label: "探亲访友"),
        ServiceFieldOption(value: "4", label: "就医"),
        ServiceFieldOption(value: "5", label: "出差"),
        ServiceFieldOption(value: "6", label: "回家"),
        ServiceFieldOption(value: "7", label: "其它"),
    ]

    static let regionHint = "选择省份、城市、区县并填写详细地址"

    /// 只读展示字段（User_21~24）
    static let readonlyInfo: [(key: String, label: String)] = [
        ("User_21", "学号"),
        ("User_22", "姓名"),
        ("User_23", "学院"),
        ("User_24", "手机号"),
    ]
}
