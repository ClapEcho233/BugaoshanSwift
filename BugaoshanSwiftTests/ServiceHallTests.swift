import XCTest
@testable import BugaoshanSwift

/// 办事大厅动态表单引擎核心（插件解析 / ShowHide 求值 / 序列化 / 控制器）
final class ServiceHallTests: XCTestCase {

    // MARK: - ShowHide 表达式

    func testEvalExpressions() {
        XCTAssertEqual(evalServiceShowHideExpression("true", valueOf: { _ in nil }), true)
        XCTAssertEqual(evalServiceShowHideExpression("false", valueOf: { _ in nil }), false)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Radio_67}==7", valueOf: { _ in "7" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Radio_67}!=7", valueOf: { _ in "7" }), false)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Input_1}==''", valueOf: { _ in "" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Input_1}!=''", valueOf: { _ in "x" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Radio_67}.indexOf(7)!==-1", valueOf: { _ in "7" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Radio_67}.indexOf(7)==-1", valueOf: { _ in "7" }), false)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Select_1}[0].value==5", valueOf: { _ in "5" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Select_1}[0]==5", valueOf: { _ in "5" }), true)
        XCTAssertEqual(evalServiceShowHideExpression("{p_Calendar_25}!='' || {p_Calendar_26}!=''",
                                                     valueOf: { key in key == "Calendar_25" ? "2026-08-10" : nil }), true)
        // 未支持形态 → nil（不命中）
        XCTAssertNil(evalServiceShowHideExpression("Math.random()", valueOf: { _ in nil }))
    }

    func testEvalDateComparison() {
        let expr = "new Date({p_Calendar_25}) <= new Date('2026-08-10')"
        XCTAssertEqual(evalServiceShowHideExpression(expr, valueOf: { _ in "2026-08-10" }), true)
        XCTAssertEqual(evalServiceShowHideExpression(expr, valueOf: { _ in "2026-08-11" }), false)
        // 截断时区（'2026-08-10T17:10:21+'）也能解析：仍早于 08-12
        XCTAssertEqual(evalServiceShowHideExpression("new Date({p_Calendar_25}) < new Date('2026-08-12')",
                                                     valueOf: { _ in "2026-08-10T17:10:21+" }), true)
    }

    // MARK: - 插件解析

    func testPluginFromJsonDoubleEncodedAttr() throws {
        let attrData: [String: Any] = ["data": ["name": "发起者.学号", "placeholder": "请输入"]]
        let attrString = String(data: try JSONSerialization.data(withJSONObject: attrData), encoding: .utf8)!
        let pluginJson: [String: Any] = [
            "key": "Input_84", "type": "dInput", "description": "辅导员",
            "sort": 80, "attr": attrString,
        ]
        let plugin = try ServiceFormPlugin.fromJson(pluginJson, formId: "1419")
        XCTAssertEqual(plugin.key, "Input_84")
        XCTAssertEqual(plugin.type, .input)
        XCTAssertEqual(plugin.label, "辅导员")  // description 优先于 attr.data.name
        XCTAssertEqual(plugin.hint, "请输入")
    }

    func testFieldTypeResolution() {
        XCTAssertEqual(resolveServiceFieldType("dRadio", "Radio_30"), .radio)
        XCTAssertEqual(resolveServiceFieldType("dSelectV2", "x"), .selectV2)
        XCTAssertEqual(resolveServiceFieldType("dmultiText", "x"), .multiInput)
        XCTAssertEqual(resolveServiceFieldType(nil, "Radio_30"), .radio)
        XCTAssertEqual(resolveServiceFieldType(nil, "Ximage_64"), .file)
        XCTAssertEqual(resolveServiceFieldType(nil, "MultiText_1"), .multiInput)
        XCTAssertEqual(resolveServiceFieldType(nil, "Text_39"), .text)
        XCTAssertEqual(resolveServiceFieldType("dUnknown", "Weird_1"), .unknown)
    }

    // MARK: - Schema 构建

    func testSchemaBuildMergesPluginsAndAuth() throws {
        let plugins: [String: Any] = [
            "Radio_30": ["key": "Radio_30", "type": "dRadio", "description": "离开校区",
                         "sort": 10, "attr": ["data": ["options": [
                             ["value": "1", "name": "望江校区"],
                             ["value": "3", "name": "江安校区"],
                         ]]]],
            "Calendar_25": ["key": "Calendar_25", "type": "dCalendar", "description": "离校时间", "sort": 2],
        ]
        let pluginsString = String(data: try JSONSerialization.data(withJSONObject: plugins), encoding: .utf8)!
        let formvD: [String: Any] = ["id": 1419, "form_version_id": 2357, "plugins": pluginsString]
        let startData = ServiceFormDefinition.fromJson([
            "currform": [1419],
            "auth": ["1419": ["Radio_30": "require", "Calendar_25": "require"]],
            "data": ["1419": ["User_21": "2021141463017"]],
        ])
        let schema = try ServiceFormSchema.build(appId: "350", formvD: formvD, startData: startData)
        XCTAssertEqual(schema.formId, "1419")
        XCTAssertEqual(schema.formVersionId, "2357")
        XCTAssertEqual(schema.plugins.count, 2)
        // sort 2 在前
        XCTAssertEqual(schema.plugins.first?.key, "Calendar_25")
        XCTAssertEqual(schema.editablePlugins.map(\.key), ["Calendar_25", "Radio_30"])
        XCTAssertTrue(schema.isRenderable)
        XCTAssertTrue(schema.isRequired("Radio_30"))
        XCTAssertEqual(schema.plugins.last?.options.map(\.label), ["望江校区", "江安校区"])
    }

    // MARK: - 350 fallback + 控制器

    private func leaveController() -> ServiceFormController {
        let startData = ServiceFormDefinition.fromJson([
            "currform": [1419],
            "auth": ["1419": [
                "Radio_30": "require", "Radio_67": "require", "Calendar_25": "require",
                "Calendar_26": "require", "Region_80": "require", "MultiInput_40": "writable",
                "File_71": "writable", "User_21": "readable", "User_22": "readable",
                "Input_84": "front_readonly", "DataSource_85": "writable",
                "Variate_75": "writable", "Conversion_74": "writable",
            ]],
            "data": ["1419": ["User_21": "2021141463017", "User_22": "张三", "Calendar_25": ""]],
        ])
        return ServiceFormController(
            schema: buildLeaveFallbackSchema(startData),
            overrides: app350Overrides
        )
    }

    func testFallbackShowHideTogglesDetail() {
        let controller = leaveController()
        let detail = controller.schema.pluginByKey(ServiceFormFields.detailKey)!
        // 初始（未选事由）：MultiInput_40 隐藏（默认条件 isShow=false）
        XCTAssertFalse(controller.isFieldVisible(detail))
        XCTAssertFalse(controller.isFieldRequired(detail.key))
        // 选「其它」(7)：显示并必填
        controller.values["Radio_67"] = "7"
        XCTAssertTrue(controller.isFieldVisible(detail))
        XCTAssertTrue(controller.isFieldRequired(detail.key))
    }

    func testValidateRequiredAndDateOrder() {
        let controller = leaveController()
        controller.values["Radio_30"] = "3"
        controller.values["Radio_67"] = "6"
        controller.values[ServiceFormFields.leaveDateKey] = parseServiceDate("2026-09-20")
        controller.values["Region_80"] = ServiceRegionSelection(
            province: ServiceRegionNode(label: "四川省", value: "510000", children: [], childrenIsList: false),
            details: "XX路1号"
        )
        // 返校时间未填 → required
        var issue = controller.validate()
        XCTAssertEqual(issue?.fieldKey, ServiceFormFields.returnDateKey)
        XCTAssertEqual(issue?.kind, .required)
        // 返校早于离校 → 附加校验（返校必须晚于离校）
        controller.values[ServiceFormFields.returnDateKey] = parseServiceDate("2026-09-19")
        issue = controller.validate()
        XCTAssertEqual(issue?.kind, .custom)
        XCTAssertEqual(issue?.message, "返校时间必须晚于离校时间")
        // 合法
        controller.values[ServiceFormFields.returnDateKey] = parseServiceDate("2026-09-21")
        XCTAssertNil(controller.validate())
    }

    func testBuildFormFields350Shape() throws {
        let controller = leaveController()
        controller.values["Radio_30"] = "3"
        controller.values["Radio_67"] = "6"
        controller.values[ServiceFormFields.leaveDateKey] = parseServiceDate("2026-09-20")
        controller.values[ServiceFormFields.returnDateKey] = parseServiceDate("2026-09-21")
        controller.values["Input_84"] = "李辅导员"
        controller.values["DataSource_85"] = "李辅导员"

        let fields = controller.buildFormFields()
        XCTAssertEqual(controller.schema.formId, "1419")
        XCTAssertEqual(controller.buildFormData().count, 1)

        // radio → {value, name}
        let radio = try XCTUnwrap(fields["Radio_30"] as? [String: Any])
        XCTAssertEqual(radio["value"] as? String, "3")
        XCTAssertEqual(radio["name"] as? String, "江安校区")
        // calendar → UTC ISO：Asia/Shanghai 零点 = 前一日 16:00Z（与 Dart 设备 toIso8601String 一致）
        XCTAssertEqual(fields[ServiceFormFields.leaveDateKey] as? String, "2026-09-19T16:00:00.000Z")
        // 占位类型提交 ''/[]
        XCTAssertEqual(fields["Variate_75"] as? String, "")
        XCTAssertEqual((fields["Conversion_74"] as? [Any])?.count, 0)
        // DataSource 配对：{list:name} + resultKey Input
        let ds = try XCTUnwrap(fields["DataSource_85"] as? [String: Any])
        XCTAssertEqual(ds["list"] as? String, "李辅导员")
        XCTAssertEqual(fields["Input_84"] as? String, "李辅导员")
        // 未选「其它」→ MultiInput_40 条件隐藏提交 ''
        XCTAssertEqual(fields[ServiceFormFields.detailKey] as? String, "")
        // File_71 空提交 []
        XCTAssertEqual((fields["File_71"] as? [Any])?.count, 0)
    }

    func testBuildFormFieldsDataSourceEmptyOmitted() {
        let controller = leaveController()
        // 未取到辅导员：DataSource_85 与 Input_84 整对省略（350 已验证行为）
        let fields = controller.buildFormFields()
        XCTAssertNil(fields["DataSource_85"])
        XCTAssertNil(fields["Input_84"])
    }

    // MARK: - Region

    func testRegionMunicipalityAndSerialization() {
        // 直辖市：children 为 list 且区无下级
        let beijing = ServiceRegionNode(
            label: "北京市", value: "110000",
            children: [
                ServiceRegionNode(label: "东城区", value: "110101", children: [], childrenIsList: true),
            ],
            childrenIsList: true
        )
        XCTAssertTrue(beijing.isMunicipality)
        // 普通省：children 为 dict 形式（在线接口）
        let guangdongJson: [String: Any] = [
            "label": "广东省", "value": "440000",
            "children": ["1": ["label": "广州市", "value": "440100",
                               "children": [["label": "天河区", "value": "440106"]]]],
        ]
        let guangdong = ServiceRegionNode.fromJson(guangdongJson)
        XCTAssertFalse(guangdong.isMunicipality)
        XCTAssertEqual(guangdong.children.first?.label, "广州市")
        XCTAssertEqual(guangdong.children.first?.children.first?.value, "440106")

        let selection = ServiceRegionSelection(
            province: guangdong,
            city: guangdong.children.first,
            area: guangdong.children.first?.children.first,
            details: "XX路1号"
        )
        let data = selection.toRegionData()
        let province = data["province"] as? [String: String]
        XCTAssertEqual(province?["value"], "440000")
        XCTAssertEqual(data["address"] as? String, "广东省/广州市/天河区/XX路1号")
    }

    func testNormalizeRegionCode() {
        XCTAssertEqual(normalizeRegionCode("11"), "110000")
        XCTAssertEqual(normalizeRegionCode("1101"), "110100")
        XCTAssertEqual(normalizeRegionCode("110101"), "110101")
    }

    // MARK: - DataSource setplugin 分发

    func testApplyDataSourceSetPluginFanOut() {
        let startData = ServiceFormDefinition.fromJson([
            "currform": [1396],
            "auth": ["1396": ["DataSource_163": "writable", "User_156": "front_readonly",
                              "Input_162": "front_readonly"]],
            "data": ["1396": [:]],
        ])
        let mapConfig = ["User_156": "grade", "Input_162": "back_date"]
        let schema = ServiceFormSchema(
            appId: "337", formId: "1396", formVersionId: "2358",
            plugins: [
                ServiceFormPlugin(key: "DataSource_163", type: .dataSource, label: "数据源", sort: 1,
                                  options: [], hint: nil, maxCount: 3,
                                  dataSource: ServiceDataSourceRef(id: "11", formVersionId: "2358",
                                                                   component: "DataSource_163", formId: "1396",
                                                                   resultKey: "setplugin", mapConfig: mapConfig),
                                  dateOrderRule: nil, showHideRule: nil, raw: [:]),
                ServiceFormPlugin(key: "Input_162", type: .calendar, label: "返校日期", sort: 2,
                                  options: [], hint: nil, maxCount: 3, dataSource: nil,
                                  dateOrderRule: nil, showHideRule: nil, raw: [:]),
                ServiceFormPlugin(key: "User_156", type: .user, label: "年级", sort: 3,
                                  options: [], hint: nil, maxCount: 3, dataSource: nil,
                                  dateOrderRule: nil, showHideRule: nil, raw: [:]),
            ],
            auth: startData.auth, data: startData.data
        )
        let controller = ServiceFormController(schema: schema)
        let plugin = controller.schema.pluginByKey("DataSource_163")!
        controller.applyDataSourceValue(plugin, ["grade": "2021级", "back_date": "2026-08-30"])
        XCTAssertEqual(controller.values["User_156"] as? String, "2021级")
        XCTAssertEqual((controller.values["Input_162"] as? Date), parseServiceDate("2026-08-30"))
    }
}
