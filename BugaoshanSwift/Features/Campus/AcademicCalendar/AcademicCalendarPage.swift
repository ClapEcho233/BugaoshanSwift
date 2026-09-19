import SwiftUI

/// 事件类型 → 颜色（月历圆点与图例共用；五类五色相，区分明显）
extension AcademicCalendarEvent {
    var tint: Color {
        switch tag {
        case "holiday": return .red       // 假期
        case "exam": return .orange       // 考试
        case "start": return .green       // 开学/行课
        case "course": return .purple     // 实践/课程周
        default: return .indigo           // 其它活动
        }
    }
}

/// 校历页（对应 academic_calendar_page.dart）：交互式月历（事件高亮）+ 学期选择
struct AcademicCalendarPage: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var calendar: AcademicCalendarData?
    @State private var selectedSemesterIndex: Int = 0
    @State private var displayedMonth: Date = Date()
    @State private var showExportSheet = false
    @State private var isLoading = true
    @State private var loadError: String?

    private var monthGrid: [Date] {
        let cal = Calendar(identifier: .gregorian)
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let first = interval.start
        // 周一为首列
        let firstWeekday = first.dartWeekday
        let leading = firstWeekday - 1
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var currentSemester: AcademicCalendarSemester? {
        guard let calendar, selectedSemesterIndex < calendar.semesters.count else { return nil }
        return calendar.semesters[selectedSemesterIndex]
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载校历…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView {
                    Label("校历加载失败", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(loadError)
                }
            } else if let calendar {
                calendarBody(calendar)
            }
        }
        .navigationTitle("校历")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let semester = currentSemester, !semester.events.isEmpty {
                    Button {
                        showExportSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let semester = currentSemester {
                CalendarExportSheet(
                    title: "校历导出",
                    icsContent: IcsBuilder.academicCalendarIcs(semester: semester),
                    icsFileName: IcsBuilder.calendarFileName(semesterName: semester.name),
                    events: CalendarEventBuilder.academicEvents(semester: semester)
                )
            }
        }
        .task {
            let service = AcademicCalendarService()
            calendar = await service.loadCalendar()
            // 默认选当前学期（否则最后一个）；定位到今天所在月份（否则学期首月）
            if let index = calendar?.semesters.firstIndex(where: { $0.isDateInSemester(Date()) }) {
                selectedSemesterIndex = index
                displayedMonth = Date()
            } else if let last = calendar?.semesters.indices.last {
                selectedSemesterIndex = last
                displayedMonth = calendar!.semesters[last].startDate
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func calendarBody(_ data: AcademicCalendarData) -> some View {
        let semester = currentSemester
        VStack(spacing: 0) {
            // 学期选择（初始定位到当前选中项，避免从 2021 年开始展示）
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(data.semesters.indices, id: \.self) { index in
                        let item = data.semesters[index]
                        Group {
                        Button {
                            selectedSemesterIndex = index
                            displayedMonth = item.isDateInSemester(Date()) ? Date() : item.startDate
                        } label: {
                            Text(item.name)
                                .font(.caption.weight(selectedSemesterIndex == index ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedSemesterIndex == index
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(.secondarySystemBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedSemesterIndex == index ? Color.accentColor : .secondary)
                        }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(selectedSemesterIndex, anchor: .center)
                    }
                }
            }
            }

            monthHeader
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(monthGrid, id: \.self) { day in
                    dayCell(day, semester: semester)
                }
            }
            .padding(.horizontal, 8)

            // 当前学期信息
            if let semester {
                semesterInfo(semester)
            }
            Spacer(minLength: 0)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth)!
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(BeijingTime.format(displayedMonth, pattern: "yyyy年M月"))
                .font(.headline)
            Spacer()
            Button {
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth)!
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func dayCell(_ day: Date, semester: AcademicCalendarSemester?) -> some View {
        let events = semester?.events.filter { $0.isActive(on: day) } ?? []
        let isToday = Calendar.current.isDateInToday(day)
        let inMonth = Calendar.current.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let eventColor = events.first?.tint ?? Color.accentColor

        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color(.systemGray3)))
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
            Circle()
                .fill(events.isEmpty ? Color.clear : eventColor)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击日期：详情弹层（后续迭代补事件列表弹层）
        }
    }

    @ViewBuilder
    private func semesterInfo(_ semester: AcademicCalendarSemester) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(semester.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let week = semester.getCurrentWeek(on: Date()) {
                    Text("第 \(week) 周")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text("\(ScheduleConfig.formatDate(semester.startDate)) — \(ScheduleConfig.formatDate(semester.endDate)) · 共 \(semester.totalWeeks) 周")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 图例：本学期全部特殊事件（不只当前月）
            if !semester.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本学期特殊事件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(semester.events, id: \.label) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(event.tint)
                                .frame(width: 6, height: 6)
                            Text(event.label)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(eventDateText(event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    /// 图例日期文案：单日「9月10日」，区间「9月10日–10月7日」
    private func eventDateText(_ event: AcademicCalendarEvent) -> String {
        let start = BeijingTime.format(event.date, pattern: "M月d日")
        guard let end = event.endDate, end != event.date else { return start }
        return "\(start)–\(BeijingTime.format(end, pattern: "M月d日"))"
    }
}
