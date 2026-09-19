import SwiftUI
import Combine

/// 统一身份认证登录页（对应 lib/pages/auth/scu_login_page.dart）：
/// 验证码行内展示 + 点击刷新 + OCR 自动识别预填、记住密码/自动登录。
struct ScuLoginPage: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var authBus: AuthBus
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = ScuLoginViewModel()

    var body: some View {
        Form {
            Section {
                TextField("学号 / 工号", text: $model.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("统一身份认证密码", text: $model.password)
                    .textContentType(.password)
            } header: {
                Text("账号")
            }

            Section {
                HStack(spacing: 12) {
                    captchaImage
                        .frame(width: 110, height: 42)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        Task { await model.refreshCaptcha(environment: environment) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("刷新验证码")
                    Spacer()
                }
                .padding(.vertical, 2)
                HStack {
                    TextField("验证码（不区分大小写）", text: $model.captchaText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        Task { await model.ocrFill(environment: environment) }
                    } label: {
                        Label("自动识别", systemImage: "text.viewfinder")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.captchaImage == nil || model.isRecognizing)
                }
            } header: {
                Text("验证码")
            } footer: {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("记住密码", isOn: $model.rememberPassword)
                Toggle("自动登录", isOn: $model.autoLoginEnabled)
                    .disabled(!model.rememberPassword)
            }

            Section {
                Button {
                    Task {
                        await model.login(environment: environment)
                        if case .success = model.result {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("登录")
                        }
                        Spacer()
                    }
                }
                .disabled(!model.canSubmit || model.isLoading)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("统一身份认证")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task {
            await model.bootstrap(environment: environment)
        }
    }

    @ViewBuilder
    private var captchaImage: some View {
        if let image = model.captchaImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .onTapGesture {
                    Task { await model.refreshCaptcha(environment: environment) }
                }
        } else {
            if model.isLoadingCaptcha {
                ProgressView().controlSize(.small)
            } else {
                Text("点击刷新")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .onTapGesture {
                        Task { await model.refreshCaptcha(environment: environment) }
                    }
            }
        }
    }
}

/// 登录页视图模型
@MainActor
final class ScuLoginViewModel: ObservableObject {

    enum LoginResult: Equatable {
        case idle
        case success
        case failure(String)
    }

    @Published var username = ""
    @Published var password = ""
    @Published var captchaText = ""
    @Published var rememberPassword = false
    @Published var autoLoginEnabled = false
    @Published var captchaImage: UIImage?
    @Published var isLoading = false
    @Published var isLoadingCaptcha = false
    @Published var isRecognizing = false
    @Published var errorMessage: String?
    @Published var result: LoginResult = .idle

    private var captchaCode = ""

    var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !captchaText.isEmpty && !captchaCode.isEmpty
    }

    func bootstrap(environment: AppEnvironment) async {
        // 恢复记住的凭据
        if let credentials = await environment.scuAuth.getSavedCredentials() {
            username = credentials.username
            password = credentials.password
            rememberPassword = true
            autoLoginEnabled = true
        }
        await refreshCaptcha(environment: environment)
    }

    func refreshCaptcha(environment: AppEnvironment) async {
        isLoadingCaptcha = true
        defer { isLoadingCaptcha = false }
        do {
            let captcha = try await environment.scuAuth.fetchCaptcha()
            captchaCode = captcha.code
            var base64 = captcha.captchaBase64
            if let comma = base64.firstIndex(of: ",") {
                base64 = String(base64[base64.index(after: comma)...])
            }
            if let data = Data(base64Encoded: base64) {
                captchaImage = UIImage(data: data)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// OCR 自动识别预填（识别失败静默——用户手输兜底）
    func ocrFill(environment: AppEnvironment) async {
        guard let image = captchaImage, let data = image.pngData() else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        guard let model = ScuOcrLite.loadBundledModel(),
              let recognized = try? ScuOcrLite.recognize(imageData: data, model: model),
              !recognized.isEmpty else {
            return
        }
        captchaText = recognized.lowercased()
    }

    func login(environment: AppEnvironment) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await environment.scuAuth.login(
                username: username,
                password: password,
                captchaCode: captchaCode,
                captchaText: captchaText
            )
            if rememberPassword {
                await environment.scuAuth.saveCredentials(username: username, password: password)
                await environment.scuAuth.setAutoLoginEnabled(autoLoginEnabled)
            } else {
                await environment.scuAuth.clearCredentials()
            }
            environment.authCoordinator.warmUpAllInBackground()
            Task { await environment.fetchUserInfo() }
            result = .success
        } catch {
            errorMessage = error.localizedDescription
            result = .failure(error.localizedDescription)
            // 验证码已消耗，刷新
            captchaText = ""
            await refreshCaptcha(environment: environment)
        }
    }
}
