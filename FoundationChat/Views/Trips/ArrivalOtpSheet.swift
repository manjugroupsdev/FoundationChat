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
    let clientPlaceVisitId: String?
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
    @State private var isRequestingAssistance = false
    @State private var showAssistancePrompt = false
    @State private var assistanceRemark = ""
    @State private var assistanceConfirmation: String?
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
        clientPlaceVisitId: String? = nil,
        arrivalPhotoStorageId: String? = nil,
        onVerified: @escaping (String) -> Void
    ) {
        self.visitId = visitId
        self.phoneMasked = phoneMasked
        self.initialExpiresIn = initialExpiresIn
        self.initialResendCooldown = initialResendCooldown
        self.lat = lat
        self.lng = lng
        self.clientPlaceVisitId = clientPlaceVisitId
        self.arrivalPhotoStorageId = arrivalPhotoStorageId
        self.onVerified = onVerified
        _expirySecondsRemaining = State(initialValue: initialExpiresIn)
        _resendSecondsRemaining = State(initialValue: initialResendCooldown)
        _phoneMaskedState = State(initialValue: phoneMasked)
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 38, height: 5)
                .padding(.top, 8)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 58, height: 58)
                .background(Color(hex: 0x0B61CA).opacity(0.10), in: Circle())

            VStack(spacing: 5) {
                Text("Verify client arrival")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitleText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hex: 0xB42318))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xB42318).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await performVerify() }
                } label: {
                    HStack {
                        if isVerifying { ProgressView().tint(.white) }
                        Text("Verify OTP").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(hex: 0x2DAE12))
                .disabled(otp.count != 4 || isVerifying)
            }

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

            if clientPlaceVisitId != nil {
                Button {
                    fieldFocused = false
                    showAssistancePrompt = true
                } label: {
                    HStack(spacing: 7) {
                        if isRequestingAssistance {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                        }
                        Text("Request GM for OTP")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isRequestingAssistance)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .appLibraryNativeSheet([.medium, .large])
        .onAppear { fieldFocused = true }
        .onReceive(timer) { _ in tick() }
        .onTapGesture { fieldFocused = true }
        .alert("Request GM for OTP", isPresented: $showAssistancePrompt) {
            TextField("Remark (optional)", text: $assistanceRemark, axis: .vertical)
            Button("Cancel", role: .cancel) {}
            Button("Send Request") {
                Task { await requestGmAssistance() }
            }
        } message: {
            Text("Your GM will receive the client, location, distance, and OTP context.")
        }
        .alert("Request Sent", isPresented: assistanceConfirmationBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(assistanceConfirmation ?? "Your manager has been notified.")
        }
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
        var msg = "Enter the 4-digit code shared by the client."
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

    private var assistanceConfirmationBinding: Binding<Bool> {
        Binding(
            get: { assistanceConfirmation != nil },
            set: { if !$0 { assistanceConfirmation = nil } }
        )
    }

    private func requestGmAssistance() async {
        guard let clientPlaceVisitId, !clientPlaceVisitId.isEmpty else { return }
        isRequestingAssistance = true
        errorText = nil
        defer { isRequestingAssistance = false }
        do {
            let token = try requireToken()
            geoAPI.tokenProvider = { token }
            let trimmedRemark = assistanceRemark.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await geoAPI.requestCpOtpAssist(
                clientPlaceVisitId: clientPlaceVisitId,
                lat: lat,
                lng: lng,
                remark: trimmedRemark.isEmpty ? nil : trimmedRemark
            )
            assistanceRemark = ""
            let managerName = response.gmName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let recipient = managerName.flatMap { $0.isEmpty ? nil : $0 } ?? "your manager"
            assistanceConfirmation = "Sent to \(recipient). They can read the OTP back to you."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func requireToken() throws -> String {
        if let token = authStore.currentSession?.token { return token }
        if let token = try KeychainTokenStore().load()?.token { return token }
        throw NSError(domain: "ArrivalOtpSheet", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }
}
