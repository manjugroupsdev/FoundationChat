import SwiftUI

struct LoginView: View {
  private enum SheetRoute: String, Identifiable {
    case signIn
    var id: String { rawValue }
  }

  @State private var activeSheet: SheetRoute?

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ZStack {
          ManjuChatOnboardingBackground()

          VStack(spacing: 0) {
            headline(maxWidth: min(proxy.size.width - 48, 340))
              .padding(.top, proxy.safeAreaInsets.top + 28)

            Spacer(minLength: 24)

            ManjuChatOnboardingIllustration()
              .frame(width: min(proxy.size.width - 80, 320))

            Spacer(minLength: 30)

            getStartedButton()
          }
          .padding(.horizontal, 24)
          .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
        }
        .ignoresSafeArea()
      }
      .toolbar(.hidden, for: .navigationBar)
      .sheet(item: $activeSheet) { route in
        switch route {
        case .signIn:
          SignInSheet()
        }
      }
    }
  }

  @ViewBuilder
  private func headline(maxWidth: CGFloat) -> some View {
    Text("ManjuChat brings the team together, wherever you are")
      .font(.system(size: 34, weight: .bold))
      .foregroundStyle(.white)
      .frame(maxWidth: maxWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func getStartedButton() -> some View {
    Button {
      activeSheet = .signIn
    } label: {
      Text("Get started")
        .font(.title3.weight(.bold))
        .foregroundStyle(Color(red: 0.29, green: 0.08, blue: 0.29))
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
          .white,
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Sign In Sheet

private struct SignInSheet: View {
  private enum Step {
    case phone
    case otp
  }

  private enum FocusField {
    case phone
    case otp
  }

  @Environment(AuthStore.self) private var authStore
  @Environment(\.dismiss) private var dismiss

  @FocusState private var focusedField: FocusField?
  @State private var step: Step = .phone
  @State private var phoneNumber = ""
  @State private var verifiedPhoneNumber = ""
  @State private var otpCode = ""

  private var trimmedPhoneNumber: String {
    phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedOtpCode: String {
    otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(step == .phone ? "Sign in with your phone number" : "Enter the OTP")
        .font(.title3.weight(.semibold))
        .padding(.top, 4)

      if step == .otp {
        Button {
          withAnimation(.snappy(duration: 0.25)) {
            step = .phone
            otpCode = ""
            verifiedPhoneNumber = ""
          }
        } label: {
          Text(verifiedPhoneNumber)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      }

      Group {
        switch step {
        case .phone:
          phoneField
        case .otp:
          otpField
        }
      }

      if let errorMessage = authStore.errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      actionButton
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 20)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(28)
    .interactiveDismissDisabled(authStore.isAuthenticating || authStore.isRequestingOTP)
    .animation(.snappy(duration: 0.25), value: step)
    .onAppear {
      DispatchQueue.main.async {
        focusedField = .phone
      }
    }
    .onChange(of: step) { _, newStep in
      DispatchQueue.main.async {
        focusedField = newStep == .phone ? .phone : .otp
      }
    }
    .onChange(of: authStore.status) { _, status in
      if status == .signedIn {
        dismiss()
      }
    }
  }

  private var phoneField: some View {
    TextField("+91 9876543210", text: $phoneNumber)
      .textInputAutocapitalization(.never)
      .keyboardType(.phonePad)
      .textContentType(.telephoneNumber)
      .autocorrectionDisabled()
      .focused($focusedField, equals: .phone)
      .padding(.horizontal, 16)
      .frame(height: 54)
      .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var otpField: some View {
    TextField("6-digit code", text: $otpCode)
      .keyboardType(.numberPad)
      .textContentType(.oneTimeCode)
      .focused($focusedField, equals: .otp)
      .padding(.horizontal, 16)
      .frame(height: 54)
      .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var actionButton: some View {
    Button {
      switch step {
      case .phone:
        Task {
          do {
            let normalizedPhoneNumber = try await authStore.requestOTP(phoneNumber: trimmedPhoneNumber)
            await MainActor.run {
              verifiedPhoneNumber = normalizedPhoneNumber
              otpCode = ""
              withAnimation(.snappy(duration: 0.25)) {
                step = .otp
              }
            }
          } catch {
            // Error is surfaced through authStore.errorMessage.
          }
        }
      case .otp:
        Task {
          await authStore.verifyOTP(phoneNumber: verifiedPhoneNumber, code: trimmedOtpCode)
        }
      }
    } label: {
      HStack(spacing: 10) {
        if authStore.isRequestingOTP || authStore.isAuthenticating {
          ProgressView()
            .tint(step == .phone ? .primary : .white)
        }
        Text(step == .phone ? "Send OTP" : "Verify OTP")
          .font(.headline.weight(.semibold))
      }
      .foregroundStyle(step == .phone ? Color.primary : Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(buttonBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isButtonDisabled)
  }

  private var buttonBackground: AnyShapeStyle {
    switch step {
    case .phone:
      AnyShapeStyle(Color(.systemGray5))
    case .otp:
      AnyShapeStyle(
        LinearGradient(
          colors: [
            Color(red: 0.24, green: 0.07, blue: 0.30),
            Color(red: 0.43, green: 0.12, blue: 0.46)
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
    }
  }

  private var isButtonDisabled: Bool {
    switch step {
    case .phone:
      authStore.isRequestingOTP || trimmedPhoneNumber.isEmpty
    case .otp:
      authStore.isAuthenticating || trimmedOtpCode.isEmpty || verifiedPhoneNumber.isEmpty
    }
  }
}

// MARK: - Background

private struct ManjuChatOnboardingBackground: View {
  var body: some View {
    Color(red: 0.29, green: 0.08, blue: 0.29)
      .ignoresSafeArea()
  }
}

// MARK: - Illustration

private struct ManjuChatOnboardingIllustration: View {
  var body: some View {
    Image("LoginCenterIllustration")
      .resizable()
      .scaledToFit()
      .clipShape(.rect(cornerRadius: 24))
  }
}
