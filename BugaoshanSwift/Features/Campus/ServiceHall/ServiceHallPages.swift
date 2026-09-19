import SwiftUI
import PhotosUI
import Combine

// MARK: - 事项目录（service_app_catalog.dart）

/// 单个事项（办事大厅列表项）
struct ServiceAppInfo: Identifiable {
    var id: String { appId }
    let appId: String
    let icon: String              // SF Symbol
    let title: String
    let desc: String
    var overrides = ServiceAppOverrides()
    /// 实时表单定义失败时的硬编码 fallback（仅 350）；其他事项失败封闭
    var fallbackSchema: ((ServiceFormDefinition) -> ServiceFormSchema)? = nil
}

/// 350 覆盖配置：字段顺序修正（Calendar_25=2/Calendar_26=3 sort 异常）+
/// 返校晚于离校校验（服务端无对应 Validate 规则）
let app350Overrides = ServiceAppOverrides(
    fieldOrder: [
        "Radio_30",           // 离开校区
        "Radio_67",           // 事由
        ServiceFormFields.detailKey,     // 其他事由（条件显示）
        ServiceFormFields.leaveDateKey,  // 离校时间
        ServiceFormFields.returnDateKey, // 返校时间
        ServiceFormFields.regionKey,     // 目的地
        "File_71",            // 上传证明
    ],
    extraValidators: [leaveDateOrderValidator]
)

/// 返校时间（Calendar_26）必须晚于离校时间（Calendar_25）
private func leaveDateOrderValidator(_ c: ServiceFormController) -> ServiceValidationIssue? {
    if let start = (c.values[ServiceFormFields.leaveDateKey] ?? nil) as? Date,
       let end = (c.values[ServiceFormFields.returnDateKey] ?? nil) as? Date,
       end <= start {
        return ServiceValidationIssue(
            fieldKey: ServiceFormFields.returnDateKey,
            kind: .custom,
            message: "返校时间必须晚于离校时间"
        )
    }
    return nil
}

/// 硬编码元数据组装 350 fallback schema（实时定义失败时兜底，
/// 产出与已抓包验证的提交体逐字段相同的结构）。
func buildLeaveFallbackSchema(_ startData: ServiceFormDefinition) -> ServiceFormSchema {
    let formId = startData.currform.first.map { ServiceFormDefinition.anyToString($0) } ?? "1419"
    let formVersionId = "2357"

    func plugin(_ key: String, _ type: ServiceFieldType, label: String = "",
                sort: Int = 0, options: [ServiceFieldOption] = [],
                dataSource: ServiceDataSourceRef? = nil) -> ServiceFormPlugin {
        ServiceFormPlugin(key: key, type: type, label: label, sort: sort,
                          options: options, hint: nil, maxCount: 3,
                          dataSource: dataSource, dateOrderRule: nil,
                          showHideRule: nil, raw: [:])
    }

    var plugins: [ServiceFormPlugin] = []
    for (i, info) in ServiceFormFields.readonlyInfo.enumerated() {
        plugins.append(plugin(info.key, .user, label: info.label, sort: i + 1))
    }
    plugins.append(plugin("Radio_30", .radio, label: "离开校区", sort: 10, options: ServiceFormFields.campusOptions))
    plugins.append(plugin("Radio_67", .radio, label: "请假事由", sort: 20, options: ServiceFormFields.reasonOptions))
    plugins.append(plugin(ServiceFormFields.detailKey, .multiInput, label: "其他事由", sort: 30))
    plugins.append(plugin(ServiceFormFields.leaveDateKey, .calendar, label: "离校时间", sort: 40))
    plugins.append(plugin(ServiceFormFields.returnDateKey, .calendar, label: "返校时间", sort: 50))
    plugins.append(plugin(ServiceFormFields.regionKey, .region, label: "去往地址", sort: 60))
    plugins.append(plugin("File_71", .file, label: "上传证明", sort: 70))
    plugins.append(plugin("Input_84", .input, label: "辅导员", sort: 80))
    plugins.append(plugin("DataSource_85", .dataSource, label: "辅导员", sort: 90, dataSource: ServiceDataSourceRef(
        id: ServiceApiService.tutorDataSourceId,
        formVersionId: formVersionId,
        component: "DataSource_85",
        formId: "1419",
        resultKey: "Input_84"
    )))
    plugins.append(plugin("Variate_75", .variate, sort: 100))
    // ShowHide_44 真实规则（350 抓包确认）：选「其它」显示并必填 MultiInput_40
    plugins.append(ServiceFormPlugin(
        key: "ShowHide_44", type: .showHide, label: "", sort: 101,
        options: [], hint: nil, maxCount: 3, dataSource: nil, dateOrderRule: nil,
        showHideRule: ServiceShowHideRule(
            conditions: [
                ServiceShowHideCondition(name: "默认", expression: "true"),
                ServiceShowHideCondition(name: "其他", expression: "{p_Radio_67}.indexOf(7)!==-1"),
                ServiceShowHideCondition(name: "！其他", expression: "{p_Radio_67}.indexOf(7)==-1"),
            ],
            controls: [
                "0": ServiceShowHideControl(isShow: false, isRequired: false, clearWhenHidden: false,
                                            targets: ["MultiInput_40", "Text_39"]),
                "1": ServiceShowHideControl(isShow: true, isRequired: true, clearWhenHidden: false,
                                            targets: ["MultiInput_40", "Text_39"]),
                "2": ServiceShowHideControl(isShow: false, isRequired: false, clearWhenHidden: true,
                                            targets: ["MultiInput_40", "Text_39"]),
            ]
        ),
        raw: [:]
    ))
    plugins.append(plugin("ShowHide_83", .showHide, sort: 102))
    plugins.append(plugin("Validate_86", .validate, sort: 103))
    plugins.append(plugin("Conversion_74", .conversion, sort: 104))
    plugins.append(plugin("RepeatTable_76", .repeatTable, sort: 105))

    return ServiceFormSchema(
        appId: ServiceApiService.leaveAppId,
        formId: formId,
        formVersionId: formVersionId,
        plugins: plugins,
        auth: startData.auth,
        data: startData.data
    )
}

