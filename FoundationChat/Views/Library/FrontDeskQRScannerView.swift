import AVFoundation
import Foundation
import SwiftUI

struct FrontDeskQRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var cameraAccessDenied = false
    @State private var scanLineAnimating = false
    let showsCloseButton: Bool

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            QRScannerCameraView(scannedValue: $scannedValue, cameraAccessDenied: $cameraAccessDenied)
                .ignoresSafeArea()

            scannerOverlay
            scannerHeader

            if cameraAccessDenied {
                cameraDeniedCard
            }

            if let scannedValue {
                scannedResultCard(value: scannedValue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: scannedValue)
        .onChange(of: scannedValue) { _, value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            FrontDeskQRHistoryStore.add(value)
        }
    }

    private var scannerHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: showsCloseButton ? "xmark" : "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .accessibilityLabel(showsCloseButton ? "Close scanner" : "Back")
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Front Desk Scanner")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 2)

                HStack(spacing: 10) {
                    NavigationLink {
                        FrontDeskQRHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.black.opacity(0.28), in: Circle())
                    }
                    .accessibilityLabel("Open scan history")

                    if scannedValue != nil {
                        Button {
                            scannedValue = nil
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .accessibilityLabel("Scan another QR code")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 58)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }

    private var scannerOverlay: some View {
        GeometryReader { proxy in
            let boxSize = min(proxy.size.width * 0.72, 292)
            let centerYOffset = proxy.size.height * 0.07

            VStack(spacing: 22) {
                ScannerTargetView(
                    size: boxSize,
                    isAnimating: scanLineAnimating && scannedValue == nil
                )

                Text("Align QR code inside the box to scan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: centerYOffset)
            .padding(.horizontal, 24)
            .background(
                Rectangle()
                    .fill(.black.opacity(scannedValue == nil ? 0.22 : 0.44))
                    .ignoresSafeArea()
            )
            .onAppear {
                scanLineAnimating = false
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: true)) {
                        scanLineAnimating = true
                    }
                }
            }
        }
    }

    private var cameraDeniedCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B61CA))

            Text("Camera permission needed")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x111827))

            Text("Enable camera access in Settings to scan Front Desk QR codes.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x667085))
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func scannedResultCard(value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xEAF4FF), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("QR Scanned")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x111827))

                    Text(Self.inviteToken(from: value) ?? value)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(3)
                }
            }

            Button {
                scannedValue = nil
            } label: {
                Text("Scan Another")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: 0x0B61CA), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(.clear)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(height: 214)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    fileprivate static func inviteToken(from value: String) -> String? {
        let marker = "/frontdesk/invite/"
        guard let range = value.range(of: marker) else { return nil }
        return String(value[range.upperBound...])
            .split(separator: "?")
            .first?
            .split(separator: "#")
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
}

private struct ScannerTargetView: View {
    let size: CGFloat
    let isAnimating: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.94), lineWidth: 3.5)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.08))
                .frame(width: size - 6, height: size - 6)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(hex: 0x22C55E), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size - 48, height: 3)
                .shadow(color: Color(hex: 0x22C55E).opacity(0.95), radius: 10)
                .offset(y: isAnimating ? (size / 2 - 30) : -(size / 2 - 30))
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }
}

private struct FrontDeskQRHistoryView: View {
    @State private var items = FrontDeskQRHistoryStore.load()
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack {
            Color(hex: 0xF1F3F8).ignoresSafeArea()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Scan History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Your scanned QR codes and visitor logs will show up here.")
                )
                .foregroundStyle(Color(hex: 0x667085))
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink {
                                FrontDeskQRHistoryDetailView(item: item)
                            } label: {
                                FrontDeskQRHistoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(Color(hex: 0xF04438))
                }
            }
        }
        .alert("Clear Scan History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                FrontDeskQRHistoryStore.clear()
                items = []
            }
        } message: {
            Text("Are you sure you want to delete all scans?")
        }
        .onAppear {
            items = FrontDeskQRHistoryStore.load()
        }
        .preferredColorScheme(.light)
    }
}

private struct FrontDeskQRHistoryRow: View {
    let item: FrontDeskQRHistoryItem

    private var payload: FrontDeskQRHistoryPayload {
        item.payload
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(payload.initials)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: 0x0B61CA))
                .frame(width: 48, height: 48)
                .background(Color(hex: 0xEAF4FF), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(payload.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x101828))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let status = payload.statusLabel {
                        Text(status.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(status.foreground)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(status.background, in: Capsule())
                    }
                }

                if let details = payload.details {
                    Text(details)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0x667085))
                        .lineLimit(1)
                }

                if let host = payload.hostLine {
                    Text(host)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x98A2B3))
                        .lineLimit(1)
                }

                Text(item.timestamp)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0B61CA))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: 0x98A2B3))
                .padding(.top, 17)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xEAECF0), lineWidth: 1)
        }
    }
}

private struct FrontDeskQRHistoryDetailView: View {
    let item: FrontDeskQRHistoryItem

    private var payload: FrontDeskQRHistoryPayload {
        item.payload
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text(payload.initials)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 68, height: 68)
                        .background(Color(hex: 0xEAF4FF), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(payload.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))

