import SwiftUI

struct StaffDetailView: View {
    let staffId: String

    @Environment(AuthStore.self) private var authStore
    @Environment(\.openURL) private var openURL

    @State private var staff: ConvexStaffDetail?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

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
    }

    private func content(for staff: ConvexStaffDetail) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header(for: staff)
                contactActions(for: staff)
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

#Preview {
    NavigationStack {
        StaffDetailView(staffId: "preview")
    }
}
