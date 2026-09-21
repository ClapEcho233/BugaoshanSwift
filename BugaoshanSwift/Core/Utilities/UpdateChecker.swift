import Foundation

/// GitHub 版本检查（update_checker.dart 全量移植）。
/// 仓库：ClapEcho233/BugaoshanSwift（本 App 自己的发布通道，
/// 不查询原项目 The-Brotherhood-of-SCU/Bugaoshan 的 Releases）
enum UpdateChecker {

    static let githubRepo = "ClapEcho233/BugaoshanSwift"

    static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
    }

    static var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(githubRepo)/releases")!
    }

    static var headers: [String: String] {
        ["Accept": "application/vnd.github+json"]
    }

    /// 最新稳定版 tag（去 v 前缀）
    static func fetchLatestVersion() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: latestReleaseURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SCUError.service("GitHub API error: \(code)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw SCUError.service("Could not parse release tag from response")
        }
        return stripVPrefix(tagName)
    }

    /// 最新预发布 tag（无则 nil）
    static func fetchLatestPrerelease() async throws -> String? {
        let (data, response) = try await URLSession.shared.data(from: releasesURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SCUError.service("GitHub API error: \(code)")
        }
        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        for release in releases where release["prerelease"] as? Bool == true {
            if let tag = release["tag_name"] as? String {
                return stripVPrefix(tag)
            }
        }
        return nil
    }

    /// latest 比 current 新？（v 前缀与 +build 后缀容忍）
    static func hasUpdate(currentVersion: String, latestVersion: String) -> Bool {
        guard let current = parseVersion(currentVersion),
              let latest = parseVersion(latestVersion) else {
            return false
        }
        for i in 0..<3 {
            if latest[i] > current[i] { return true }
            if latest[i] < current[i] { return false }
        }
        return false
    }

    /// 预发布 tag 是否比当前构建新（提取 - 前基础版本号比较；
    /// 与当前 gitTag 相同 / 无法解析 / 不高于当前 → false，保守不提示）
    static func isNewerPrerelease(_ prereleaseTag: String?, currentVersion: String, gitTag: String) -> Bool {
        guard let prereleaseTag, prereleaseTag != gitTag else { return false }
        guard let baseVersion = prereleaseBaseVersion(prereleaseTag) else { return false }
        return hasUpdate(currentVersion: currentVersion, latestVersion: baseVersion)
    }

    static func prereleaseBaseVersion(_ tag: String) -> String? {
        let clean = stripVPrefix(tag)
        let base = clean.split(separator: "-").first.map(String.init) ?? ""
        return parseVersion(base) != nil ? base : nil
    }

    static func stripVPrefix(_ tag: String) -> String {
        tag.lowercased().hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// '1.2.3+4' → [1,2,3]；解析失败 nil
    static func parseVersion(_ version: String) -> [Int]? {
        let stripped = stripVPrefix(version)
        let base = stripped.split(separator: "+").first.map(String.init) ?? stripped
        let parts = base.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3, parts.allSatisfy({ $0 != nil }) else {
            // 两段式（1.2）也接受，补 0
            let compact = parts.compactMap { $0 }
            guard parts.count >= 2, compact.count == parts.count else { return nil }
            var result = compact
            while result.count < 3 { result.append(0) }
            return result
        }
        return parts.compactMap { $0 }
    }
}
