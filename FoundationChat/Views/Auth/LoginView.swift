import SwiftUI
import UIKit

// MARK: - Root

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var step: AuthStep = .phone
    @State private var phoneNumber = ""
    @State private var verifiedPhone = ""
    @State private var employeeId = ""
    @State private var employeePassword = ""
    @State private var employeePasswordVisible = false
    @State private var otpCode = ""
    @FocusState private var phoneFieldFocused: Bool
    // Plain state, not @FocusState: the OTP field is a UIKit text field that
    // takes first responder from this value (OtpCodeField.updateUIView). No
    // view is bound to it with .focused(), and SwiftUI resets a @FocusState
    // with no focusable target to nil, which left the field untypeable.
    @State private var otpFocused = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var employeeFieldFocused: EmployeeField?

    private enum EmployeeField {
        case employeeId
        case password
    }

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

                // Sheet moves as a single unit; the OTP badge is anchored to its top edge.
                bottomSheet(geo: geo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
            .contentShape(Rectangle())
            .simultaneousGesture(backSwipeGesture)
        }
        // Ignore the device container inset but keep the keyboard safe area.
        // SwiftUI can then perform one native keyboard transition instead of
        // competing with a second full-screen offset animation.
        .ignoresSafeArea(.container, edges: .all)
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
        switch step {
        case .phone: return geo.size.height * 0.60
        // Six boxes, resend, change-number and the button: 0.62 left a band of
        // empty space under "Verify OTP", as 0.70 did on the employee step.
        case .otp: return geo.size.height * 0.45
        // The shortest step — two fields, a button and the back link. It used
        // to ask for MORE height than the phone step, which has two further
        // buttons and the OR divider, so the card ended in a band of empty
        // space below "Use mobile number instead".
        case .employee: return geo.size.height * 0.52
        }
    }

    private func bottomSheet(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.appPrimaryText)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

                // Step content
                Group {
                    if step == .phone {
                        phoneStepContent
                    } else if step == .otp {
                        otpStepContent
                    } else {
                        employeeStepContent
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, step == .otp ? 44 : 40)
            // Not `geo.safeAreaInsets.bottom + 28`: the container inset is
            // ignored above, so that inset is 0 until the keyboard opens - and
            // then it is the keyboard height, which the frame has already
            // shrunk by. Adding it counted the keyboard twice: an empty band
            // under the last control and the title pushed under the clock.
            .padding(.bottom, 28)
            // Keeps the sheet's designed proportion when the content is short,
            // and the full screen width, both of which the fixed background
            // rect used to provide. It is a MINIMUM now, so taller content
            // grows the card instead of overflowing it.
            .frame(maxWidth: .infinity, minHeight: sheetHeight(geo), alignment: .top)
            // The surface used to be painted into a FIXED rect - a fraction
            // of the screen height (sheetHeight + 60) rather than the card's
            // own size. Whenever the content ran taller than that guess, with
            // the keyboard up or at larger text sizes, the last control spilled
            // below the white area onto the dark backdrop: the Employee ID
            // button appeared to hang outside the sheet. Filling the card's
            // real bounds tracks the content instead, and the negative bottom
            // padding keeps the lower corners off-screen so only the top two
            // are ever seen, exactly as before.
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.appElevatedSurface)
                    .padding(.bottom, -60)
            )
            .overlay(alignment: .top) {
                if step == .otp {
                    shieldBadge
                        .offset(y: -31)
                        .zIndex(1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Phone Step

    private var phoneStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phone Number label
            Text("Phone Number")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appSecondaryText)
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
                .foregroundStyle(Color.appPrimaryText)

            Rectangle()
                .fill(Color(red: 0.596, green: 0.635, blue: 0.702).opacity(0.4))
                .frame(width: 1, height: 18)

            TextField("Enter phone number", text: $phoneNumber)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .font(.system(size: 14))
                .foregroundStyle(Color.appPrimaryText)
                .tint(Color(red: 0.10, green: 0.45, blue: 0.96))
                .focused($phoneFieldFocused)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color.appFieldBackground)
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
            handleSendOtp()
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
                .fill(Color.appSeparator)
                .frame(height: 1)
            Text("OR")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
            Rectangle()
                .fill(Color.appSeparator)
                .frame(height: 1)
        }
    }

    private var employeeIdButton: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                authStore.clearError()
                clearFocus()
                step = .employee
            }
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

    // MARK: - Employee Step

    private var employeeStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            employeeTextField
                .padding(.bottom, 16)

            employeePasswordField
                .padding(.bottom, 16)

            if let err = authStore.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.47))
                    .padding(.bottom, 8)
            }

            employeeLoginButton
                .padding(.bottom, 20)

            Button {
                withAnimation(.spring(response: 0.35)) {
                    authStore.clearError()
                    employeePassword = ""
                    clearFocus()
                    step = .phone
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Use mobile number instead")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.appSecondaryText)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: employeeId) { _, _ in
            authStore.clearError()
        }
        .onChange(of: employeePassword) { _, _ in
            authStore.clearError()
        }
    }

    private var employeeTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Employee ID")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appSecondaryText)

            HStack(spacing: 10) {
                Image(systemName: "person")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                    .frame(width: 20)

                TextField("Enter Employee ID", text: $employeeId)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appPrimaryText)
                    .tint(Color(red: 0.10, green: 0.45, blue: 0.96))
                    .focused($employeeFieldFocused, equals: .employeeId)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.appFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        employeeFieldFocused == .employeeId
                            ? Color(red: 0.10, green: 0.79, blue: 0.04)
                            : Color(red: 0.596, green: 0.635, blue: 0.702),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var employeePasswordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Password")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appSecondaryText)

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                    .frame(width: 20)

                Group {
                    if employeePasswordVisible {
                        TextField("Enter password", text: $employeePassword)
                    } else {
                        SecureField("Enter password", text: $employeePassword)
                    }
                }
                .textContentType(.password)
                .font(.system(size: 14))
                .foregroundStyle(Color.appPrimaryText)
                .tint(Color(red: 0.10, green: 0.45, blue: 0.96))
                .focused($employeeFieldFocused, equals: .password)

                Button {
                    employeePasswordVisible.toggle()
                } label: {
                    Image(systemName: employeePasswordVisible ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.appFieldBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        employeeFieldFocused == .password
                            ? Color(red: 0.10, green: 0.79, blue: 0.04)
                            : Color(red: 0.596, green: 0.635, blue: 0.702),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var employeeLoginButton: some View {
        Button {
            Task { await handleEmployeeLogin() }
        } label: {
            ZStack {
                if authStore.isEmployeeLoginInProgress {
                    ProgressView().tint(.white)
                } else {
                    Text("Sign In")
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
        .disabled(employeeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || employeePassword.isEmpty || authStore.isEmployeeLoginInProgress)
        .opacity(employeeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || employeePassword.isEmpty ? 0.6 : 1)
        .buttonStyle(.plain)
    }

    // MARK: - OTP Step

    private var otpStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 6 OTP boxes over one input field, so the keyboard stays up.
            OtpCodeBoxes(code: otpCode, isFocused: $otpFocused, onChange: handleOtpChange)
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
                    .foregroundStyle(Color.appPrimaryText)
                Button("Resend it.") {
                    handleSendOtp()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.043, green: 0.380, blue: 0.792))
                .disabled(authStore.isRequestingOTP)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            // Change phone (back)
            Button {
                withAnimation(.spring(response: 0.35)) {
                    authStore.clearError()
                    step = .phone
                    otpCode = ""
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Change +91 \(verifiedPhone)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.appSecondaryText)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            // Verify button
            verifyButton
        }
        .onAppear { refocusOtp() }
        .onChange(of: authStore.isRequestingOTP) { wasRequesting, isRequesting in
            // Sending the code must never prevent staff from entering it. Once
            // delivery setup finishes, restore the keyboard if they have not
            // already completed the code.
            if wasRequesting && !isRequesting, otpCode.count < OtpCodeInput.length {
                refocusOtp()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Messages after copying the code.
            if phase == .active { refocusOtp() }
        }
    }

    /// Puts the caret back in the OTP field, re-asserting it even when the
    /// field is already marked focused.
    ///
    /// iOS resigns first responder when the app goes to the background (e.g.
    /// to copy the code from Messages) while `otpFocused` stays true, so
    /// SwiftUI sees no change and never re-attaches the keyboard. Clearing the
    /// value first guarantees the transition that does.
    private func refocusOtp() {
        otpFocused = false
        DispatchQueue.main.async { otpFocused = true }
    }

    private var verifyButton: some View {
        Button {
            Task { await handleVerifyOtp() }
        } label: {
            ZStack {
                if authStore.isAuthenticating {
                    AuthPulsingLoadingCircle()
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
        .disabled(otpCode.count < OtpCodeInput.length || authStore.isAuthenticating || authStore.isRequestingOTP)
        .opacity(otpCode.count < OtpCodeInput.length || authStore.isRequestingOTP ? 0.6 : 1)
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func handleSendOtp() {
        let phone = phoneNumber.filter(\.isNumber)
        guard phone.count == 10, !authStore.isRequestingOTP else { return }

        let isResend = step == .otp
        if !isResend {
            // Do not make the input wait for the network request. SMS gateways
            // may deliver the code before the API acknowledges it, and waiting
            // here made the OTP screen appear frozen on slow connections.
            verifiedPhone = phone
            otpCode = ""
            clearFocus()
            withAnimation(.spring(response: 0.4)) { step = .otp }
        }

        Task {
            do {
                _ = try await authStore.requestOTP(phoneNumber: phone)
            } catch {
                // AuthStore exposes the user-facing error. Keep the OTP view
                // open so the staff can correct the number or resend.
            }
        }
    }

    private func handleVerifyOtp() async {
        await authStore.verifyOTP(phoneNumber: verifiedPhone, code: otpCode)
    }

    private func handleEmployeeLogin() async {
        await authStore.loginWithEmployeeId(employeeId: employeeId, password: employeePassword)
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.width > 72,
                      abs(value.translation.height) < 60 else { return }
                goBackOneStep()
            }
    }

    private func goBackOneStep() {
        withAnimation(.spring(response: 0.35)) {
            authStore.clearError()
            clearFocus()
            if step == .phone {
                dismissKeyboard()
            } else if step == .otp {
                otpCode = ""
                step = .phone
            } else if step == .employee {
                employeePassword = ""
                step = .phone
            }
        }
    }

    private func clearFocus() {
        phoneFieldFocused = false
        otpFocused = false
        employeeFieldFocused = nil
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var title: String {
        switch step {
        case .phone: return "Sign In"
        case .otp: return "Verify OTP"
        case .employee: return "Employee Login"
        }
    }

    private var subtitle: String {
        switch step {
        case .phone: return "Sign in to my account"
        case .otp:
            return authStore.isRequestingOTP
                ? "Sending code to +91 \(verifiedPhone)"
                : "Code sent to +91 \(verifiedPhone)"
        case .employee: return "Use the password HR created for your account."
        }
    }

    /// The whole code from the OTP field; a complete code verifies at once
    /// (typed, pasted or filled from Messages).
    private func handleOtpChange(_ code: String) {
        otpCode = code
        if code.count == OtpCodeInput.length,
           !authStore.isAuthenticating,
           !authStore.isRequestingOTP {
            otpFocused = false
            Task { await handleVerifyOtp() }
        }
    }
}

// MARK: - OTP Box

private enum AuthStep { case phone, otp, employee }

private struct AuthPulsingLoadingCircle: View {
    @State private var isBright = false

    var body: some View {
        Circle()
            .fill(Color.appSurface.opacity(0.66))
            .frame(width: 22, height: 22)
            .opacity(isBright ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isBright = true
                }
            }
    }
}

/// Six display-only boxes over one nearly transparent text field that holds
/// the whole code. Typing never moves focus, so the keyboard stays open.
private struct OtpCodeBoxes: View {
    let code: String
    @Binding var isFocused: Bool
    let onChange: (String) -> Void

    var body: some View {
        let digits = Array(code)
        let active = OtpCodeInput.activeIndex(for: code)
        HStack(spacing: 6) {
            ForEach(0..<OtpCodeInput.length, id: \.self) { i in
                OtpDigitBox(
                    digit: i < digits.count ? String(digits[i]) : "",
                    highlighted: isFocused && i == active
                )
            }
        }
        .overlay {
            OtpCodeField(code: code, isFocused: $isFocused, onChange: onChange)
                // UIKit skips fully transparent controls in hit testing on
                // some iOS versions; keep it almost invisible but tappable.
                .opacity(0.02)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

private struct OtpDigitBox: View, Equatable {
    let digit: String
    let highlighted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.appFieldBackground)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    highlighted ? Color(red: 0.102, green: 0.792, blue: 0.043) : Color.appSeparator,
                    lineWidth: 1.5
                )
            Text(digit.isEmpty ? "0" : digit)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(digit.isEmpty ? Color.appTertiaryText : Color.appPrimaryText)
        }
        .frame(height: 50)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - OTP text field

private struct OtpCodeField: UIViewRepresentable {
    let code: String
    @Binding var isFocused: Bool
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.tintColor = .clear
        field.textColor = .clear
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != code { field.text = code }
        if isFocused, field.window != nil, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OtpCodeField
        init(_ parent: OtpCodeField) { self.parent = parent }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let next = OtpCodeInput.apply(current: field.text ?? "", range: range, replacement: string)
            if next != (field.text ?? "") {
                field.text = next
                parent.onChange(next)
            }
            return false
        }

        // Keep SwiftUI's focus in step with taps and system resigns, so an
        // update never resigns a field the staff member just tapped.
        func textFieldDidBeginEditing(_ field: UITextField) {
            guard !parent.isFocused else { return }
            DispatchQueue.main.async { self.parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            guard parent.isFocused else { return }
            DispatchQueue.main.async { self.parent.isFocused = false }
        }
    }
}
