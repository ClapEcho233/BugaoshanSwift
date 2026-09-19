import Foundation

/// 上课地点 → 校区/建筑/房间 解析器（calendar_location_mapper.dart 全量移植，
/// 3 校区 + 56 建筑静态表）。匹配策略：1. campusName/location 识别校区；
/// 2. 最长 pattern 优先匹配建筑（字母结尾带座号 +1 权重）；3. 回退校区级推断。
enum CalendarLocationMapper {

    struct CampusGeoReference {
        var fullName: String
        var keywords: [String]
        var buildingKeywords: [String]
    }

    struct BuildingGeoReference {
        var campusName: String
        var canonicalBuildingName: String
        var matchPatterns: [String]
        var redirectNote: String?

        /// 命中的最高匹配得分（0 未命中）；最长 pattern 优先 + 字母结尾（带座号）+1
        func longestMatchLength(_ text: String) -> Int {
            var longest = 0
            for pattern in matchPatterns where !pattern.isEmpty && text.contains(pattern) {
                let endsWithLetter = pattern.last.map { $0.isASCII && $0.isLetter } == true
                let score = pattern.count + (endsWithLetter ? 1 : 0)
                if score > longest { longest = score }
            }
            return longest
        }
    }

    struct ResolvedLocation {
        var title: String
    }

    static let campusLocations: [CampusGeoReference] = [
        CampusGeoReference(fullName: "四川大学江安校区", keywords: ["江安"], buildingKeywords: ["一教", "第一教学楼", "启明楼", "二教", "第二教学楼", "综楼", "综合楼", "综合教学楼", "易明楼", "综A", "综B", "综C", "二基楼", "第二基础", "水明楼", "文科楼", "文襄楼", "匹兹堡", "灾后", "空天", "法学院", "艺术学院", "建环", "水利水电"]),
        CampusGeoReference(fullName: "四川大学望江校区", keywords: ["望江"], buildingKeywords: ["基础教学楼", "基础教学大楼", "基础楼", "启秀楼", "基A", "基B", "基C", "东三教", "东三教学楼", "汇文楼", "西三教", "西五教", "泓文楼", "物理馆", "化学馆", "校史馆", "水电大楼", "水电馆", "智行楼", "机械大楼", "机械馆", "纺织楼", "化工楼", "逸夫科技", "工科大楼"]),
        CampusGeoReference(fullName: "四川大学华西校区", keywords: ["华西"], buildingKeywords: ["八教", "第八教学楼", "启德堂", "老八教", "九教", "第九教学楼", "敬德堂", "十教", "第十教学楼", "仁德堂", "七教", "第七教学楼", "志德堂", "五教", "第五教学楼", "六教", "第六教学楼", "怀德堂", "药学大楼", "基础医学", "公卫大楼", "法医大楼", "口腔楼"]),
    ]

