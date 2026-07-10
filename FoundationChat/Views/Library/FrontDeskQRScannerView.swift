import AVFoundation
import SwiftUI

struct FrontDeskQRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var cameraAccessDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            QRScannerCameraView(scannedValue: $scannedValue, cameraAccessDenied: $cameraAccessDenied)
                .ignoresSafeArea()

            scannerOverlay

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
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: scannedValue)
    }

    private var scannerOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.38), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Front Desk Scanner")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    scannedValue = nil
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.38), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(scannedValue == nil ? 0 : 1)
                .disabled(scannedValue == nil)
            }
            .padding(.horizontal, 18)
            .padding(.top, 52)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 3)
                    .frame(width: 250, height: 250)

                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(hex: 0x16A34A), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 214, height: 3)
                        .shadow(color: Color(hex: 0x16A34A).opacity(0.7), radius: 8)
                        .padding(.top, 18)

                    Spacer()
                }
                .frame(width: 250, height: 250)
            }

            Text("Align QR code inside the box to scan")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.84))
                .padding(.top, 24)

            Spacer()
        }
        .background(
            Rectangle()
                .fill(.black.opacity(scannedValue == nil ? 0.18 : 0.42))
                .ignoresSafeArea()
        )
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
