import Combine
import SwiftUI

/// 4-digit arrival OTP entry sheet.
///
/// Caller is responsible for invoking `requestArrivalOtp` once before
/// presenting the sheet (so the SMS goes out and we know the masked phone +
/// expiry). The sheet handles `verifyArrivalOtp` and resend internally; on
/// successful verify it calls `onVerified` with the entered OTP and dismisses.
struct ArrivalOtpSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let visitId: String
    let phoneMasked: String?
    let initialExpiresIn: Int
    let initialResendCooldown: Int
    let lat: Double
    let lng: Double
    /// Storage id of the arrival photo captured & uploaded before this sheet was
    /// shown. Forwarded with the OTP verify so the backend links the photo to the
    /// fieldVisit row at arrival time (parity with Android ArrivalOtpBottomSheet).
    let arrivalPhotoStorageId: String?
    let onVerified: (String) -> Void

    @State private var otp: String = ""
    @State private var errorText: String?
    @State private var expirySecondsRemaining: Int
    @State private var resendSecondsRemaining: Int
    @State private var phoneMaskedState: String?
    @State private var isVerifying = false
    @State private var isResending = false
    @FocusState private var fieldFocused: Bool

    private let geoAPI = GeoTrackAPIService.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        visitId: String,
        phoneMasked: String?,
        initialExpiresIn: Int,
        initialResendCooldown: Int,
        lat: Double,
        lng: Double,
        arrivalPhotoStorageId: String? = nil,
        onVerified: @escaping (String) -> Void
    ) {
        self.visitId = visitId
        self.phoneMasked = phoneMasked
        self.initialExpiresIn = initialExpiresIn
        self.initialResendCooldown = initialResendCooldown
        self.lat = lat
        self.lng = lng
        self.arrivalPhotoStorageId = arrivalPhotoStorageId
        self.onVerified = onVerified
        _expirySecondsRemaining = State(initialValue: initialExpiresIn)
        _resendSecondsRemaining = State(initialValue: initialResendCooldown)
        _phoneMaskedState = State(initialValue: phoneMasked)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("We have send an OTP to Client!")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x101828))
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x475467))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            otpBoxes
                .padding(.top, 4)

            // Hidden TextField receives keyboard input; boxes are display-only.
            TextField("", text: $otp)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($fieldFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
                .onChange(of: otp) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue { otp = digits }
                    if digits.count > 4 { otp = String(digits.prefix(4)) }
                    errorText = nil
                }

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }

            Button {
                Task { await performVerify() }
            } label: {
                HStack {
                    if isVerifying { ProgressView().tint(.white) }
                    Text("Submit").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(otp.count != 4 || isVerifying)

            Button {
                Task { await performResend() }
            } label: {
                if isResending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Resending…")
                    }
                    .font(.subheadline)
                } else if resendSecondsRemaining > 0 {
                    Text("Haven't received the verification code? Resend in \(resendSecondsRemaining)s.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Haven't received the verification code? Resend it.")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .disabled(resendSecondsRemaining > 0 || isResending)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .appLibraryNativeSheet([.medium, .large])
        .onAppear { fieldFocused = true }
        .onReceive(timer) { _ in tick() }
        .onTapGesture { fieldFocused = true }
    }

    // MARK: - Subviews

    private var otpBoxes: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                otpBox(at: index)
            }
        }
        .onTapGesture { fieldFocused = true }
    }

    private func otpBox(at index: Int) -> some View {
        let chars = Array(otp)
        let char: String = index < chars.count ? String(chars[index]) : ""
        let isActive = index == chars.count
        return Text(char)
            .font(.title.weight(.semibold))
            .frame(width: 56, height: 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive && fieldFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 2 : 1)
            )
    }

    private var subtitleText: String {
        var msg = "Please confirm if you have seen or met the client at this location."
        if let phoneMaskedState, !phoneMaskedState.isEmpty {
            msg += " OTP sent to \(phoneMaskedState)."
        }
        if expirySecondsRemaining > 0 {
            let mm = expirySecondsRemaining / 60
            let ss = expirySecondsRemaining % 60
            msg += String(format: " Expires in %d:%02d.", mm, ss)
        } else {
            msg += " OTP expired — tap Resend."
        }
        return msg
    }

    // MARK: - Timer

    private func tick() {
        if expirySecondsRemaining > 0 { expirySecondsRemaining -= 1 }
        if resendSecondsRemaining > 0 { resendSecondsRemaining -= 1 }
    }

    // MARK: - Actions

    private func performVerify() async {
        guard otp.count == 4 else {
            errorText = "Enter all 4 digits"
            return
        }
        isVerifying = true
        errorText = nil
        defer { isVerifying = false }
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let resp = try await geoAPI.verifyArrivalOtp(
                visitId: visitId,
                otp: otp,
                lat: lat,
                lng: lng,
                arrivalPhotoStorageId: arrivalPhotoStorageId
            )
            if resp.success {
                onVerified(otp)
            } else {
                otp = ""
                fieldFocused = true
                if let attempts = resp.attemptsRemaining, attempts >= 0 {
                    errorText = (resp.error ?? "Invalid OTP") + " (\(attempts) attempts left)"
                } else {
                    errorText = resp.error ?? "Invalid OTP"
                }
            }
        } catch {
            errorText = "Network error: \(error.localizedDescription)"
        }
    }

    private func performResend() async {
        isResending = true
        errorText = nil
        defer { isResending = false }
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let resp = try await geoAPI.requestArrivalOtp(
                visitId: visitId,
                lat: lat,
                lng: lng
            )
            if resp.success {
                otp = ""
                fieldFocused = true
                phoneMaskedState = resp.contactPhoneMasked ?? phoneMaskedState
                expirySecondsRemaining = resp.otpExpiresInSeconds ?? 600
                resendSecondsRemaining = resp.resendCooldownSeconds ?? 60
            } else {
                errorText = resp.error ?? "Failed to resend OTP"
            }
        } catch {
            errorText = "Network error: \(error.localizedDescription)"
        }
    }

    private func requireToken() throws -> String {
        if let token = authStore.currentSession?.token { return token }
        if let token = try KeychainTokenStore().load()?.token { return token }
        throw NSError(domain: "ArrivalOtpSheet", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }
}