    static let buildingLocations: [BuildingGeoReference] = [
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第一教学楼A座", matchPatterns: ["一教A", "一教 A", "第一教学楼A", "第一教学楼 A", "启明楼A", "启明楼 A"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第一教学楼B座", matchPatterns: ["一教B", "一教 B", "第一教学楼B", "第一教学楼 B", "启明楼B", "启明楼 B"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第一教学楼C座", matchPatterns: ["一教C", "一教 C", "第一教学楼C", "第一教学楼 C", "启明楼C", "启明楼 C"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第一教学楼D座", matchPatterns: ["一教D", "一教 D", "第一教学楼D", "第一教学楼 D", "启明楼D", "启明楼 D"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第一教学楼", matchPatterns: ["一教", "第一教学楼", "启明楼"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第二教学楼", matchPatterns: ["二教", "第二教学楼"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "综合楼A座", matchPatterns: ["综A", "综 A", "综合楼A", "综合楼 A", "易明楼A", "易明楼 A"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "逸夫教学楼", matchPatterns: ["综B", "综 B", "综合楼B", "综合楼 B", "易明楼B", "易明楼 B"], redirectNote: "综B"),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "逸夫教学楼", matchPatterns: ["综C", "综 C", "综合楼C", "综合楼 C", "易明楼C", "易明楼 C"], redirectNote: "综C"),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "逸夫教学楼", matchPatterns: ["综楼", "综合楼", "综合教学楼", "易明楼", "逸夫教学楼", "逸夫楼"], redirectNote: "综合楼"),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "第二基础实验大楼", matchPatterns: ["二基楼", "第二基础实验", "第二基础", "水明楼"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "文科楼一区", matchPatterns: ["文科楼一区", "文科楼1区", "文科楼一", "文科楼1"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "文科楼二区", matchPatterns: ["文科楼二区", "文科楼2区", "文科楼二", "文科楼2"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "文科楼三区", matchPatterns: ["文科楼三区", "文科楼3区", "文科楼三", "文科楼3"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "文科楼四区", matchPatterns: ["文科楼四区", "文科楼4区", "文科楼四", "文科楼4"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "文科楼", matchPatterns: ["文科楼", "文襄楼"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "法学院", matchPatterns: ["法学院"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "艺术学院", matchPatterns: ["艺术学院", "艺术大楼"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "匹兹堡学院", matchPatterns: ["匹兹堡"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "灾后重建与管理学院", matchPatterns: ["灾后重建", "灾后"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "制造工程实验楼", matchPatterns: ["制造工程", "制造梦工厂", "基础力学", "土木结构"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "水利水电实验基地", matchPatterns: ["江安水电", "水利水电学院实验"]),
        BuildingGeoReference(campusName: "四川大学江安校区", canonicalBuildingName: "江安体育馆", matchPatterns: ["江安体育馆", "江安体育", "江安游泳池", "江安网球场", "江安田径场"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "基础教学楼A座", matchPatterns: ["基础教学楼A", "基础教学楼 A", "基教A", "基教 A", "基A", "基 A", "启秀楼A"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "基础教学楼B座", matchPatterns: ["基础教学楼B", "基础教学楼 B", "基教B", "基教 B", "基B", "基 B", "启秀楼B"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "基础教学楼C座", matchPatterns: ["基础教学楼C", "基础教学楼 C", "基教C", "基教 C", "基C", "基 C", "启秀楼C"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "基础教学楼", matchPatterns: ["基础教学楼", "基础教学大楼", "基础楼", "基教", "启秀楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "东三教学楼", matchPatterns: ["东三教", "东三教学楼", "东三", "汇文楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "东一教学楼", matchPatterns: ["东一教", "东一教学楼", "东一"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "东二教学楼", matchPatterns: ["东二教", "东二教学楼", "东二"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "望江文科楼", matchPatterns: ["望江文科楼", "泓文楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "物理馆", matchPatterns: ["物理馆", "物理楼", "第一理科楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "第二理科楼", matchPatterns: ["第二理科楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "化学馆", matchPatterns: ["化学馆", "化学楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "水电大楼", matchPatterns: ["水电大楼", "水电馆", "智行楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "逸夫科技楼", matchPatterns: ["逸夫科技楼", "逸夫楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "西四教", matchPatterns: ["西四教", "西五教", "西三教"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "机电科技楼", matchPatterns: ["机械大楼", "机械馆", "机电科技楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "纺工楼", matchPatterns: ["纺工楼", "纺织楼"]),
        BuildingGeoReference(campusName: "四川大学望江校区", canonicalBuildingName: "望江体育馆", matchPatterns: ["望江体育馆", "望江游泳池"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第八教学楼", matchPatterns: ["八教", "第八教学楼", "老八教", "启德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第九教学楼", matchPatterns: ["九教", "第九教学楼", "敬德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第十教学楼", matchPatterns: ["十教", "第十教学楼", "仁德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第七教学楼", matchPatterns: ["七教", "第七教学楼", "志德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第六教学楼", matchPatterns: ["六教", "第六教学楼", "万德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第五教学楼", matchPatterns: ["五教", "第五教学楼", "育德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第四教学楼", matchPatterns: ["四教", "第四教学楼", "合德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第三教学楼", matchPatterns: ["三教", "第三教学楼", "树德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第二教学楼", matchPatterns: ["华西二教", "华西第二教学楼", "懿德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "第一教学楼", matchPatterns: ["华西一教", "华西第一教学楼", "嘉德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "办公楼（怀德堂）", matchPatterns: ["怀德堂"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "逸夫基础医学楼", matchPatterns: ["基础医学", "基础医学大楼", "逸夫基础医学楼"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "法医楼", matchPatterns: ["法医大楼", "法医教学楼", "法医楼", "正德楼"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "口腔科研楼", matchPatterns: ["口腔楼", "口腔科教楼", "口腔科研楼", "涵德楼"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "药物化学楼", matchPatterns: ["药学大楼", "药物化学楼", "药学科教大楼"]),
        BuildingGeoReference(campusName: "四川大学华西校区", canonicalBuildingName: "体育馆", matchPatterns: ["华西体育馆"]),
    ]

    // MARK: - 正则替换助手

    /// NSRegularExpression 模板替换（组 1 起传入 template 闭包）
    static func regexReplace(_ text: String, pattern: String, template: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        var result: [String] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: nsRange) {
            if let r = Range(match.range, in: text) {
                result.append(String(text[cursor..<r.lowerBound]))
                let groups = (1..<match.numberOfRanges).compactMap { i -> String? in
                    guard let gr = Range(match.range(at: i), in: text) else { return nil }
                    return String(text[gr])
                }
                result.append(template([""] + groups))
                cursor = r.upperBound
            }
        }
        result.append(String(text[cursor...]))
        return result.joined()
    }

    // MARK: - 解析

    /// 地点 → 展示标题（校区全称 · 建筑全称 · 房间号）
    static func resolve(_ rawLocation: String, campusName: String? = nil) -> ResolvedLocation {
        let location = rawLocation.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 1. 优先从 campusName 或 location 识别目标校区
        var explicitCampus: CampusGeoReference?
        let trimmedCampus = campusName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmedCampus.isEmpty {
            explicitCampus = campusLocations.first { ref in
                ref.keywords.contains { trimmedCampus.contains($0) }
            }
        }
        if explicitCampus == nil, !location.isEmpty {
            explicitCampus = campusLocations.first { ref in
                ref.keywords.contains { location.contains($0) }
            }
        }

        // 2. 最长 pattern 优先匹配高精度建筑
        var matchedBuilding: BuildingGeoReference?
        if !location.isEmpty {
            var bestLength = 0
            for building in buildingLocations {
                if let campus = explicitCampus, building.campusName != campus.fullName {
                    continue
                }
                let length = building.longestMatchLength(location)
                if length > bestLength {
                    bestLength = length
                    matchedBuilding = building
                }
            }
        }

        if let matched = matchedBuilding {
            let fullBuildingName = matched.campusName + matched.canonicalBuildingName
            let room = extractRoomName(location, building: matched)
            let noteSuffix = matched.redirectNote.map { " (\($0))" } ?? ""
            let title = room.isEmpty
                ? fullBuildingName + noteSuffix
                : fullBuildingName + " · " + room + noteSuffix
            return ResolvedLocation(title: title)
        }

        // 3. 回退校区级推断
        var campus = explicitCampus
        if campus == nil, !location.isEmpty {
            campus = campusLocations.first { ref in
                ref.buildingKeywords.contains { location.contains($0) }
            }
        }

        if location.isEmpty {
            return ResolvedLocation(title: campus?.fullName ?? "")
        }
        guard let campus else {
            return ResolvedLocation(title: location)
        }
        let title = location.contains(campus.fullName)
            ? location
            : campus.fullName + " · " + location
        return ResolvedLocation(title: title)
    }

    /// 从原始地点中剥出房间号（保留 A101/C407 等字母+数字形态）
    static func extractRoomName(_ rawLocation: String, building: BuildingGeoReference) -> String {
        var text = rawLocation

        // 1. 移除校区全称和校区关键字
        for campus in campusLocations {
            text = text.replacingOccurrences(of: campus.fullName, with: " ")
            for k in campus.keywords {
                text = text.replacingOccurrences(of: k, with: " ")
            }
        }

        // 2. 移除教学楼名称（"综C407" 只剥中文前缀保留 C407），最长名优先
        var stripNames = Set<String>([building.canonicalBuildingName] + building.matchPatterns)
        stripNames.formUnion([
            "第一教学楼", "第二教学楼", "第三教学楼", "第四教学楼", "第五教学楼",
            "第六教学楼", "第七教学楼", "第八教学楼", "第九教学楼", "第十教学楼",
            "综合教学楼", "综合楼", "第二基础实验大楼", "第二基础实验楼", "第二基础教学楼",
            "第二基础", "二基楼", "文科楼一区", "文科楼二区", "文科楼三区", "文科楼四区",
            "文科楼", "基础教学大楼", "基础教学楼", "东三教学楼", "东一教学楼", "东二教学楼",
            "教学楼", "实验大楼", "实验楼", "启明楼", "易明楼", "水明楼", "文襄楼", "启秀楼",
            "汇文楼", "泓文楼", "逸夫教学楼", "逸夫科技楼", "逸夫楼", "启德堂", "敬德堂",
            "仁德堂", "志德堂", "嘉德堂", "懿德堂", "树德堂", "合德堂", "育德堂", "万德堂",
            "怀德堂", "一教", "二教", "三教", "四教", "五教", "六教", "七教", "八教", "九教",
            "十教", "基教", "综楼", "综",
        ])
        let orderedNames = stripNames.sorted { $0.count > $1.count }

        for name in orderedNames {
            // 名字以单个字母结尾（如 综C/一教A）且后接数字 → 只剥中文前缀
            if let m = RegexHelper.firstMatch(#"^(.+?)([A-Za-z])$"#, in: name) {
                let prefix = m[1]
                let letter = m[2]
                let pattern = NSRegularExpression.escapedPattern(for: prefix + letter) + "(\\d+)"
                text = regexReplace(text, pattern: pattern) { groups in
                    " " + letter + groups[1]
                }
            }
            text = text.replacingOccurrences(of: name, with: " ")
        }

        // 移除独立的 座/栋
        text = text.replacingOccurrences(of: "[座栋]", with: " ", options: .regularExpression)

        // 3. 清理空白与首尾标点
        text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[·\s\-_:：/、]+|[·\s\-_:：/、]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 4. 只剩单个座号字母 → 房间号视为空
        if text.count == 1, text.first?.isLetter == true {
            return ""
        }

        // 5. "B B503" → "B503"
        if let m = RegexHelper.firstMatch(#"^([A-Za-z])\s+([A-Za-z]\d+.*)$"#, in: text) {
            text = m[2]
        }

        // 6. "A 101" → "A101"
        if let m = RegexHelper.firstMatch(#"^([A-Za-z])\s+(\d+.*)$"#, in: text) {
            text = m[1] + m[2]
        }

        return text
    }
}
