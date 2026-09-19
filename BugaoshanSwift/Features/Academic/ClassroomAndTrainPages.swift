import SwiftUI

/// 空闲教室页（对应 classroom_page.dart）：校区→楼栋→教室三级下钻 + 节次状态网格
struct ClassroomPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var campuses: [ClassroomCampus] = []
    @State private var buildings: [ClassroomBuilding] = []
    @State private var selectedCampusNumber = ""
    @State private var selectedBuildingNumber = ""
    @State private var sectionFrom = 1
    @State private var sectionTo = 2
    @State private var queryDate = Date()
    @State private var result: ClassroomQueryResult?
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    private var buildingsForCampus: [ClassroomBuilding] {
        buildings.filter { $0.campusNumber == selectedCampusNumber }
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else {
                content
            }
        }
        .navigationTitle("空闲教室")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if campuses.isEmpty {
                await loadIndex()
            }
        }
        .refreshable {
            await loadIndex()
        }
    }

    private var content: some View {
        List {
            Section("条件") {
                Picker("校区", selection: $selectedCampusNumber) {
                    ForEach(campuses, id: \.campusNumber) { campus in
                        Text(campus.campusName).tag(campus.campusNumber)
                    }
                }
                Picker("楼栋", selection: $selectedBuildingNumber) {
                    ForEach(buildingsForCampus) { building in
                        Text(building.teachingBuildingName).tag(building.teachingBuildingNumber)
                    }
                }
                .disabled(selectedCampusNumber.isEmpty)
                DatePicker("日期", selection: $queryDate, displayedComponents: .date)
                HStack {
                    Picker("起节", selection: $sectionFrom) {
                        ForEach(1...12, id: \.self) { Text("第\($0)节").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("至").foregroundStyle(.secondary)
                    Picker("止节", selection: $sectionTo) {
                        ForEach(sectionFrom...12, id: \.self) { Text("第\($0)节").tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Button {
                    Task { await query() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("查询空闲教室")
                        }
                        Spacer()
                    }
                }
                .disabled(selectedCampusNumber.isEmpty || selectedBuildingNumber.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if let result {
                Section("结果（\(result.classrooms.count) 间 · 第 \(result.jxzc) 周）") {
                    if result.classrooms.isEmpty {
                        Text("该条件下无教室")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.classrooms) { classroom in
                        NavigationLink {
                            ClassroomDetailPage(classroom: classroom, result: result)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(classroom.classroomName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(classroom.placeNum) 座\(classroom.remark.isEmpty ? "" : " · \(classroom.remark)")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(freeCount(classroom, result: result))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func freeCount(_ classroom: ClassroomInfo, result: ClassroomQueryResult) -> String {
        let status = result.periodStatusMap(classroomNumber: classroom.classroomNumber)
        let free = (sectionFrom...sectionTo).filter { status[$0] == nil }.count
        return "\(free)/\(sectionTo - sectionFrom + 1) 空闲"
    }

    private func loadIndex() async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        needsLogin = false
        isLoading = true
        defer { isLoading = false }
        do {
            let index = try await api.fetchClassroomIndex()
            campuses = index.campuses
            buildings = index.buildings
            selectedCampusNumber = index.campuses.first?.campusNumber ?? ""
            selectedBuildingNumber = buildingsForCampus.first?.teachingBuildingNumber ?? ""
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func query() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            result = try await api.fetchClassroomAvailability(.init(
                campusNumber: selectedCampusNumber,
                buildingNumber: selectedBuildingNumber,
                typeCode: "",
                sectionFrom: sectionFrom,
                sectionTo: sectionTo,
                date: formatter.string(from: queryDate)
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 教室详情：全天节次状态（当前节高亮）
struct ClassroomDetailPage: View {
    let classroom: ClassroomInfo
    let result: ClassroomQueryResult

    private var statusMap: [Int: ClassroomPeriodStatus] {
        result.periodStatusMap(classroomNumber: classroom.classroomNumber)
    }

    private func statusColor(_ status: ClassroomPeriodStatus?) -> Color {
        switch status {
        case nil, .free: return .green
        case .inClass: return .orange
        case .exam: return .red
        case .experiment: return .purple
        case .borrowed: return .blue
        }
    }

    var body: some View {
        List {
            Section("教室信息") {
                LabeledContent("名称", value: classroom.classroomName)
                LabeledContent("容量", value: "\(classroom.placeNum) 座")
                if !classroom.remark.isEmpty {
                    LabeledContent("备注", value: classroom.remark)
                }
            }
            Section("节次状态（全天）") {
                ForEach(1...12, id: \.self) { section in
                    let status = statusMap[section]
                    HStack {
                        Text("第 \(section) 节")
                        Spacer()
                        Text(status?.label ?? "空闲")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.12), in: Capsule())
                            .foregroundStyle(statusColor(status))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(classroom.classroomName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 培养方案页（对应 train_program_page.dart）：学院/年级筛选 → 方案列表 → 课程明细
struct TrainProgramPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var colleges: [College] = []
    @State private var grades: [Grade] = []
    @State private var selectedCollege = ""
    @State private var selectedGrade = ""
    @State private var programs: [TrainProgram] = []
    @State private var isLoading = false
    @State private var needsLogin = false
    @State private var errorMessage: String?

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    var body: some View {
        Group {
            if needsLogin {
                ContentUnavailableView("未登录", systemImage: "person.badge.key")
            } else {
                list
            }
        }
        .navigationTitle("培养方案")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if colleges.isEmpty {
                await loadFilters()
            }
        }
        .refreshable {
            await loadFilters()
        }
    }

    private var list: some View {
        List {
            Section("筛选") {
                Picker("学院", selection: $selectedCollege) {
                    Text("全部").tag("")
                    ForEach(colleges) { Text($0.name).tag($0.value) }
                }
                Picker("年级", selection: $selectedGrade) {
                    Text("全部").tag("")
                    ForEach(grades) { Text($0.label).tag($0.value) }
                }
                Button {
                    Task { await search() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("查询")
                        }
                        Spacer()
                    }
                }
                .disabled(selectedCollege.isEmpty || isLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if !programs.isEmpty {
                Section("方案（\(programs.count)）") {
                    ForEach(programs) { program in
                        NavigationLink {
                            TrainProgramDetailPage(program: program)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.jhmc.isEmpty ? program.famc : program.jhmc)
                                    .font(.subheadline.weight(.medium))
                                Text("方案号 \(program.fajhh) · \(program.nj) 级")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadFilters() async {
        var ready = environment.authBus.scuState == .ready
        if !ready {
            ready = await environment.scuAuth.isReady
        }
        guard ready else {
            needsLogin = true
            return
        }
        needsLogin = false
        isLoading = true
        defer { isLoading = false }
        do {
            let filters = try await api.fetchTrainProgramFilters()
            colleges = filters.colleges
            grades = filters.grades
            selectedGrade = filters.grades.last?.value ?? ""
            errorMessage = nil
        } catch let error as SCUError where error.isUnauthenticated {
            needsLogin = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            programs = try await api.searchTrainPrograms(college: selectedCollege, grade: selectedGrade)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrainProgramDetailPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    let program: TrainProgram

    @State private var courses: [TrainProgramCourse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var api: ZhjwApiService {
        ZhjwApiService(auth: environment.zhjwAuth)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                List {
                    ForEach(courses) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.kcm)
                                .font(.subheadline.weight(.medium))
                            HStack(spacing: 8) {
                                if !course.xf.isEmpty { Text("\(course.xf) 学分") }
                                if !course.zxs.isEmpty { Text("\(course.zhsSafe) 学时") }
                                if !course.khfs.isEmpty { Text(course.khfs) }
                                if !course.kcgsdmName.isEmpty { Text(course.kcgsdmName) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(program.jhmc.isEmpty ? "方案明细" : program.jhmc)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                courses = try await api.fetchTrainProgramDetail(id: program.fajhh)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

extension TrainProgramCourse {
    var zhsSafe: String { zxs }
}
