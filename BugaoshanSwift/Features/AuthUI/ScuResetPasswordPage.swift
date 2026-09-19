import SwiftUI

/// 忘记密码三步流（scu_reset_password_page.dart）：
/// ① 学号 + 图形验证码校验身份 → ② 选择短信/邮箱收验证码并校验 → ③ 设置新密码。
struct ScuResetPasswordPage: View {
    @Environment(\.dismiss) private var dismiss

    private let service = ForgotPasswordService()

    // 步骤与共享状态
    @State private var step = 1
    @State private var isWorking = false
    @State private var errorMessage: String?

    // ① 身份
    @State private var username = ""
    @State private var captchaText = ""
    @State private var captchaBase64 = ""
    @State private var captchaCode = ""
    @State private var verifyResult: ForgotPasswordService.VerifyUserResult?

    // ② 验证码
    @State private var channel = "phone"
    @State private var smsCode = ""
    @State private var resetToken = ""
    @State private var codeSent = false

    // ③ 新密码
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var doneMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Form {
                switch step {
                case 1: stepIdentity
                case 2: stepVerifyCode
                default: stepNewPassword
                }
            }
        }
        .navigationTitle("忘记密码")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if captchaBase64.isEmpty {
                await reloadCaptcha()
            }
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil || doneMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                    if doneMessage != nil {
                        doneMessage = nil
                        dismiss()
                    }
                }
            }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(doneMessage ?? errorMessage ?? "")
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            stepDot(1, label: "验证身份")
            stepLine(active: step > 1)
            stepDot(2, label: "获取验证码")
            stepLine(active: step > 2)
            stepDot(3, label: "重置密码")
        }
        .padding(.vertical, 14)
    }

    private func stepDot(_ number: Int, label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(step >= number ? Color.accentColor : Color(.systemGray4))
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(step >= number ? .primary : .secondary)
        }
        .frame(width: 76)
    }

    private func stepLine(active: Bool) -> some View {
        Rectangle()
            .fill(active ? Color.accentColor : Color(.systemGray4))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -8)
    }

    // MARK: - 第 ① 步

    @ViewBuilder
    private var stepIdentity: some View {
        Section("账号信息") {
            TextField("学号 / 工号", text: $username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.asciiCapable)
            HStack(spacing: 10) {
                TextField("图形验证码", text: $captchaText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                captchaImage
            }
        }
        Section {
            Button {
                Task { await verifyUser() }
            } label: {
                rowButton("下一步", loading: isWorking)
            }
            .disabled(username.isEmpty || captchaText.isEmpty || isWorking)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var captchaImage: some View {
        if let data = Data(base64Encoded: captchaBase64), let image = UIImage(data: data) {
            Button {
                Task { await reloadCaptcha() }
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 36)
                    .cornerRadius(4)
            }
        } else {
            ProgressView()
                .frame(width: 100, height: 36)
        }
    }

    private func reloadCaptcha() async {
        do {
            let result = try await service.fetchCaptcha()
            captchaBase64 = result.captchaBase64
            captchaCode = result.code
            captchaText = ""
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "验证码加载失败"
        }
    }

    private func verifyUser() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await service.verifyUser(
                username: username, captchaText: captchaText, captchaCode: captchaCode
            )
            guard !result.sToken.isEmpty else {
                errorMessage = "身份校验未返回有效凭证"
                await reloadCaptcha()
                return
            }
            verifyResult = result
            step = 2
        } catch let error as SCUError {
            if case .forgotPassword(let message, let code) = error {
                // 400 验证码错误 / 439 验证码过期 → 刷新验证码重填
                if code == 400 || code == 439 {
                    await reloadCaptcha()
                }
                errorMessage = message
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "校验失败"
        }
    }

    // MARK: - 第 ② 步

    @ViewBuilder
    private var stepVerifyCode: some View {
        Section("接收方式") {
            if let result = verifyResult, !result.phone.isEmpty {
                channelRow("phone", label: "短信", detail: ForgotPasswordService.maskedPhone(result.phone))
            }
            if let result = verifyResult, !result.email.isEmpty {
                channelRow("email", label: "邮箱", detail: ForgotPasswordService.maskedEmail(result.email))
            }
        }
        Section("验证码") {
            HStack {
                TextField("输入收到的验证码", text: $smsCode)
                    .keyboardType(.numberPad)
                if codeSent {
                    Button("重新发送") {
                        Task { await sendCode() }
                    }
                    .font(.footnote)
                    .disabled(isWorking)
                }
            }
        }
        Section {
            Button {
                Task {
                    if codeSent {
                        await verifyCode()
                    } else {
                        await sendCode()
                    }
                }
            } label: {
                rowButton(codeSent ? "下一步" : "发送验证码", loading: isWorking)
            }
            .disabled(smsCode.isEmpty && codeSent || isWorking)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func channelRow(_ value: String, label: String, detail: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                channel = value
                codeSent = false
                smsCode = ""
            }
        } label: {
            HStack {
                Image(systemName: channel == value ? "circle.inset.filled" : "circle")
                    .foregroundStyle(channel == value ? Color.accentColor : Color(.systemGray3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func sendCode() async {
        guard let verifyResult else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.obtainCode(username: username, type: channel, sToken: verifyResult.sToken)
            codeSent = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "发送失败"
        }
    }

    private func verifyCode() async {
        guard let verifyResult else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            resetToken = try await service.verifyCode(
                username: username, type: channel, code: smsCode, sToken: verifyResult.sToken
            )
            step = 3
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "验证码校验失败"
        }
    }

    // MARK: - 第 ③ 步

    @ViewBuilder
    private var stepNewPassword: some View {
        Section {
            SecureField("新密码（8 位以上）", text: $newPassword)
            SecureField("确认新密码", text: $confirmPassword)
        } header: {
            Text("新密码")
        } footer: {
            Text("重置成功后请使用新密码重新登录")
        }
        Section {
            Button {
                Task { await submitNewPassword() }
            } label: {
                rowButton("重置密码", loading: isWorking)
            }
            .disabled(newPassword.count < 8 || newPassword != confirmPassword || isWorking)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func submitNewPassword() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await service.submit(
                token: resetToken, password: newPassword, username: username, channel: channel
            )
            doneMessage = "密码重置成功，请使用新密码登录"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "重置失败"
        }
    }

    private func rowButton(_ label: String, loading: Bool) -> some View {
        HStack {
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
