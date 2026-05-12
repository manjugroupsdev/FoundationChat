import SwiftUI

// MARK: - Root

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var step: AuthStep = .phone
    @State private var phoneNumber = ""
    @State private var verifiedPhone = ""
    @State private var otpDigits = Array(repeating: "", count: 6)
    @FocusState private var phoneFieldFocused: Bool
    @FocusState private var focusedOtpBox: Int?
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dark blurred auth background
                Image("AuthBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                // Gradient overlay to deepen top
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.09, blue: 0.18).opacity(0.7), .clear],
                    startPoint: .top, endPoint: .center
                )
                .ignoresSafeArea()

                // Badge + sheet move together as keyboard rises/falls
                ZStack(alignment: .bottom) {
                    if step == .otp {
                        shieldBadge
                            .offset(y: -(sheetHeight(geo) - 31))
                            .zIndex(1)
                            .transition(.scale.combined(with: .opacity))
                    }
                    bottomSheet(geo: geo)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -keyboardHeight)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeOut(duration: duration)) {
                keyboardHeight = 0
            }
        }
        .onChange(of: authStore.status) { _, _ in }
    }

    // MARK: - Shield Badge (OTP step)

    private var shieldBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.45, blue: 0.96),
                                 Color(red: 0.06, green: 0.29, blue: 0.79)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 62, height: 62)
                .shadow(color: Color(red: 0.10, green: 0.45, blue: 0.96).opacity(0.45), radius: 12, y: 4)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Bottom Sheet

    private func sheetHeight(_ geo: GeometryProxy) -> CGFloat {
        step == .phone ? geo.size.height * 0.60 : geo.size.height * 0.62
    }

    private func bottomSheet(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text(step == .phone ? "Sign In" : "Verify OTP")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))

                    Text(step == .phone
                         ? "Sign in to my account"
                         : "Code sent to +91 \(verifiedPhone)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.400))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

                // Step content
                Group {
                    if step == .phone {
                        phoneStepContent
                    } else {
                        otpStepContent
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, step == .otp ? 44 : 40)
            .padding(.bottom, geo.safeAreaInsets.bottom + 28)
            .background(
                .white,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .path(in: CGRect(
                        x: 0, y: 0,
                        width: geo.size.width,
                        height: sheetHeight(geo) + 60
                    ))
            )
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    // MARK: - Phone Step

    private var phoneStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phone Number label
            Text("Phone Number")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.400))
                .padding(.bottom, 4)

            // Phone input
            phoneInputField
                .padding(.bottom, 12)

            // Forgot password
            HStack {
                Spacer()
                Button("Forgot Password?") {}
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.043, green: 0.380, blue: 0.792))
            }
            .padding(.bottom, 24)

            // Error
            if let err = authStore.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.47))
                    .padding(.bottom, 8)
            }

            // Send OTP button
            sendOtpButton
                .padding(.bottom, 24)

            // OR divider
            orDivider
                .padding(.bottom, 24)

            // Employee ID button
            employeeIdButton
        }
    }

    private var phoneInputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "phone")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                .frame(width: 20)

            Text("+91")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.012, green: 0.016, blue: 0.027))

            Rectangle()
                .fill(Color(red: 0.596, green: 0.635, blue: 0.702).opacity(0.4))
                .frame(width: 1, height: 18)

            TextField("Enter phone number", text: $phoneNumber)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.012, green: 0.016, blue: 0.027))
                .focused($phoneFieldFocused)
                .onAppear { phoneFieldFocused = true }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    phoneFieldFocused
                        ? Color(red: 0.10, green: 0.79, blue: 0.04)
                        : Color(red: 0.596, green: 0.635, blue: 0.702),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sendOtpButton: some View {
        Button {
            Task { await handleSendOtp() }
        } label: {
            ZStack {
                if authStore.isRequestingOTP {
                    ProgressView().tint(.white)
                } else {
                    Text("Send OTP")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.102, green: 0.792, blue: 0.043),
                             Color(red: 0.239, green: 0.616, blue: 0.008)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 100, style: .continuous)
            )
        }
        .disabled(phoneNumber.filter(\.isNumber).count < 10 || authStore.isRequestingOTP)
        .opacity(phoneNumber.filter(\.isNumber).count < 10 ? 0.6 : 1)
        .buttonStyle(.plain)
    }

    private var orDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color(red: 0.816, green: 0.835, blue: 0.867))
                .frame(height: 1)
            Text("OR")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
            Rectangle()
                .fill(Color(red: 0.816, green: 0.835, blue: 0.867))
                .frame(height: 1)
        }
    }

    private var employeeIdButton: some View {
        Button {
            // Coming soon
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.102, green: 0.792, blue: 0.043))
                Text("Sign In With Employee ID")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.102, green: 0.792, blue: 0.043))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    .strokeBorder(Color(red: 0.102, green: 0.792, blue: 0.043), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - OTP Step

    private var otpStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 6 OTP boxes
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    OtpBox(
                        digit: $otpDigits[i],
                        isFocused: focusedOtpBox == i,
                        onInput: { handleOtpInput(at: i, value: $0) },
                        onDelete: { handleOtpDelete(at: i) }
                    )
                    .focused($focusedOtpBox, equals: i)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)

            // Error
            if let err = authStore.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.47))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }

            // Resend
            HStack(spacing: 4) {
                Text("Haven't received the code?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.012, green: 0.016, blue: 0.027))
                Button("Resend it.") {
                    Task { await handleSendOtp() }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.043, green: 0.380, blue: 0.792))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // Change phone (back)
            Button {
                withAnimation(.spring(response: 0.35)) {
                    step = .phone
                    otpDigits = Array(repeating: "", count: 6)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Change +91 \(verifiedPhone)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.400))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            // Verify button
            verifyButton
        }
        .onAppear { focusedOtpBox = 0 }
    }

    private var verifyButton: some View {
        Button {
            Task { await handleVerifyOtp() }
        } label: {
            ZStack {
                if authStore.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("Verify OTP")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.102, green: 0.792, blue: 0.043),
                             Color(red: 0.239, green: 0.616, blue: 0.008)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 100, style: .continuous)
            )
        }
        .disabled(otpDigits.joined().count < 6 || authStore.isAuthenticating)
        .opacity(otpDigits.joined().count < 6 ? 0.6 : 1)
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func handleSendOtp() async {
        do {
            let phone = try await authStore.requestOTP(phoneNumber: phoneNumber)
            await MainActor.run {
                verifiedPhone = phone
                otpDigits = Array(repeating: "", count: 6)
                withAnimation(.spring(response: 0.4)) { step = .otp }
            }
        } catch {}
    }

    private func handleVerifyOtp() async {
        await authStore.verifyOTP(phoneNumber: verifiedPhone, code: otpDigits.joined())
    }

    private func handleOtpInput(at index: Int, value: String) {
        let digit = value.filter(\.isNumber).prefix(1)
        otpDigits[index] = String(digit)
        if !digit.isEmpty && index < 5 {
            focusedOtpBox = index + 1
        }
    }

    private func handleOtpDelete(at index: Int) {
        if otpDigits[index].isEmpty && index > 0 {
            focusedOtpBox = index - 1
            otpDigits[index - 1] = ""
        } else {
            otpDigits[index] = ""
        }
    }
}

