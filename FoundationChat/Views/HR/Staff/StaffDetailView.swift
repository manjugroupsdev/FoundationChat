import SwiftUI

struct StaffDetailView: View {
    let staffId: String

    @Environment(AuthStore.self) private var authStore
    @Environment(\.openURL) private var openURL

    @State private var staff: ConvexStaffDetail?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSecurity = false

    private var canManageSecurity: Bool {
        guard authStore.hasPermission("staff.resetDeviceBinding") else { return false }
        let user = authStore.currentSession?.user
        let currentIds = [user?.staffId, user?._id].compactMap { $0 }
        return !currentIds.contains(staffId)
    }

    var body: some View {
        Group {
            if let staff {
                content(for: staff)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load staff",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                Color.clear
            }
        }
        .navigationTitle(staff?.displayName ?? "Staff")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showSecurity) {
            StaffSecuritySheet(
                staffId: staffId,
                staffName: staff?.displayName ?? "Staff"
            )
            .environment(authStore)
            .appLibraryNativeSheet([.large])
        }
    }

    private func content(for staff: ConvexStaffDetail) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(for: staff)
                contactActions(for: staff)
                if canManageSecurity {
                    Button {
                        showSecurity = true
                    } label: {
                        Label("Device & Access", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.bordered)
                }
                personalSection(for: staff)
                familySection(for: staff)
                employmentSection(for: staff)
                bankSection(for: staff)
                if let docs = staff.documents, !docs.isEmpty {
                    documentsSection(docs)
                }
            }
            .padding()
        }
    }

    private func header(for staff: ConvexStaffDetail) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                Text(staff.initials)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 88, height: 88)

            Text(staff.displayName)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            if !staff.headerSubtitle.isEmpty {
                Text(staff.headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            statusBadge(active: staff.isActive)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func contactActions(for staff: ConvexStaffDetail) -> some View {
        HStack(spacing: 10) {
            if let phone = staff.phone, let url = phoneURL(phone) {
                contactButton(label: "Call", systemImage: "phone.fill", color: .green) {
                    openURL(url)
                }
            }
            if let phone = staff.phone, let url = smsURL(phone) {
                contactButton(label: "SMS", systemImage: "message.fill", color: .blue) {
                    openURL(url)
                }
            }
            if let email = staff.email, let url = emailURL(email) {
                contactButton(label: "Email", systemImage: "envelope.fill", color: .orange) {
                    openURL(url)
                }
            }
        }
    }

    private func contactButton(label: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func personalSection(for staff: ConvexStaffDetail) -> some View {
        section(title: "Personal") {
            row("Phone", staff.phone, tap: staff.phone.flatMap(phoneURL))
            row("Email", staff.email, tap: staff.email.flatMap(emailURL))
            row("Gender", staff.gender)
            row("Date of Birth", staff.dateOfBirth)
            row("Blood Group", staff.bloodGroup)
            row("Marital Status", staff.maritalStatus)
            row("Nationality", staff.nationality)
            row("Religion", staff.religion)
            row("Qualification", staff.qualification)
            row("Address", staff.address)
            row("City", staff.city)
            row("State", staff.state)
            row("Pincode", staff.pincode)
        }
    }

    private func familySection(for staff: ConvexStaffDetail) -> some View {
        section(title: "Family") {
            row("Father's Name", staff.fatherName)
            row("Mother's Name", staff.motherName)
            row("Emergency Contact", staff.emergencyContact?.name)
            row("Emergency Phone", staff.emergencyContact?.phone, tap: staff.emergencyContact?.phone.flatMap(phoneURL))
            row("Relation", staff.emergencyContact?.relation)
        }
    }

    private func employmentSection(for staff: ConvexStaffDetail) -> some View {
        section(title: "Employment") {
            row("Employee ID", staff.employeeId)
            row("Designation", staff.designation)
            row("Department", staff.department)
            row("Role", staff.role)
            row("Company", staff.company)
            row("Branch", staff.branch)
            row("Joining Date", staff.joiningDate)
            row("Reporting To", staff.reportingToName)
            if let years = staff.experienceYears {
                row("Experience", "\(years) year\(years == 1 ? "" : "s")")
            }
        }
    }

    private func bankSection(for staff: ConvexStaffDetail) -> some View {
        section(title: "Bank & ID") {
            row("Bank Name", staff.bankName)
            row("Account Number", staff.accountNumber)
            row("Branch", staff.branchName)
            row("IFSC Code", staff.ifscCode)
            row("Aadhaar", staff.aadhaarNumber)
            row("PAN", staff.panNumber)
        }
    }

    private func documentsSection(_ docs: [ConvexStaffDocument]) -> some View {
        section(title: "Documents") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(docs) { doc in
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.docType ?? doc.name ?? "Document")
                                .font(.subheadline.weight(.medium))
                            if let uploaded = doc.uploadedOn {
                                Text("Uploaded \(uploaded)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?, tap: URL? = nil) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                if let tap {
                    Button {
                        openURL(tap)
                    } label: {
                        Text(value)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider().padding(.leading, 12)
        }
    }

    private func statusBadge(active: Bool) -> some View {
        Text(active ? "Active" : "Inactive")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background((active ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(active ? Color.green : Color.red)
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func smsURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)")
    }

    private func emailURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            staff = try await HRConvexAPIService.getStaffDetail(token: token, id: staffId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StaffSecuritySheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let staffId: String
    let staffName: String

    @State private var binding: HRConvexAPIService.StaffBoundDevice?
    @State private var passwordStatus: HRConvexAPIService.StaffPasswordStatus?
    @State private var isLoading = false
    @State private var isActing = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmation: StaffSecurityConfirmation?
    @State private var showPasswordSheet = false

    private var canManagePassword: Bool {
        authStore.hasPermission("staff.password")
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoading && !didLoad {
                    Section {
                        ProgressView("Loading device and access...")
                    }
                } else {
                    deviceSection
                    if canManagePassword {
                        passwordSection
                    }
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Device & Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isActing)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert(item: $confirmation) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message(staffName: staffName)),
                    primaryButton: .destructive(Text("Continue")) {
                        Task { await perform(action) }
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $showPasswordSheet) {
                SetStaffPasswordSheet(staffName: staffName) { password in
                    try await savePassword(password)
                }
                .appLibraryNativeSheet([.medium])
            }
            .interactiveDismissDisabled(isActing)
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        Section("Bound Mobile Device") {
            if binding?.bound == true {
                LabeledContent("Device", value: deviceDescription)
                if let value = binding?.deviceId?.securityNonBlank {
                    LabeledContent("Device ID", value: value)
                }
                if let value = binding?.batteryPct {
                    LabeledContent("Battery", value: "\(Int(value.rounded()))%")
                }
                if let value = binding?.ip?.securityNonBlank {
                    LabeledContent("IP Address", value: value)
                }
                if let value = formattedEpoch(binding?.boundAt) {
                    LabeledContent("Bound At", value: value)
                }
                if let value = formattedEpoch(binding?.lastSeenAt) {
                    LabeledContent("Last Seen", value: value)
                }

                Button("Reset Device Lock", systemImage: "arrow.counterclockwise") {
                    confirmation = .resetDevice
                }
                .foregroundStyle(.orange)
                .disabled(isActing)
            } else {
                Text("No device is locked to this account. The next mobile sign-in will bind the phone used.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Force Mobile Logout", systemImage: "rectangle.portrait.and.arrow.right") {
                confirmation = .forceLogout
            }
            .foregroundStyle(.red)
            .disabled(isActing)
        }
    }

    @ViewBuilder
    private var passwordSection: some View {
        Section("Password") {
            if let passwordStatus {
                LabeledContent(
                    "Status",
                    value: passwordStatus.hasPassword == true ? "Password is set" : "No password set"
                )
                if passwordStatus.mustChangePassword == true {
                    Text("Must change at next login")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let value = formattedEpoch(passwordStatus.passwordUpdatedAt) {
                    LabeledContent("Last Changed", value: value)
                }

                Button("Set a New Password", systemImage: "key") {
                    showPasswordSheet = true
                }
                .disabled(isActing)

                Button(
                    passwordStatus.passwordExpiryExempt == true
                        ? "Re-enable Password Expiry"
                        : "Exempt from Password Expiry",
                    systemImage: "calendar.badge.clock"
                ) {
                    confirmation = passwordStatus.passwordExpiryExempt == true
                        ? .enablePasswordExpiry
                        : .exemptPasswordExpiry
                }
                .disabled(isActing)
            } else if didLoad {
                Text("Password controls are unavailable for this account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceDescription: String {
        [binding?.deviceModel?.securityNonBlank, binding?.platform?.securityNonBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
            .securityNonBlank ?? "Unknown device"
    }

    @MainActor
    private func load() async {
        guard let token = authStore.currentSession?.token else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            binding = try await HRConvexAPIService.getStaffSecurity(token: token, staffId: staffId)
        } catch {
            errorMessage = error.localizedDescription
        }
        if canManagePassword {
            passwordStatus = try? await HRConvexAPIService.getStaffPasswordStatus(token: token, staffId: staffId)
        }
    }

    @MainActor
    private func perform(_ action: StaffSecurityConfirmation) async {
        guard let token = authStore.currentSession?.token else { return }
        isActing = true
        errorMessage = nil
        statusMessage = nil
        defer { isActing = false }
        do {
            switch action {
            case .resetDevice:
                _ = try await HRConvexAPIService.resetStaffDevice(token: token, staffId: staffId)
                statusMessage = "Device lock cleared."
            case .forceLogout:
                let result = try await HRConvexAPIService.forceStaffMobileLogout(token: token, staffId: staffId)
                let count = result.signedOut ?? 0
                statusMessage = count > 0 ? "Signed out of \(count) mobile session(s)." : "No active mobile session."
            case .exemptPasswordExpiry:
                try await HRConvexAPIService.setStaffPasswordExpiryExempt(token: token, staffId: staffId, exempt: true)
                statusMessage = "Exempted from password expiry."
            case .enablePasswordExpiry:
                try await HRConvexAPIService.setStaffPasswordExpiryExempt(token: token, staffId: staffId, exempt: false)
                statusMessage = "Password expiry re-enabled."
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func savePassword(_ password: String) async throws {
        guard let token = authStore.currentSession?.token else {
            throw HRConvexAPIError.unexpected("Not signed in")
        }
        try await HRConvexAPIService.setStaffPassword(
            token: token,
            staffId: staffId,
            newPassword: password
        )
        statusMessage = "Password updated. They must change it at next login."
        await load()
    }

    private func formattedEpoch(_ milliseconds: Double?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private enum StaffSecurityConfirmation: String, Identifiable {
    case resetDevice
    case forceLogout
    case exemptPasswordExpiry
    case enablePasswordExpiry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resetDevice: return "Reset Device Lock?"
        case .forceLogout: return "Force Mobile Logout?"
        case .exemptPasswordExpiry: return "Exempt from Expiry?"
        case .enablePasswordExpiry: return "Re-enable Expiry?"
        }
    }

    func message(staffName: String) -> String {
        switch self {
        case .resetDevice:
            return "Clears the lock so \(staffName)'s next mobile sign-in binds a new phone and signs the current phone out."
        case .forceLogout:
            return "Signs \(staffName) out of every mobile session while keeping the current device lock."
        case .exemptPasswordExpiry:
            return "This staff member will stop being asked to change their password on the normal schedule."
        case .enablePasswordExpiry:
            return "This staff member will be asked to change their password again on the normal schedule."
        }
    }
}

private struct SetStaffPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    let staffName: String
    let onSave: (String) async throws -> Void

    @State private var password = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Use at least 8 characters with upper and lower case letters, a number, and a symbol.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Set Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || password.isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSave(password)
            password = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var securityNonBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#Preview {
    NavigationStack {
        StaffDetailView(staffId: "preview")
    }
}
