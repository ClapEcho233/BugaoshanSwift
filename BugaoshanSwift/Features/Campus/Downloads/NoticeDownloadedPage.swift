import SwiftUI
import UniformTypeIdentifiers

// MARK: - 下载中心（notice_downloaded_page.dart）

/// 已下载附件管理：三源目录 Tab（教务处/党委学工部/团委）、排序/搜索/扩展名筛选、
/// 多选删除、分享。文件元数据（大小/时间）在列目录时一次算好，列表不做同步 IO。
struct NoticeDownloadedPage: View {
    var initialTab = 0

    @State private var tabIndex = 0
    @State private var filesByDir: [String: [FileInfo]] = [:]
    @State private var isLoading = true
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var sortMode: SortMode = .time
    @State private var searchText = ""
    @State private var filterExt = ""
    @State private var showDeleteConfirm = false
    @State private var deleteTargetPaths: [String] = []
    @State private var shareURL: URL?

    private let tabs: [(dir: String, label: String)] = [
        (DownloadDirs.notice, "教务处通知"),
        (DownloadDirs.party, "党委学工部"),
        (DownloadDirs.tuanwei, "团委"),
    ]

    enum SortMode: String, CaseIterable, Identifiable {
        case time = "时间"
        case name = "名称"
        case size = "大小"
        var id: String { rawValue }
    }

    struct FileInfo: Identifiable, Equatable {
        var id: String { url.path }
        var url: URL
        var size: Int
        var modified: Date
    }

    private var currentDir: String { tabs[tabIndex].dir }

    private var currentInfos: [FileInfo] {
        (filesByDir[currentDir] ?? []).filter { matchesFilter($0) }
    }

    private var totalMatches: Int {
        tabs.reduce(0) { sum, tab in
            sum + (filesByDir[tab.dir] ?? []).filter { matchesFilter($0) }.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("来源", selection: $tabIndex) {
                ForEach(tabs.indices, id: \.self) { index in
                    Text(tabs[index].label).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            toolbarRow

            if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentInfos.isEmpty {
                ContentUnavailableView("暂无附件", systemImage: "tray")
                    .padding(.top, 40)
            } else {
                fileList
            }
        }
        .navigationTitle("下载中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard isLoading else { return }
            await loadFiles()
        }
        .refreshable {
            await loadFiles()
        }
        .confirmationDialog(
            deleteTargetPaths.count > 1 ? "删除 \(deleteTargetPaths.count) 个文件？" : "删除该文件？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deletePaths(deleteTargetPaths)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不可恢复")
        }
        .sheet(item: Binding(
            get: { shareURL.map { ShareItem(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { item in
            ActivityShareSheet(items: [item.url as NSURL])
        }
    }

    private struct ShareItem: Identifiable {
        var id: String { url.absoluteString }
        var url: URL
    }

    private var toolbarRow: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("排序", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("类型", selection: $filterExt) {
                    Text("全部").tag("")
                    ForEach(Array(availableExtensions).sorted(), id: \.self) { ext in
                        Text(".\(ext)").tag(ext)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文件名", text: $searchText)
                    .autocorrectionDisabled()
            }
            .padding(7)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            if selecting {
                Button(currentInfos.count == selected.count ? "取消全选" : "全选") {
                    if currentInfos.count == selected.count {
                        selected.subtract(currentInfos.map(\.url.path))
                    } else {
                        selected.formUnion(currentInfos.map(\.url.path))
                    }
                }
                .font(.subheadline)
                Button("删除") {
                    let paths = currentInfos.filter { selected.contains($0.url.path) }.map(\.url.path)
                    guard !paths.isEmpty else { return }
                    deleteTargetPaths = paths
                    showDeleteConfirm = true
                }
                .font(.subheadline)
                .foregroundStyle(.red)
                .disabled(selected.isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var fileList: some View {
        List {
            if totalMatches != currentInfos.count {
                Text("当前来源 \(currentInfos.count) 个，全部来源共 \(totalMatches) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(currentInfos) { info in
                row(info)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
    }

    private func row(_ info: FileInfo) -> some View {
        HStack(spacing: 10) {
            if selecting {
                Image(systemName: selected.contains(info.url.path) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(info.url.path) ? Color.accentColor : Color(.systemGray3))
            }
            Image(systemName: fileIcon(info.url.pathExtension))
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.url.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(2)
                Text("\(info.url.pathExtension.uppercased()) · \(formattedSize(info.size)) · \(formattedDate(info.modified))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !selecting {
                Menu {
                    Button {
                        shareURL = info.url
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        deleteTargetPaths = [info.url.path]
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                toggleSelect(info)
            } else {
                // 长按进入多选的等价手势：双击进入
                shareURL = info.url
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTargetPaths = [info.url.path]
                showDeleteConfirm = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                selecting = true
                selected = [info.url.path]
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }
        }
    }

    // MARK: - 数据

    private func matchesFilter(_ info: FileInfo) -> Bool {
        if !filterExt.isEmpty && info.url.pathExtension.lowercased() != filterExt {
            return false
        }
        if !searchText.isEmpty
            && !info.url.lastPathComponent.lowercased().contains(searchText.lowercased()) {
            return false
        }
        return true
    }

    private var availableExtensions: Set<String> {
        var exts = Set<String>()
        for (_, infos) in filesByDir {
            for info in infos where !info.url.pathExtension.isEmpty {
                exts.insert(info.url.pathExtension.lowercased())
            }
        }
        return exts
    }

    private func loadFiles() async {
        let value = await Task.detached(priority: .userInitiated) { () -> [String: [FileInfo]] in
            var result: [String: [FileInfo]] = [:]
            for tab in [DownloadDirs.notice, DownloadDirs.party, DownloadDirs.tuanwei] {
                let dir = DownloadDirs.directory(tab)
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
                )) ?? []
                let infos = entries
                    .filter { !$0.hasDirectoryPath }
                    .compactMap { entry -> FileInfo? in
                        guard let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                            return nil
                        }
                        return FileInfo(
                            url: entry,
                            size: values.fileSize ?? 0,
                            modified: values.contentModificationDate ?? .distantPast
                        )
                    }
                result[tab] = sorted(infos)
            }
            return result
        }.value
        filesByDir = value
        isLoading = false
    }

    private func sorted(_ infos: [FileInfo]) -> [FileInfo] {
        switch sortMode {
        case .time:
            return infos.sorted { $0.modified > $1.modified }
        case .name:
            return infos.sorted { $0.url.lastPathComponent.lowercased() < $1.url.lastPathComponent.lowercased() }
        case .size:
            return infos.sorted { $0.size > $1.size }
        }
    }

    private func toggleSelect(_ info: FileInfo) {
        if selected.contains(info.url.path) {
            selected.remove(info.url.path)
            if selected.isEmpty {
                selecting = false
            }
        } else {
            selected.insert(info.url.path)
        }
    }

    private func deletePaths(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
            DownloadManager.removePathMapping(dirName: currentDir, path: path)
        }
        selected.subtract(paths)
        if selected.isEmpty {
            selecting = false
        }
        Task {
            await loadFiles()
        }
    }

    // MARK: - 展示

    private func fileIcon(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "doc", "docx", "wps": return "doc.fill"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "zip", "rar", "7z", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "bmp": return "photo"
        default: return "doc"
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// UIActivityViewController 包装（分享本地文件）
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