// MARK: - OTP Box

private enum AuthStep { case phone, otp }

private struct OtpBox: View {
    @Binding var digit: String
    let isFocused: Bool
    let onInput: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? Color(red: 0.102, green: 0.792, blue: 0.043)
                        : Color(red: 0.918, green: 0.925, blue: 0.941),
                    lineWidth: 1.5
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white)
                )

            Text(digit.isEmpty ? "0" : digit)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(digit.isEmpty
                                 ? Color(red: 0.918, green: 0.925, blue: 0.941)
                                 : Color(red: 0.063, green: 0.094, blue: 0.157))

            // Hidden text field for input capture
            OtpTextField(text: $digit, onInput: onInput, onDelete: onDelete)
                .opacity(0.011)
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OTP TextField wrapper

private struct OtpTextField: UIViewRepresentable {
    @Binding var text: String
    let onInput: (String) -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> _OtpUITextField {
        let tf = _OtpUITextField()
        tf.keyboardType = .numberPad
        tf.textContentType = .oneTimeCode
        tf.delegate = context.coordinator
        tf.onDeleteBackward = onDelete
        tf.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: _OtpUITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OtpTextField
        init(_ parent: OtpTextField) { self.parent = parent }

        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { return true }
            let digits = string.filter(\.isNumber)
            if !digits.isEmpty { parent.onInput(String(digits.prefix(1))) }
            return false
        }
    }
}

final class _OtpUITextField: UITextField {
    var onDeleteBackward: (() -> Void)?
    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}
