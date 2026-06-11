import SwiftUI

struct ForcePasswordChangeView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var newPasswordVisible = false
    @State private var confirmPasswordVisible = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case newPassword
        case confirmPassword
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("AuthBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color(red: 0.09, green: 0.09, blue: 0.18).opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 6) {
                    Text("Change Password")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.063, green: 0.094, blue: 0.157))

                    Text("Choose a personal password for Employee ID \(authStore.currentSession?.user.employeeId ?? "").")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.400))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

                passwordField(
                    title: "New password",
                    text: $newPassword,
                    isVisible: $newPasswordVisible,
                    focused: .newPassword
                )
                .padding(.bottom, 16)

                passwordField(
                    title: "Confirm password",
                    text: $confirmPassword,
                    isVisible: $confirmPasswordVisible,
                    focused: .confirmPassword
                )
                .padding(.bottom, 16)

                if let error = authStore.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.80, green: 0.12, blue: 0.12))
                        .padding(.bottom, 12)
                }

                Button {
                    Task {
                        await authStore.changeRequiredPassword(
                            newPassword: newPassword,
                            confirmPassword: confirmPassword
                        )
                    }
                } label: {
                    ZStack {
                        if authStore.isChangingPassword {
                            ProgressView().tint(.white)
                        } else {
                            Text("Update Password")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.102, green: 0.792, blue: 0.043),
                                Color(red: 0.239, green: 0.616, blue: 0.008)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 100, style: .continuous)
                    )
                }
                .disabled(authStore.isChangingPassword)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .ignoresSafeArea()
        .onAppear { focusedField = .newPassword }
    }

    private func passwordField(
        title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        focused: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(red: 0.278, green: 0.329, blue: 0.400))

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                    .frame(width: 20)

                Group {
                    if isVisible.wrappedValue {
                        TextField(title, text: text)
                    } else {
                        SecureField(title, text: text)
                    }
                }
                .textContentType(.password)
                .font(.system(size: 14))
                .focused($focusedField, equals: focused)

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 0.596, green: 0.635, blue: 0.702))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        focusedField == focused
                            ? Color(red: 0.10, green: 0.79, blue: 0.04)
                            : Color(red: 0.596, green: 0.635, blue: 0.702),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

#Preview {
    ForcePasswordChangeView()
        .environment(AuthStore())
}
