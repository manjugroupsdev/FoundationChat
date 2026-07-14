import AVFoundation
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
    }

    private var scannerHeader: some View {
        VStack(spacing: 0) {
            HStack {
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

                Spacer()

                Text("Front Desk Scanner")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 2)

                Spacer()

                if scannedValue == nil {
                    Color.clear
                        .frame(width: 50, height: 50)
                } else {
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
            Capsule()
                .fill(Color(hex: 0xD0D5DD))
                .frame(width: 46, height: 5)
                .frame(maxWidth: .infinity)

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

                    Text(inviteToken(from: value) ?? value)
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

    private func inviteToken(from value: String) -> String? {
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
