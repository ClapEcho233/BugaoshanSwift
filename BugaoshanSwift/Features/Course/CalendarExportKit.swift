import Foundation
import EventKit
import SwiftUI

// MARK: - 日历事件载荷（calendar_event_models.dart + AppDelegate payload 协议）

/// 单条日历事件（供系统日历导入；ICS 由 IcsBuilder 直接生成）
struct CalendarEventPayload {
    var title: String
    var location: String
    var notes: String
    var uid: String
    var timeZone: String = "Asia/Shanghai"
    var start: DateComponents
    var end: DateComponents

    static func dateComponents(_ date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.timeZone = timeZone
        return comps
    }
}

// MARK: - 事件构建（ics_service.dart 生成逻辑）

enum CalendarEventBuilder {

    /// 课程逐周事件（uid = courseId_week@bugaoshan，跨版本去重）
    static func courseEvents(
        config: ScheduleConfig, courses: [Course], teacherLabel: String = "教师"
    ) -> [CalendarEventPayload] {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var events: [CalendarEventPayload] = []
        for course in courses {
            guard !config.timeSlots.isEmpty else { continue }
            for week in course.startWeek...course.endWeek where course.isActive(inWeek: week) {
                guard course.startSection >= 1,
                      course.startSection <= config.timeSlots.count,
                      course.endSection <= config.timeSlots.count else { continue }
                let date = config.dateForCourseDay(week: week, dayOfWeek: course.dayOfWeek)
                let startSlot = config.timeSlots[course.startSection - 1]
                let endSlot = config.timeSlots[course.endSection - 1]
                let start = calendar.date(
                    bySettingHour: startSlot.startHour, minute: startSlot.startMinute,
                    second: 0, of: date
                )!
                let end = calendar.date(
                    bySettingHour: endSlot.endHour, minute: endSlot.endMinute,
                    second: 0, of: date
                )!
                let location = CalendarLocationMapper.resolve(course.location, campusName: course.campus)
                events.append(CalendarEventPayload(
                    title: course.name,
                    location: location.title,
                    notes: "\(teacherLabel): \(course.teacher)",
                    uid: "\(course.id)_\(week)@bugaoshan",
                    start: CalendarEventPayload.dateComponents(start, timeZone: timeZone),
                    end: CalendarEventPayload.dateComponents(end, timeZone: timeZone)
                ))
            }
        }
        return events
    }

    /// 考试事件（uid = exam-sha1(规范化名)@bugaoshan；「已结束」标记不影响去重）
    static func examEvents(exams: [(name: String, week: String, date: String, timeRange: String,
                                    location: String, seatNumber: String, ticketNumber: String, tip: String)]) -> [CalendarEventPayload] {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var events: [CalendarEventPayload] = []
        for exam in exams {
            guard let start = parseExamDateTime(exam.date, exam.timeRange),
                  let end = start.end else { continue }
            let courseName = IcsBuilder.normalizeExamName(exam.name)
            let location = CalendarLocationMapper.resolve(exam.location)
            var notes = [exam.week]
            if !exam.seatNumber.isEmpty { notes.append("座位号: \(exam.seatNumber)") }
            if !exam.ticketNumber.isEmpty { notes.append("准考证号: \(exam.ticketNumber)") }
            if !exam.tip.isEmpty && exam.tip != "无" { notes.append("提示: \(exam.tip)") }
            events.append(CalendarEventPayload(
                title: courseName.hasSuffix("考试") ? courseName : courseName + "考试",
                location: location.title,
                notes: notes.joined(separator: "\n"),
                uid: "exam-\(IcsBuilder.uidHash("exam|\(courseName)"))@bugaoshan",
                start: CalendarEventPayload.dateComponents(start.start, timeZone: timeZone),
                end: CalendarEventPayload.dateComponents(end, timeZone: timeZone)
            ))
        }
        return events
    }

