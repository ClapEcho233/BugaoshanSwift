import Foundation

/// 校历服务（对应 lib/services/api/academic_calendar_service.dart）：
/// 内置压缩 JSON 展开 + 远程更新（GitHub raw 主源 + gh-proxy 镜像）+ UserDefaults 缓存。
actor AcademicCalendarService {

    static let remoteUrl = "https://raw.githubusercontent.com/The-Brotherhood-of-SCU/Bugaoshan/main/assets/academic_calendar.json"
    static let mirrorUrl = "https://gh-proxy.com/https://raw.githubusercontent.com/The-Brotherhood-of-SCU/Bugaoshan/main/assets/academic_calendar.json"

    private let transport: HTTPTransport
    private let defaults: DefaultsStore

    init(transport: HTTPTransport = URLSessionTransport(), defaults: DefaultsStore = UserDefaultsStore()) {
        self.transport = transport
        self.defaults = defaults
    }

    /// 内置校历（bundle 资源）
    static func loadBundled() -> AcademicCalendarData? {
        guard let url = Bundle.main.url(forResource: "academic_calendar", withExtension: "json"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return expandCalendarJson(raw)
    }

    /// 压缩格式 → 模型格式（已是展开格式则原样解析）
    /// 顶层 eventTypes（key → {l, t}）+ semesters: [{n, s, w, e: {typeKey: "日" | ["起","止"]}}]
    static func expandCalendarJson(_ raw: String) -> AcademicCalendarData? {
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // 已展开格式（events 数组）
        if let semesters = root["semesters"] as? [[String: Any]],
           semesters.first?["events"] != nil || semesters.isEmpty {
            return try? JSONDecoder().decode(AcademicCalendarData.self, from: data)
        }
        guard let eventTypes = root["eventTypes"] as? [String: [String: Any]],
              let compactSemesters = root["semesters"] as? [[String: Any]] else {
            return nil
        }

        var result: [AcademicCalendarSemester] = []
        for semester in compactSemesters {
            guard let name = semester["n"] as? String,
                  let startString = semester["s"] as? String,
                  let start = ScheduleConfig.parseDate(startString) else { continue }
            let totalWeeks = semester["w"] as? Int ?? 20
            var events: [AcademicCalendarEvent] = []
            if let eventsMap = semester["e"] as? [String: Any] {
                for (typeKey, value) in eventsMap {
                    guard let meta = eventTypes[typeKey],
                          let label = meta["l"] as? String else { continue }
                    let tag = meta["t"] as? String ?? "event"
                    if let single = value as? String, let date = ScheduleConfig.parseDate(single) {
                        events.append(AcademicCalendarEvent(date: date, endDate: nil, label: label, tag: tag))
                    } else if let pair = value as? [String],
                              pair.count == 2,
                              let start = ScheduleConfig.parseDate(pair[0]),
                              let end = ScheduleConfig.parseDate(pair[1]) {
                        events.append(AcademicCalendarEvent(date: start, endDate: end, label: label, tag: tag))
                    }
                }
            }
            events.sort { $0.date < $1.date }
            result.append(AcademicCalendarSemester(
                name: name, startDate: start, totalWeeks: totalWeeks, events: events
            ))
        }
        return AcademicCalendarData(semesters: result)
    }

    /// 取校历：缓存 → 内置（启动即同步可用）；再异步尝试远程更新
    func loadCalendar() async -> AcademicCalendarData {
        if let cached = await cachedCalendar() {
            Task { await self.refreshFromRemote() }
            return cached
        }
        Task { await self.refreshFromRemote() }
        return Self.loadBundled() ?? AcademicCalendarData()
    }

    func cachedCalendar() async -> AcademicCalendarData? {
        guard let raw = await defaults.string(StorageKeys.cachedAcademicCalendarJson) else {
            return nil
        }
        return Self.expandCalendarJson(raw)
    }

    /// 远程更新（成功且 semesters 非空才写缓存，防空数据污染）
    func refreshFromRemote() async {
        for url in [Self.remoteUrl, Self.mirrorUrl] {
            if let raw = await fetchRaw(url) {
                if let calendar = Self.expandCalendarJson(raw), !calendar.semesters.isEmpty {
                    await defaults.setString(StorageKeys.cachedAcademicCalendarJson, raw)
                    return
                }
            }
        }
    }

    private func fetchRaw(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let resp = try await transport.request(
                HTTPRequest(method: "GET", url: url, headers: ["User-Agent": Constants.userAgent]))
            guard (200..<300).contains(resp.statusCode) else { return nil }
            return resp.bodyString
        } catch {
            return nil
        }
    }

    /// 按课表名匹配校历学期（findMatchingSemester 语义：提取学年 + 春/秋包含）。
    /// 教务标签「2026-2027学年秋」需命中校历「2026-2027学年秋季学期」。
    func findSemester(named name: String) async -> AcademicCalendarSemester? {
        let calendar = await loadCalendar()
        guard let yearMatch = RegexHelper.firstMatch(#"(\d{4})-(\d{4})"#, in: name),
              yearMatch.count > 2 else {
            return nil
        }
        let academicYear = "\(yearMatch[1])-\(yearMatch[2])"
        let isSpring = name.contains("春")
        let isFall = name.contains("秋")
        return calendar.semesters.first { semester in
            guard semester.name.contains(academicYear) else { return false }
            if isSpring { return semester.name.contains("春") }
            if isFall { return semester.name.contains("秋") }
            return true
        }
    }
}
