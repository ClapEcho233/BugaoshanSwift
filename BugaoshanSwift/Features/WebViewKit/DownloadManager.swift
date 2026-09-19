import Foundation
import Combine

// MARK: - 目录与文件工具（file_utils.dart）

enum DownloadDirs {
    static let notice = "notice_attachments"     // 教务处
    static let party = "party_attachments"       // 党委学工部
    static let tuanwei = "tuanwei_attachments"   // 团委

    /// iOS：Documents/Bugaoshan/<dir>（Info.plist UIFileSharingEnabled 后可在「文件」App 查看）
    static func directory(_ dirName: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Bugaoshan/\(dirName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// 文件名净化：取 basename、去非法字符
func sanitizeDownloadFileName(_ rawName: String) -> String {
    let normalized = rawName.replacingOccurrences(of: "\\", with: "/")
    var fileName = (normalized as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    if fileName.isEmpty || fileName == "." || fileName == ".." {
        return "download"
    }
    fileName = fileName.replacingOccurrences(
        of: #"[<>:"/\\|?*\x00-\x1F]"#,
        with: "_",
        options: .regularExpression
    )
    return fileName.isEmpty ? "download" : fileName
}

/// 附件扩展名（导航拦截判定）
let attachmentExtensions: Set<String> = [
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "wps",
    "zip", "rar", "7z", "gz",
    "jpg", "jpeg", "png", "gif", "bmp",
]

extension URL {
    var isAttachmentLike: Bool {
        let ext = pathExtension.lowercased()
        return !ext.isEmpty && attachmentExtensions.contains(ext)
    }
}

/// url → 保存路径 索引（download_index.json，随目录走）
struct DownloadPathIndex {
    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("download_index.json") }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: indexURL),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return map
    }

    private func save(_ map: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: map) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    mutating func record(url: String, path: String) {
        var map = load()
        map[url] = path
        save(map)
    }

    func resolve(url: String, legacyFileName: String) -> String? {
        if let path = load()[url], FileManager.default.fileExists(atPath: path) {
            return path
        }
        return legacyCandidate(legacyFileName)
    }

    /// 旧方案兜底：精确名 → base (n).ext 逐个探测
    func legacyCandidate(_ rawName: String) -> String? {
        let safeName = sanitizeDownloadFileName(rawName)
        let basePath = directory.appendingPathComponent(safeName).path
        if FileManager.default.fileExists(atPath: basePath) {
            return basePath
        }
        let baseName = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        for i in 1...99 {
            let variant = directory.appendingPathComponent(ext.isEmpty ? "\(baseName) (\(i))" : "\(baseName) (\(i)).\(ext)").path
            if FileManager.default.fileExists(atPath: variant) {
                return variant
            }
        }
        return nil
    }

    mutating func removePath(_ path: String) {
        var map = load()
        map = map.filter { $0.value != path }
        save(map)
    }
}

// MARK: - 下载管理器（download_manager.dart + downloadFile）

enum DownloadStatus: Equatable {
    case pending
    case downloading
    case done
    case error
}

final class DownloadTask: Identifiable, ObservableObject {
    let id: String
    let url: String
    let fileName: String
    let dirName: String
    @Published var status: DownloadStatus = .pending
    var downloadedPath: String?
    var errorMessage: String?
    var startedAt = Date()
    var networkTask: Task<String, Error>?

    init(id: String, url: String, fileName: String, dirName: String) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.dirName = dirName
    }
}

enum DownloadError: LocalizedError {
    case captchaRequired
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .captchaRequired:
            return "下载需要验证码，请在原页面重试"
        case .http(let code):
            return "下载失败: HTTP \(code)"
        }
    }
}