    /// 校历事件（与 IcsBuilder.academicCalendarIcs 同构的 UID 方案）
    static func academicEvents(semester: AcademicCalendarSemester) -> [CalendarEventPayload] {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var events: [CalendarEventPayload] = []
        for event in semester.events {
            let startComps = calendar.dateComponents([.year, .month, .day], from: event.date)
            let endComps = calendar.dateComponents([.year, .month, .day], from: event.endDate ?? event.date)
            let start = calendar.date(
                bySettingHour: 8, minute: 0, second: 0, of: event.date
            ) ?? event.date
            let end = calendar.date(
                bySettingHour: 18, minute: 0, second: 0,
                of: calendar.date(from: endComps) ?? event.date
            ) ?? event.date
            let millis = Int(event.date.timeIntervalSince1970 * 1000)
            events.append(CalendarEventPayload(
                title: event.label,
                location: "四川大学",
                notes: "四川大学官方校历日程\n类型: \(event.tag)",
                uid: "acad-\(semester.name.replacingOccurrences(of: " ", with: "_"))-\(event.label.replacingOccurrences(of: " ", with: "_"))-\(millis)@bugaoshan",
                start: CalendarEventPayload.dateComponents(start, timeZone: timeZone),
                end: CalendarEventPayload.dateComponents(end, timeZone: timeZone)
            ))
            _ = startComps
        }
        return events
    }

    /// '2026-01-10' + '08:00-10:00' → (start, end)；不匹配返回 nil
    private static func parseExamDateTime(_ date: String, _ range: String) -> (start: Date, end: Date?)? {
        let dateParts = date.split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]) else {
            return nil
        }
        let rangeParts = range.split(separator: "-")
        guard rangeParts.count == 2 else { return nil }
        let startHM = rangeParts[0].split(separator: ":")
        let endHM = rangeParts[1].split(separator: ":")
        guard startHM.count == 2, endHM.count == 2,
              let sh = Int(startHM[0]), let sm = Int(startHM[1]),
              let eh = Int(endHM[0]), let em = Int(endHM[1]) else {
            return nil
        }
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let start = calendar.date(from: DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: sh, minute: sm)) else {
            return nil
        }
        let end = calendar.date(from: DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: eh, minute: em))
        return (start, end)
    }
}

// MARK: - 系统日历导入（AppDelegate.swift EventKit 逻辑原生版）

/// EventKit 无可写的隐藏 UID 字段：App 本地维护 uid → eventIdentifier 映射，
/// 重复导入走更新而非重建，日历里也不暴露内部链接。
struct CalendarImportService {

    static let uidMapDefaultsKey = "bugaoshan.calendar.uidMap"

    struct Destination: Identifiable, Equatable {
        var id: String { identifier }
        var identifier: String
        var title: String
        var sourceTitle: String
        var isDefault: Bool
    }