/// 办事大厅事项目录
let serviceAppCatalog: [ServiceAppInfo] = [
    ServiceAppInfo(
        appId: ServiceApiService.leaveAppId,
        icon: "checklist",
        title: "离校请假", desc: "提交离校请假申请",
        overrides: app350Overrides,
        fallbackSchema: buildLeaveFallbackSchema
    ),
    ServiceAppInfo(
        appId: ServiceApiService.returnReportAppId,
        icon: "house.and.flag.fill",
        title: "返校报备", desc: "提前报备返校行程"
    ),
    ServiceAppInfo(
        appId: ServiceApiService.summerLeaveAppId,
        icon: "sun.max.fill",
        title: "暑假离校", desc: "报备暑假离校行程"
    ),
    ServiceAppInfo(
        appId: ServiceApiService.stayRegisterAppId,
        icon: "building.2.fill",
        title: "留校登记", desc: "登记假期留校"
    ),
]

// MARK: - 办事大厅入口页（service_hall_page.dart）

struct ServiceHallPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    private var isLoggedIn: Bool { environment.authBus.scuState == .ready }

    var body: some View {
        Group {
            if isLoggedIn {
                List {
                    Section("可办理事项") {
                        ForEach(serviceAppCatalog) { app in
                            NavigationLink {
                                ServiceFormPage(app: app)
                            } label: {
                                catalogRow(icon: app.icon, title: app.title, desc: app.desc)
                            }
                        }
                    }
                    Section {
                        NavigationLink {
                            MyApplicationsPage()
                        } label: {
                            catalogRow(icon: "tray.full", title: "我的申请",
                                       desc: "查看请假、报备等申请记录")
                        }
                    }
                }
            } else {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            }
        }
        .navigationTitle("办事大厅")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func catalogRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 通用动态表单页（service_form_page.dart）

/// 字段结构由服务端驱动：start-data ∥ start-info → get-formv → 每事项 fallback。
/// 提交：校验 → 逐 File 上传 → 组装 form_data → POST /site/apps/launch。
struct ServiceFormPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    let app: ServiceAppInfo

    @StateObject private var holder = FormHolder()
    @State private var schemaLoading = false
    @State private var schemaLoadFailed = false
    @State private var needsLogin = false
    @State private var regions: [ServiceRegionNode] = []
    @State private var starterDepartId: String?
    @State private var submitting = false
    @State private var resetCounter = 0
    @State private var toastMessage: String?

    private var api: ServiceApiService {
        ServiceApiService(auth: environment.serviceAuth)
    }

    /// ObservableObject 包装（ServiceFormController 由 schema 构建后注入）
    final class FormHolder: ObservableObject {
        @Published var schema: ServiceFormSchema?
        var controller: ServiceFormController? {
            didSet {
                if let controller {
                    schema = controller.schema
                }
            }
        }
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if schemaLoading && holder.schema == nil {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if holder.schema == nil || holder.controller == nil {
                ContentUnavailableView {
                    Label("表单加载失败，请稍后重试", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") { Task { await loadSchema() } }
                }
            } else {
                formBody
            }
        }
        .navigationTitle(app.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRegions()
            if !schemaLoading && holder.schema == nil {
                await loadSchema()
            }
        }
        .alert(
            "提示",
            isPresented: Binding(get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(toastMessage ?? "")
        }
    }

    private var formBody: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let controller = holder.controller {
                    infoCard(controller)
                    ForEach(controller.displayPlugins, id: \.key) { plugin in
                        if plugin.type != .dataSource && controller.isFieldVisible(plugin) {
                            fieldView(controller, plugin)
                                .id("\(plugin.key)#\(resetCounter)")
                        }
                    }
                    Button {
                        Task { await submit(controller) }
                    } label: {
                        HStack {
                            Spacer()
                            if submitting {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("提交申请")
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(submitting)
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: 信息卡

    /// 服务端带出的 User 身份字段 + 单值 DataSource（如辅导员）。
    /// setplugin 分发型不在信息卡展示（效果经目标字段呈现）。
    @ViewBuilder
    private func infoCard(_ controller: ServiceFormController) -> some View {
        let schema = controller.schema
        let infoPlugins = schema.plugins.filter { p in
            p.type == .user
                && !schema.isSuppressed(p.key)
                && ServiceFormDefinition.hasValue(
                    controller.values[p.key] ?? schema.data[p.key] ?? nil
                )
        }
        let dsPlugins = schema.dataSourcePlugins.filter { $0.dataSource?.isSetPlugin != true }
        if !infoPlugins.isEmpty || !dsPlugins.isEmpty {
            VStack(spacing: 0) {
                ForEach(infoPlugins, id: \.key) { p in
                    infoRow(
                        controller.labelOf(p),
                        ServiceFormDefinition.anyToString(
                            (controller.values[p.key] ?? schema.data[p.key] ?? nil) ?? ""
                        )
                    )
                }
                ForEach(dsPlugins, id: \.key) { p in
                    infoRow(
                        dsLabel(p, schema: schema, controller: controller),
                        ServiceFormDefinition.anyToString((controller.values[p.key] ?? nil) ?? "")
                    )
                }
            }
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// DataSource 行标签优先取 resultKey 配对字段（'辅导员' 而非 '数据源-审批辅导员'）
    private func dsLabel(_ p: ServiceFormPlugin, schema: ServiceFormSchema,
                         controller: ServiceFormController) -> String {
        if let ref = p.dataSource, !ref.resultKey.isEmpty, !ref.isSetPlugin,
           let target = schema.pluginByKey(ref.resultKey), !target.label.isEmpty {
            return target.label
        }
        return controller.labelOf(p)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: 字段分发

    @ViewBuilder
    private func fieldView(_ controller: ServiceFormController, _ plugin: ServiceFormPlugin) -> some View {
        let label = controller.labelOf(plugin)
        let required = controller.isFieldRequired(plugin.key)
        let value = controller.values[plugin.key] ?? nil
        switch plugin.type {
        case .radio:
            ServiceRadioField(label: label, required: required, plugin: plugin,
                              value: value as? String) { v in
                controller.values[plugin.key] = v
            }
        case .select, .selectV2:
            ServiceSelectField(label: label, required: required, plugin: plugin,
                               value: value as? String) { v in
                controller.values[plugin.key] = v
            }
        case .checkbox:
            ServiceCheckboxField(label: label, required: required, plugin: plugin,
                                 values: (value as? Set<String>) ?? []) { v in
                controller.values[plugin.key] = v
            }
        case .calendar:
            ServiceCalendarField(label: label, required: required, plugin: plugin,
                                 value: value as? Date) { v in
                controller.values[plugin.key] = v
            }
        case .region:
            ServiceRegionField(label: label, required: required, plugin: plugin,
                               selection: value as? ServiceRegionSelection,
                               provinces: regions) { v in
                controller.values[plugin.key] = v
            }
        case .file:
            ServiceFileField(label: label, required: required, plugin: plugin,
                             files: (value as? [Any]) ?? []) { v in
                controller.values[plugin.key] = v
            }
        case .multiInput:
            ServiceMultiInputField(label: label, required: required, plugin: plugin,
                                   initialText: (value as? String) ?? "") { v in
                controller.values[plugin.key] = v
            }
        default:
            ServiceInputField(label: label, required: required, plugin: plugin,
                              initialText: (value as? String) ?? "") { v in
                controller.values[plugin.key] = v
            }
        }
    }

    // MARK: 加载

    /// schema 获取链：start-data ∥ start-info → get-formv → fallback（仅 350）→ 失败封闭
    private func loadSchema() async {
        guard !schemaLoading else { return }
        guard await ensureReady() else { return }
        schemaLoading = true
        schemaLoadFailed = false
        defer { schemaLoading = false }
        do {
            async let startInfoTask = api.fetchStartInfo(app.appId)
            // start-data 是 auth/data 唯一来源，必须成功
            let startData = try await api.fetchFormSchema(app.appId)
            // 先取发起人部门 id（get-formv 与 data-source 都带它；不阻塞）
            Task { await loadStarterDepartId() }
            do {
                let startInfoD = try await startInfoTask
                let bpmnId = ServiceFormDefinition.anyToString(startInfoD["bpmn_id"] ?? "")
                let formId = startData.currform.first.map { ServiceFormDefinition.anyToString($0) } ?? ""
                guard !bpmnId.isEmpty, !formId.isEmpty else {
                    throw SCUError.service("start-info 缺少 bpmn_id 或 currform")
                }
                let formvD = try await api.fetchFormPlugins(
                    bpmnId: bpmnId, formId: formId,
                    starterDepartId: starterDepartId ?? ServiceApiService.defaultStarterDepartId
                )
                holder.controller = try ServiceFormSchema.build(
                    appId: app.appId, formvD: formvD, startData: startData
                ).controller(overrides: app.overrides)
            } catch {
                AuthLogger.shared.w("SERVICE", "Live schema unavailable: \(error.localizedDescription)")
                if let fallback = app.fallbackSchema {
                    AuthLogger.shared.w("SERVICE", "appId=\(app.appId) 实时表单定义不可用，使用硬编码 fallback schema")
                    holder.controller = fallback(startData).controller(overrides: app.overrides)
                } else {
                    throw SCUError.service("appId=\(app.appId) 无可用表单定义")
                }
            }
            await loadDataSources()
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            AuthLogger.shared.e("SERVICE", "Schema load failed: \(error.localizedDescription)")
            schemaLoadFailed = true
        }
    }

    private func ensureReady() async -> Bool {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        if !ready { needsLogin = true }
        return ready
    }

    private func loadStarterDepartId() async {
        if let id = try? await api.fetchStarterDepartId(app.appId) {
            starterDepartId = id
        }
    }

    /// 逐个 DataSource 取数（如辅导员）；失败不阻塞（提交时整字段省略）
    private func loadDataSources() async {
        guard let controller = holder.controller else { return }
        let schema = controller.schema
        for p in schema.dataSourcePlugins {
            guard let ref = p.dataSource else { continue }
            if let d = try? await api.fetchDataSourceValue(
                appId: app.appId, ref: ref,
                starterDepartId: starterDepartId ?? ServiceApiService.defaultStarterDepartId
            ) {
                controller.applyDataSourceValue(p, d["list"])
            }
        }
    }

    /// 省市区：在线优先，失败回退本地 region_data.json
    private func loadRegions() async {
        guard regions.isEmpty else { return }
        var data: [Any]?
        if environment.authBus.scuState == .ready {
            data = try? await api.fetchProvinces()
        }
        if data == nil || data!.isEmpty {
            if let url = Bundle.main.url(forResource: "region_data", withExtension: "json"),
               let raw = try? Data(contentsOf: url),
               let list = try? JSONSerialization.jsonObject(with: raw) as? [Any] {
                data = list
            }
        }
        if let data {
            regions = data.compactMap { $0 as? [String: Any] }.map(ServiceRegionNode.fromJson)
        }
    }

    // MARK: 提交

    private func submit(_ controller: ServiceFormController) async {
        if let issue = controller.validate() {
            if issue.kind == .required {
                let label = controller.schema.pluginByKey(issue.fieldKey)
                    .map { controller.labelOf($0) } ?? issue.fieldKey
                toastMessage = "请填写\(label)"
            } else {
                toastMessage = issue.message ?? "结束时间需晚于开始时间"
            }
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            // 逐 File 字段上传附件，失败恢复本地列表保持 UI
            var backups: [String: Any?] = [:]
            for p in controller.schema.editablePlugins where p.type == .file && controller.isFieldVisible(p) {
                let files = controller.values[p.key] ?? nil
                backups[p.key] = files
                var uploaded = [Any]()
                if let list = files as? [Any] {
                    for item in list {
                        if let local = item as? ServiceLocalFile {
                            let attachment = try await api.uploadAttachment(
                                fileData: local.data,
                                fileName: local.fileName,
                                mimeType: local.mimeType,
                                appId: app.appId
                            )
                            uploaded.append(attachment)
                        }
                    }
                }
                controller.values[p.key] = uploaded
            }
            let formData = controller.buildFormData()
            if let encoded = try? JSONSerialization.data(withJSONObject: formData),
               let text = String(data: encoded, encoding: .utf8) {
                AuthLogger.shared.i("SERVICE", "submit appId=\(app.appId) payload=\(text)")
            }
            do {
                try await api.submitMatter(
                    app.appId, formData: formData,
                    starterDepartId: starterDepartId ?? ServiceApiService.defaultStarterDepartId
                )
            } catch {
                // 恢复本地 File 列表
                for (k, v) in backups {
                    controller.values[k] = v
                }
                throw error
            }
            toastMessage = "请假申请已提交"
            controller.resetToPrefill()
            resetCounter += 1
        } catch let error as SCUError where error.isUnauthenticated {
            toastMessage = "请先登录"
        } catch {
            AuthLogger.shared.e("SERVICE", "Submit error: \(error.localizedDescription)")
            toastMessage = "提交失败，请稍后重试"
        }
    }
}

extension ServiceFormSchema {
    /// 构建绑定 overrides 的控制器
    func controller(overrides: ServiceAppOverrides) -> ServiceFormController {
        ServiceFormController(schema: self, overrides: overrides)
    }
}

// MARK: - 字段组件（service_field_widgets.swift 化）

/// 字段类型图标（服务端不下发图标，按类型给默认 SF Symbol）
func iconForServiceFieldType(_ type: ServiceFieldType) -> String {
    switch type {
    case .input: return "square.and.pencil"
    case .multiInput: return "square.and.pencil"
    case .radio: return "circle.inset.filled"
    case .select, .selectV2: return "arrow.down.circle"
    case .checkbox: return "checkmark.square"
    case .calendar: return "calendar"
    case .region: return "mappin.and.ellipse"
    case .file: return "paperclip"
    case .dataSource: return "person.wave.2"
    case .user: return "person.text.rectangle"
    default: return "slider.horizontal.3"
    }
}

/// 字段卡片外壳：图标 + 标题 + 必填标记 + 内容
private struct ServiceFieldShell<Content: View>: View {
    let label: String
    let required: Bool
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                if required {
                    Text("*").foregroundStyle(.red)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 单选字段
struct ServiceRadioField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let value: String?
    let onChanged: (String) -> Void

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            VStack(spacing: 0) {
                ForEach(plugin.options, id: \.value) { opt in
                    Button {
                        onChanged(opt.value)
                    } label: {
                        HStack {
                            Image(systemName: value == opt.value ? "circle.inset.filled" : "circle")
                                .foregroundStyle(value == opt.value ? Color.accentColor : Color(.systemGray3))
                            Text(opt.label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if opt.value != plugin.options.last?.value {
                        Divider()
                    }
                }
            }
        }
    }
}

/// 下拉选择字段（Select/SelectV2 单值选择）
struct ServiceSelectField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let value: String?
    let onChanged: (String) -> Void

    private var selection: String {
        plugin.options.contains { $0.value == value } ? (value ?? "") : ""
    }

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            Picker(plugin.label, selection: Binding(
                get: { selection },
                set: { onChanged($0) }
            )) {
                Text(plugin.hint ?? "请选择").tag("")
                ForEach(plugin.options, id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 多选字段
struct ServiceCheckboxField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let values: Set<String>
    let onChanged: (Set<String>) -> Void

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            VStack(spacing: 0) {
                ForEach(plugin.options, id: \.value) { opt in
                    Button {
                        var next = values
                        if values.contains(opt.value) {
                            next.remove(opt.value)
                        } else {
                            next.insert(opt.value)
                        }
                        onChanged(next)
                    } label: {
                        HStack {
                            Image(systemName: values.contains(opt.value) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(values.contains(opt.value) ? Color.accentColor : Color(.systemGray3))
                            Text(opt.label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if opt.value != plugin.options.last?.value {
                        Divider()
                    }
                }
            }
        }
    }
}

/// 日期字段
struct ServiceCalendarField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let value: Date?
    let onChanged: (Date) -> Void

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            DatePicker(
                plugin.label,
                selection: Binding(
                    get: { value ?? Date() },
                    set: { onChanged($0) }
                ),
                in: Date().addingTimeInterval(-2 * 365 * 86400)...Date().addingTimeInterval(2 * 365 * 86400),
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 单行文本
struct ServiceInputField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    @State var initialText: String
    let onChanged: (String) -> Void

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            TextField(plugin.hint ?? "", text: $initialText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: initialText) { _, newValue in
                    onChanged(newValue)
                }
        }
    }
}

/// 多行文本（500 字）
struct ServiceMultiInputField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    @State var initialText: String
    let onChanged: (String) -> Void

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            ZStack(alignment: .topLeading) {
                if initialText.isEmpty {
                    Text(plugin.hint ?? "")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $initialText)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .onChange(of: initialText) { _, newValue in
                        if newValue.count > 500 {
                            initialText = String(newValue.prefix(500))
                        }
                        onChanged(initialText)
                    }
            }
        }
    }
}

/// 地区字段（省-市-区县三级级联 + 详细地址；直辖市跳过市级）
struct ServiceRegionField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let selection: ServiceRegionSelection?
    let provinces: [ServiceRegionNode]
    let onChanged: (ServiceRegionSelection) -> Void

    private var current: ServiceRegionSelection { selection ?? ServiceRegionSelection() }

    /// 市列表：直辖市为空（直接选区）
    private var cityOptions: [ServiceRegionNode] {
        guard let province = current.province, !province.isMunicipality else { return [] }
        return province.children
    }

    /// 区列表：直辖市取省 children，普通省取市 children
    private var areaOptions: [ServiceRegionNode] {
        if let province = current.province, province.isMunicipality {
            return province.children
        }
        return current.city?.children ?? []
    }

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            VStack(alignment: .leading, spacing: 8) {
                if provinces.isEmpty {
                    Text("地区数据加载中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("省份", selection: provinceBinding) {
                        Text("选择省份").tag("")
                        ForEach(provinces) { p in
                            Text(p.label).tag(p.value)
                        }
                    }
                    .pickerStyle(.menu)
                    if !cityOptions.isEmpty {
                        Picker("城市", selection: cityBinding) {
                            Text("选择城市").tag("")
                            ForEach(cityOptions) { c in
                                Text(c.label).tag(c.value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if !areaOptions.isEmpty {
                        Picker("区县", selection: areaBinding) {
                            Text("选择区县").tag("")
                            ForEach(areaOptions) { a in
                                Text(a.label).tag(a.value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    TextField("详细地址（街道、门牌号等）", text: detailBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var provinceBinding: Binding<String> {
        Binding(
            get: { current.province?.value ?? "" },
            set: { newValue in
                let province = provinces.first { $0.value == newValue }
                onChanged(ServiceRegionSelection(
                    province: province, city: nil, area: nil, details: current.details
                ))
            }
        )
    }

    private var cityBinding: Binding<String> {
        Binding(
            get: { current.city?.value ?? "" },
            set: { newValue in
                let city = cityOptions.first { $0.value == newValue }
                onChanged(ServiceRegionSelection(
                    province: current.province, city: city, area: nil, details: current.details
                ))
            }
        )
    }

    private var areaBinding: Binding<String> {
        Binding(
            get: { current.area?.value ?? "" },
            set: { newValue in
                let area = areaOptions.first { $0.value == newValue }
                onChanged(ServiceRegionSelection(
                    province: current.province, city: current.city, area: area, details: current.details
                ))
            }
        )
    }

    private var detailBinding: Binding<String> {
        Binding(
            get: { current.details },
            set: { newValue in
                onChanged(ServiceRegionSelection(
                    province: current.province, city: current.city, area: current.area, details: newValue
                ))
            }
        )
    }
}

/// 附件字段（PhotosPicker 选图，最多 maxCount 张）
struct ServiceFileField: View {
    let label: String
    let required: Bool
    let plugin: ServiceFormPlugin
    let files: [Any]
    let onChanged: ([Any]) -> Void

    @State private var pickerItem: PhotosPickerItem?

    private var localFiles: [ServiceLocalFile] {
        files.compactMap { $0 as? ServiceLocalFile }
    }

    private func mimeType(for fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".png") { return "image/png" }
        return "image/jpeg"
    }

    var body: some View {
        ServiceFieldShell(label: label, required: required, icon: iconForServiceFieldType(plugin.type)) {
            VStack(alignment: .leading, spacing: 8) {
                if localFiles.isEmpty {
                    Text("可上传 1-\(plugin.maxCount) 张图片作为请假证明（非必填）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(localFiles) { file in
                            thumb(file)
                        }
                        if localFiles.count < plugin.maxCount {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Image(systemName: "plus")
                                    .frame(width: 72, height: 72)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if localFiles.isEmpty {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("添加图片", systemImage: "photo.badge.plus")
                                .font(.footnote)
                        }
                    }
                }
            }
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self) {
                        let fileName = newValue.itemIdentifier ?? "attachment.jpg"
                        var next: [Any] = files
                        next.append(ServiceLocalFile(
                            fileName: fileName,
                            data: data,
                            mimeType: mimeType(for: fileName)
                        ))
                        onChanged(next)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private func thumb(_ file: ServiceLocalFile) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: file.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button {
                let next = files.filter { !($0 is ServiceLocalFile && ($0 as? ServiceLocalFile)?.id == file.id) }
                onChanged(next)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.black.opacity(0.6), in: Circle())
            }
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - 我的申请（my_applications_page.dart）

struct MyApplicationsPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var items: [[String: Any]] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var needsLogin = false
    @State private var errorMessage: String?

    private var api: ServiceApiService {
        ServiceApiService(auth: environment.serviceAuth)
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else if isLoading && !hasLoaded {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, !hasLoaded {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(force: true) } }
                }
            } else if items.isEmpty {
                ContentUnavailableView("暂无申请记录", systemImage: "tray")
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        applicationRow(item)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("我的申请")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasLoaded {
                await load(force: false)
            }
        }
        .refreshable {
            await load(force: true)
        }
    }

    private func applicationRow(_ item: [String: Any]) -> some View {
        let title = ServiceFormDefinition.anyToString(item["app_name"] ?? item["name"] ?? "")
        let created = ServiceFormDefinition.anyToString(item["created"] ?? item["create_time"] ?? "")
        let instStatus = ServiceFormDefinition.anyToString(item["inst_status"] ?? "")
        let status = ServiceFormDefinition.anyToString(item["status"] ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.isEmpty ? "请假申请" : title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                statusChip(instStatus: instStatus, status: status)
            }
            if !created.isEmpty {
                Text("提交时间: \(created)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// 优先服务端中文状态（inst_status），兜底数字 status 映射
    private func statusChip(instStatus: String, status: String) -> some View {
        let text = !instStatus.isEmpty ? instStatus : labelForStatus(status)
        let color = colorForStatus(status)
        return Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func labelForStatus(_ status: String) -> String {
        switch status {
        case "1", "7": return "审批中"
        case "0": return "草稿"
        case "2", "4": return "已完成"
        default: return status.isEmpty ? "—" : status
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "1", "7": return .orange
        case "0": return .gray
        case "2", "4": return .green
        default: return Color(.systemTeal)
        }
    }

    private func load(force: Bool) async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        if !force && hasLoaded { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.fetchMyApplications(status: 0)
            hasLoaded = true
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