                        if let details = payload.details {
                            Text(details)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: 0x667085))
                        }
                    }
                }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                detailCard(title: "Contact", rows: payload.contactRows)
                detailCard(title: "Visit", rows: payload.visitRows)

                if !payload.secondaryVisitors.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Secondary Visitors")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: 0x101828))

                        ForEach(payload.secondaryVisitors, id: \.self) { visitor in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(visitor.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x101828))
                                Text([visitor.phone, visitor.email, visitor.age].compactMap { $0 }.joined(separator: " • "))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(hex: 0x667085))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(hex: 0xF8FAFC), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0xF1F3F8).ignoresSafeArea())
        .navigationTitle("Visitor Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func detailCard(title: String, rows: [FrontDeskQRDetailRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: 0x101828))

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x0B61CA))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0xEAF4FF), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x98A2B3))
                        Text(row.value)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x344054))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private enum FrontDeskQRHistoryStore {
    private static let key = "frontdesk.qr.history.items"

    static func load() -> [FrontDeskQRHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([FrontDeskQRHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    static func add(_ value: String) {
        var items = load()
        let item = FrontDeskQRHistoryItem(value: value, timestamp: displayFormatter.string(from: Date()))
        items.insert(item, at: 0)
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        save(items)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ items: [FrontDeskQRHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy hh:mm a"
        return formatter
    }()
}

private struct FrontDeskQRHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let value: String
    let timestamp: String

    init(id: UUID = UUID(), value: String, timestamp: String) {
        self.id = id
        self.value = value
        self.timestamp = timestamp
    }

    var payload: FrontDeskQRHistoryPayload {
        FrontDeskQRHistoryPayload(value: value)
    }
}

private struct FrontDeskQRHistoryPayload {
    let value: String
    private let json: [String: Any]

    init(value: String) {
        self.value = value
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["isStructured"] as? Bool == true {
            json = object
        } else {
            json = [:]
        }
    }

    var isStructured: Bool {
        !json.isEmpty
    }

    var title: String {
        string("primaryName") ?? string("visitorName") ?? FrontDeskQRScannerView.inviteToken(from: value) ?? value
    }

    var details: String? {
        if isStructured {
            let company = string("primaryCompany")
            let type = string("visitorType")
            let purpose = string("purpose")
            let typePurpose = [type, purpose.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            return [company, typePurpose.nilIfBlank].compactMap { $0 }.joined(separator: " • ").nilIfBlank
        }
        return FrontDeskQRScannerView.inviteToken(from: value).map { "Invite token: \($0)" }
    }

    var hostLine: String? {
        guard let host = string("hostPerson") else { return nil }
        return "Host: \(host)"
    }

    var initials: String {
        let words = title
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let text = String(words).uppercased()
        return text.isEmpty ? "#" : text
    }

    var statusLabel: FrontDeskQRStatusLabel? {
        switch string("status") {
        case "checked_out":
            return FrontDeskQRStatusLabel(title: "Checked Out", foreground: Color(hex: 0x475467), background: Color(hex: 0xF2F4F7))
        case "checked_in":
            return FrontDeskQRStatusLabel(title: "Checked In", foreground: Color(hex: 0x15803D), background: Color(hex: 0xDCFCE7))
        default:
            return nil
        }
    }

    var contactRows: [FrontDeskQRDetailRow] {
        [
            detail("Phone", value: string("primaryPhone"), icon: "phone.fill"),
            detail("Email", value: string("primaryEmail"), icon: "envelope.fill"),
            detail("Age", value: string("primaryAge").map { "Age: \($0)" }, icon: "calendar")
        ].compactMap { $0 }
    }

    var visitRows: [FrontDeskQRDetailRow] {
        [
            detail("Category", value: [string("visitorType"), string("purpose")].compactMap { $0 }.joined(separator: " • ").nilIfBlank, icon: "tag.fill"),
            detail("Host", value: string("hostPerson"), icon: "person.fill"),
            detail("Expected Time", value: string("expectedTime"), icon: "clock.fill"),
            detail("Pass Number", value: string("passNumber"), icon: "number"),
            detail("Notes", value: string("meetingNotes"), icon: "doc.text.fill")
        ].compactMap { $0 }
    }

    var secondaryVisitors: [FrontDeskQRSecondaryVisitor] {
        guard let array = json["secondaryList"] as? [[String: Any]] else { return [] }
        return array.compactMap { object in
            let name = (object["name"] as? String)?.nilIfBlank
            guard let name else { return nil }
            return FrontDeskQRSecondaryVisitor(
                name: name,
                phone: (object["phone"] as? String)?.nilIfBlank,
                email: (object["email"] as? String)?.nilIfBlank,
                age: (object["age"] as? String)?.nilIfBlank.map { "Age: \($0)" }
            )
        }
    }

    private func string(_ key: String) -> String? {
        (json[key] as? String)?.nilIfBlank
    }

    private func detail(_ label: String, value: String?, icon: String) -> FrontDeskQRDetailRow? {
        guard let value else { return nil }
        return FrontDeskQRDetailRow(label: label, value: value, icon: icon)
    }
}

private struct FrontDeskQRStatusLabel {
    let title: String
    let foreground: Color
    let background: Color
}

private struct FrontDeskQRDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

private struct FrontDeskQRSecondaryVisitor: Hashable {
    let name: String
    let phone: String?
    let email: String?
    let age: String?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct QRScannerCameraView: UIViewControllerRepresentable {
    @Binding var scannedValue: String?
    @Binding var cameraAccessDenied: Bool

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = { value in
            scannedValue = value
        }
        controller.onDenied = {
            cameraAccessDenied = true
        }
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {
        controller.isPaused = scannedValue != nil
    }
}

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onDenied: (() -> Void)?
    var isPaused = false {
        didSet {
            if isPaused {
                session.stopRunning()
            } else if isViewLoaded, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.startRunning()
                }
            }
        }
    }

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.startSession() : self?.onDenied?()
                }
            }
        default:
            onDenied?()
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onDenied?()
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isPaused,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        isPaused = true
        onScan?(value)
    }
}

#Preview {
    FrontDeskQRScannerView()
}
