import SwiftUI
import WebKit

/// 通用通知 WebView（对应 widgets/webview/webview_notice_page.dart）：
/// 站点 chrome 美化 JS 注入（bundle 资产）、进度条、前进/后退/刷新。
/// 附件下载与验证码对话框在后续迭代接入（DownloadManager 阶段）。
struct WebViewNoticePage: View {
    let url: URL
    var beautifyJSFileName: String?
    var title: String
    var userAgent: String? = Constants.userAgent
    /// 附件下载目录（nil = 不拦截附件）
    var attachmentDir: String? = nil
    var downloadReferer: String? = nil

    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var captchaURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            WebViewContainer(
                url: url,
                beautifyJS: beautifyJS,
                userAgent: userAgent,
                interceptAttachments: attachmentDir != nil,
                onDownloadRequested: { downloadURL in
                    Task { await download(downloadURL) }
                },
                onNavigationStateChange: { back, forward in
                    canGoBack = back
                    canGoForward = forward
                }
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $captchaURL) { captchaTarget in
            CaptchaDownloadSheet(
                url: captchaTarget,
                attachmentDir: attachmentDir ?? DownloadDirs.notice,
                referer: downloadReferer ?? "https://\(captchaTarget.host ?? "")"
            ) { filePath in
                downloadMessage = "已下载：\((filePath as NSString).lastPathComponent)"
            }
        }
        .alert("下载", isPresented: Binding(
            get: { downloadMessage != nil }, set: { if !$0 { downloadMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    NotificationCenter.default.post(name: .webViewGoBack, object: nil)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                Button {
                    NotificationCenter.default.post(name: .webViewGoForward, object: nil)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
            }
        }
    }

    private func download(_ target: URL) async {
        guard let attachmentDir else { return }
        isDownloading = true
        defer { isDownloading = false }
        let fileName = sanitizeDownloadFileName(target.lastPathComponent)
        do {
            let path = try await DownloadManager.shared.download(
                url: target.absoluteString,
                dirName: attachmentDir,
                fileName: fileName,
                referer: downloadReferer ?? "https://\(target.host ?? "")"
            )
            downloadMessage = "已下载：\((path as NSString).lastPathComponent)"
        } catch let error as DownloadError {
            if case .captchaRequired = error {
                // 服务器返回验证码页 → 弹 WebView 让用户在原站完成验证，
                // 之后的附件导航会被拦截并以带 Cookie 的请求落盘
                captchaURL = target
            } else {
                downloadMessage = error.localizedDescription
            }
        } catch {
            downloadMessage = (error as? LocalizedError)?.errorDescription ?? "下载失败"
        }
    }

    private var beautifyJS: String? {
        guard let beautifyJSFileName else { return nil }
        guard let url = Bundle.main.url(forResource: beautifyJSFileName, withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

extension Notification.Name {
    static let webViewGoBack = Notification.Name("webViewGoBack")
    static let webViewGoForward = Notification.Name("webViewGoForward")
}

/// WKWebView 容器（UIViewRepresentable）：UA 伪装 + document-end 美化 JS 注入 + 进度条
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    var beautifyJS: String?
    var userAgent: String?
    var interceptAttachments: Bool = false
    var onDownloadRequested: ((URL) -> Void)? = nil
    var onNavigationStateChange: (Bool, Bool) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        let webView = WKWebView(frame: .zero, configuration: config)
        if let userAgent {
            webView.customUserAgent = userAgent
        }
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.parent = self

        // 进度条观察
        context.coordinator.progressObserver = webView.observe(\.estimatedProgress, options: .new) { view, _ in
            DispatchQueue.main.async {
                view.setValue(view.estimatedProgress, forKey: "progressValue")
            }
        }

        // 导航按钮通知
        context.coordinator.notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: .webViewGoBack, object: nil, queue: .main
            ) { [weak webView] _ in
                webView?.goBack()
            },
            NotificationCenter.default.addObserver(
                forName: .webViewGoForward, object: nil, queue: .main
            ) { [weak webView] _ in
                webView?.goForward()
            },
        ]

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var parent: WebViewContainer?
        var progressObserver: NSKeyValueObservation?
        var notificationObservers: [NSObjectProtocol] = []

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // 附件拦截：download 意图或附件扩展名链接 → 走下载而非网页加载
            if parent?.interceptAttachments == true,
               let target = navigationAction.request.url,
               navigationAction.navigationType != .backForward,
               target.isAttachmentLike {
                parent?.onDownloadRequested?(target)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func cleanup() {
            progressObserver?.invalidate()
            notificationObservers.forEach(NotificationCenter.default.removeObserver)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let js = parent?.beautifyJS {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            parent?.onNavigationStateChange(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent?.onNavigationStateChange(webView.canGoBack, webView.canGoForward)
        }
    }
}

// MARK: - 通知中心（hub）

/// 通知 hub：三源入口（教务处 / 党委学工部 / 团委）
struct NoticePage: View {
    private let sources: [(label: String, icon: String, tint: Color, url: String, js: String?, dir: String, referer: String)] = [
        ("教务处通知", "graduationcap", .blue, "https://jwc.scu.edu.cn/tzgg.htm", "jwc_notice_beautify", DownloadDirs.notice, "https://jwc.scu.edu.cn"),
        ("党委学工部", "flag", .red, "https://xgb.scu.edu.cn/index/tzgg.htm", "party_notice_beautify", DownloadDirs.party, "https://xgb.scu.edu.cn"),
        ("团委通知", "hands.and.sparkles", .orange, "https://tuanwei.scu.edu.cn/index/gg.htm", "tuanwei_notice_beautify", DownloadDirs.tuanwei, "https://tuanwei.scu.edu.cn"),
    ]

    var body: some View {
        List {
            ForEach(sources, id: \.label) { source in
                NavigationLink {
                    WebViewNoticePage(
                        url: URL(string: source.url)!,
                        beautifyJSFileName: source.js,
                        title: source.label,
                        attachmentDir: source.dir,
                        downloadReferer: source.referer
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: source.icon)
                            .font(.title3)
                            .foregroundStyle(source.tint)
                            .frame(width: 36, height: 36)
                            .background(source.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        Text(source.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}


extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - 验证码下载弹窗（captcha_webview_dialog.dart）

/// 直接加载下载 URL：用户在原站页面完成验证，服务端转回真实文件时
/// 附件导航被拦截 → 取 WKWebView Cookie 后下载落盘 → 关闭弹窗。
struct CaptchaDownloadSheet: View {
    let url: URL
    let attachmentDir: String
    let referer: String
    let onDownloadComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    ContentUnavailableView("页面加载失败", systemImage: "exclamationmark.triangle")
                } else {
                    WebViewContainer(
                        url: url,
                        userAgent: Constants.userAgent,
                        interceptAttachments: true,
                        onDownloadRequested: { target in
                            Task { await downloadAfterCaptcha(target) }
                        },
                        onNavigationStateChange: { _, _ in }
                    )
                }
            }
            .navigationTitle("完成验证后下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    /// 取 WKWebView Cookie 拼请求头下载
    private func downloadAfterCaptcha(_ target: URL) async {
        let cookieHeader = await Self.webViewCookieHeader(for: target)
        do {
            let path = try await DownloadManager.shared.download(
                url: target.absoluteString,
                dirName: attachmentDir,
                fileName: sanitizeDownloadFileName(target.lastPathComponent),
                referer: referer,
                extraHeaders: cookieHeader.isEmpty ? [:] : ["Cookie": cookieHeader]
            )
            onDownloadComplete(path)
            dismiss()
        } catch {
            dismiss()
        }
    }

    /// WKWebsiteDataStore 中匹配 host 的 Cookie → "k=v; k2=v2"
    static func webViewCookieHeader(for url: URL) async -> String {
        guard let host = url.host else { return "" }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let domain = ".\(host)" as NSString
        let matched = cookies.filter { cookie in
            cookie.domain == host || domain.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(".\(host)")
        }
        return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