    enum ImportError: LocalizedError {
        case noWritableCalendars
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .noWritableCalendars: return "没有可写的日历"
            case .accessDenied: return "日历访问被拒绝，请在系统设置中授权"
            }
        }
    }

    private let store = EKEventStore()

    /// 申请只写权限（iOS 17+ NSCalendarsWriteOnlyAccessKey）
    func requestWriteAccess() async throws {
        let granted = await withCheckedContinuation { continuation in
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized, .writeOnly:
                continuation.resume(returning: true)
            case .notDetermined:
                store.requestWriteOnlyAccessToEvents { ok, _ in
                    continuation.resume(returning: ok)
                }
            default:
                continuation.resume(returning: false)
            }
        }
        guard granted else { throw ImportError.accessDenied }
    }

    /// 可写日历列表（默认日历置顶标记）
    func writableCalendars() -> [Destination] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { calendar in
                Destination(
                    identifier: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title,
                    isDefault: store.defaultCalendarForNewEvents?.calendarIdentifier == calendar.calendarIdentifier
                )
            }
            .filter { !$0.identifier.isEmpty && !$0.title.isEmpty }
    }

    private func targetCalendar(_ identifier: String?) -> EKCalendar? {
        guard let identifier, !identifier.isEmpty else {
            return store.defaultCalendarForNewEvents
        }
        guard let calendar = store.calendar(withIdentifier: identifier),
              calendar.allowsContentModifications else {
            return nil
        }
        return calendar
    }

    /// 批量导入（AppDelegate saveEvents 全逻辑）：UID 映射 + 内容键去重，
    /// 命中已有事件则原地更新；批量 commit。
    func importEvents(_ payloads: [CalendarEventPayload], calendarIdentifier: String?) throws {
        guard let target = targetCalendar(calendarIdentifier) else {
            throw ImportError.noWritableCalendars
        }
        var existingIndex = existingEventIndex(for: payloads, targetCalendar: target)
        var savedUidEvents: [(uid: String, event: EKEvent)] = []
        for payload in payloads {
            guard let event = makeEvent(payload, targetCalendar: target) else { continue }
            let eventToSave: EKEvent
            if let existing = matchingExistingEvent(for: payload, event: event, in: existingIndex) {
                copyFields(from: event, to: existing)
                eventToSave = existing
            } else {
                eventToSave = event
            }
            try store.save(eventToSave, span: .thisEvent, commit: false)
            if !payload.uid.isEmpty {
                savedUidEvents.append((payload.uid, eventToSave))
            }
            for key in eventKeys(uid: payload.uid, title: event.title,
                                 start: event.startDate, end: event.endDate) {
                existingIndex[key] = eventToSave
            }
        }
        try store.commit()
        rememberEventIdentifiers(savedUidEvents)
    }

    // MARK: - 事件构建/匹配

    private func makeEvent(_ payload: CalendarEventPayload, targetCalendar: EKCalendar) -> EKEvent? {
        let timeZone = TimeZone(identifier: payload.timeZone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let start = calendar.date(from: payload.start),
              let end = calendar.date(from: payload.end) else {
            return nil
        }
        let event = EKEvent(eventStore: store)
        event.title = payload.title
        event.location = payload.location.isEmpty ? nil : payload.location
        event.notes = payload.notes.isEmpty ? nil : payload.notes
        event.startDate = start
        event.endDate = end
        event.timeZone = timeZone
        event.calendar = targetCalendar
        return event
    }

    private func existingEventIndex(
        for payloads: [CalendarEventPayload], targetCalendar: EKCalendar
    ) -> [String: EKEvent] {
        // 事件日期范围（首日 0 点 ~ 末日次日 0 点）内拉取目标日历全部事件建索引
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dates: [Date] = []
        for payload in payloads {
            if let d = calendar.date(from: payload.start) { dates.append(d) }
            if let d = calendar.date(from: payload.end) { dates.append(d) }
        }
        guard let first = dates.min(), let last = dates.max(),
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else {
            return [:]
        }
        let predicate = store.predicateForEvents(
            withStart: calendar.startOfDay(for: first), end: endOfDay, calendars: [targetCalendar]
        )
        var index: [String: EKEvent] = [:]
        for event in store.events(matching: predicate) {
            for key in eventKeys(uid: nil, title: event.title, start: event.startDate, end: event.endDate) {
                index[key] = event
            }
        }
        return index
    }

    private func matchingExistingEvent(
        for payload: CalendarEventPayload, event: EKEvent, in existing: [String: EKEvent]
    ) -> EKEvent? {
        // 优先 UID 本地映射
        if !payload.uid.isEmpty,
           let mapped = eventForUid(payload.uid, targetCalendar: event.calendar) {
            return mapped
        }
        for key in eventKeys(uid: payload.uid, title: event.title, start: event.startDate, end: event.endDate) {
            if let hit = existing[key] {
                return hit
            }
        }
        return nil
    }

    private func eventKeys(uid: String?, title: String?, start: Date?, end: Date?) -> [String] {
        var keys: [String] = []
        if let uid, !uid.isEmpty {
            keys.append("uid:\(uid)")
        }
        if let title, let start, let end {
            keys.append(["content", title, String(Int(start.timeIntervalSince1970)), String(Int(end.timeIntervalSince1970))].joined(separator: "|"))
        }
        return keys
    }

    private func copyFields(from source: EKEvent, to target: EKEvent) {
        target.title = source.title
        target.location = source.location
        target.notes = source.notes
        target.startDate = source.startDate
        target.endDate = source.endDate
        target.timeZone = source.timeZone
        target.calendar = source.calendar
    }

    // MARK: - UID 本地映射（UserDefaults）

    private func eventForUid(_ uid: String, targetCalendar: EKCalendar) -> EKEvent? {
        guard let eventIdentifier = storedEventIdentifiers()[uid] else { return nil }
        guard let event = store.event(withIdentifier: eventIdentifier) else {
            forgetEventIdentifier(for: uid)
            return nil
        }
        guard event.calendar.calendarIdentifier == targetCalendar.calendarIdentifier else {
            return nil
        }
        return event
    }

    private func rememberEventIdentifiers(_ uidEvents: [(uid: String, event: EKEvent)]) {
        var identifiers = storedEventIdentifiers()
        for uidEvent in uidEvents {
            if let eventIdentifier = uidEvent.event.eventIdentifier {
                identifiers[uidEvent.uid] = eventIdentifier
            }
        }
        UserDefaults.standard.set(identifiers, forKey: Self.uidMapDefaultsKey)
    }

    private func forgetEventIdentifier(for uid: String) {
        var identifiers = storedEventIdentifiers()
        identifiers.removeValue(forKey: uid)
        UserDefaults.standard.set(identifiers, forKey: Self.uidMapDefaultsKey)
    }

    private func storedEventIdentifiers() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.uidMapDefaultsKey) as? [String: String] ?? [:]
    }
}