/// 会话级下载管理器（页面导航不中断）
final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    @Published private(set) var tasks: [String: DownloadTask] = [:]

    private func taskKey(_ url: String, _ dirName: String) -> String {
        "\(dirName)\u{0}\(url)"
    }

    func taskFor(url: String, dirName: String) -> DownloadTask? {
        tasks[taskKey(url, dirName)]
    }

    func enqueue(url: String, dirName: String, fileName: String) -> DownloadTask {
        let key = taskKey(url, dirName)
        if let existing = tasks[key] {
            return existing
        }
        let task = DownloadTask(id: key, url: url, fileName: fileName, dirName: dirName)
        tasks[key] = task
        return task
    }

    func cancel(url: String, dirName: String) {
        let key = taskKey(url, dirName)
        tasks[key]?.networkTask?.cancel()
        tasks.removeValue(forKey: key)
    }

    /// 下载并落盘：Content-Disposition 文件名优先（RFC5987 filename* 优先 filename），
    /// 重名追加 (n)，写 url→path 索引。
    @discardableResult
    func download(
        url: String, dirName: String, fileName: String,
        referer: String = "https://xgb.scu.edu.cn"
    ) async throws -> String {
        let task = enqueue(url: url, dirName: dirName, fileName: fileName)
        if task.status == .downloading {
            // 复用在途任务
            if let path = try? await task.networkTask?.value {
                return path
            }
        }
        task.status = .downloading
        let networkTask = Task<String, Error> {
            try await Self.downloadFile(
                url: url, dirName: dirName, fileName: fileName, referer: referer
            )
        }
        task.networkTask = networkTask
        do {
            let path = try await networkTask.value
            task.status = .done
            task.downloadedPath = path
            task.errorMessage = nil
            return path
        } catch {
            if error is CancellationError {
                tasks.removeValue(forKey: task.id)
            } else {
                task.status = .error
                task.errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// 纯函数下载（file_utils.dart downloadFile）
    static func downloadFile(
        url: String, dirName: String, fileName: String,
        referer: String
    ) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw DownloadError.http(-1)
        }
        var request = URLRequest(url: requestURL)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(Constants.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.http(-1)
        }
        guard http.statusCode == 200 else {
            throw DownloadError.http(http.statusCode)
        }
        // 200 但返回 HTML → 验证码/错误页
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html") {
            throw DownloadError.captchaRequired
        }

        var actualFileName = sanitizeDownloadFileName(fileName)
        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let name = Self.fileNameFromContentDisposition(cd) {
                actualFileName = sanitizeDownloadFileName(name)
            }
        }

        let saveDir = DownloadDirs.directory(dirName)
        var fileURL = saveDir.appendingPathComponent(actualFileName)
        var counter = 1
        let baseName = (actualFileName as NSString).deletingPathExtension
        let ext = (actualFileName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = saveDir.appendingPathComponent(ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)")
            counter += 1
        }
        try data.write(to: fileURL, options: .atomic)
        var index = DownloadPathIndex(directory: saveDir)
        index.record(url: url, path: fileURL.path)
        return fileURL.path
    }

    /// Content-Disposition：filename*=UTF-8''…（RFC5987）优先，回退 filename=
    static func fileNameFromContentDisposition(_ cd: String) -> String? {
        if let m = RegexHelper.firstMatch(
            #"filename\*\s*=\s*UTF-8'[^']*'([^;]+)"#, in: cd
        ) {
            let decoded = m[1].removingPercentEncoding ?? m[1]
            if !decoded.isEmpty {
                return decoded
            }
        }
        if let m = RegexHelper.firstMatch(
            #"filename\s*=\s*["']?([^"';]+)["']?"#, in: cd
        ) {
            return m[1]
        }
        return nil
    }

    /// 查已下载文件（url 索引优先，旧名兜底）
    static func downloadedFile(dirName: String, fileName: String, url: String?) -> String? {
        let dir = DownloadDirs.directory(dirName)
        var index = DownloadPathIndex(directory: dir)
        if let url, let path = index.resolve(url: url, legacyFileName: fileName) {
            return path
        }
        if url == nil {
            return index.legacyCandidate(fileName)
        }
        _ = index
        return nil
    }

    static func removePathMapping(dirName: String, path: String) {
        let dir = DownloadDirs.directory(dirName)
        var index = DownloadPathIndex(directory: dir)
        index.removePath(path)
    }
}