// MARK: - 导出动作弹层（calendar_export_utils.dart UI）

/// 导出选项（复制 JSON 由调用方自带；本弹层承载 ICS 与系统日历）
enum CalendarExportAction: Hashable {
    case ics
    case addToCalendar
}

struct CalendarExportSheet: View {
    let title: String
    /// ICS 内容（分享/预览）
    let icsContent: String
    let icsFileName: String
    /// 系统日历导入载荷
    let events: [CalendarEventPayload]
    var includeCopy = false
    var onCopy: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showCalendarPicker = false
    @State private var calendars: [CalendarImportService.Destination] = []
    @State private var importMessage: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                if includeCopy {
                    Button {
                        onCopy?()
                        dismiss()
                    } label: {
                        Label("复制课表数据", systemImage: "doc.on.doc")
                    }
                }
                if !events.isEmpty {
                    Button {
                        Task { await startImport() }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Label("添加到系统日历", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(isImporting)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if !icsContent.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: icsContent,
                            subject: Text(title),
                            preview: SharePreview(icsFileName)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                calendarPicker
            }
            .alert("提示", isPresented: Binding(
                get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var calendarPicker: some View {
        NavigationStack {
            List(calendars) { calendar in
                Button {
                    showCalendarPicker = false
                    Task { await importToCalendar(calendar.identifier) }
                } label: {
                    HStack {
                        Image(systemName: calendar.isDefault ? "star.circle" : "calendar")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.title)
                                .foregroundStyle(.primary)
                            if calendar.isDefault || !calendar.sourceTitle.isEmpty {
                                Text([calendar.isDefault ? "默认" : nil, calendar.sourceTitle.isEmpty ? nil : calendar.sourceTitle]
                                    .compactMap { $0 }
                                    .joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showCalendarPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func startImport() async {
        isImporting = true
        defer { isImporting = false }
        let service = CalendarImportService()
        do {
            try await service.requestWriteAccess()
            let list = service.writableCalendars()
            guard !list.isEmpty else {
                importMessage = "没有可写的日历"
                return
            }
            calendars = list
            showCalendarPicker = true
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func importToCalendar(_ identifier: String) async {
        isImporting = true
        defer { isImporting = false }
        do {
            try CalendarImportService().importEvents(events, calendarIdentifier: identifier)
            importMessage = "已添加到系统日历（\(events.count) 个事件）"
        } catch {
            importMessage = (error as? LocalizedError)?.errorDescription ?? "导入失败"
        }
    }
}
