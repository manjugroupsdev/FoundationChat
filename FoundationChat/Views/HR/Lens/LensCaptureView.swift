import AVFoundation
import SwiftUI
import UIKit

/// Drives LensFaceEngine and mirrors its state for SwiftUI.
@Observable
final class LensCaptureModel {
    var snapshot = LensEngineSnapshot()
    var camera: LensFaceEngine.CameraState = .starting
    var flashTick = 0
    var targetSince = Date()
    @ObservationIgnored private(set) var engine: LensFaceEngine! = nil
    @ObservationIgnored private var lastTarget: LensPose?

    init() {
        engine = LensFaceEngine(
            onSnapshot: { [weak self] snapshot in self?.apply(snapshot) },
            onCamera: { [weak self] state in self?.camera = state }
        )
    }

    private func apply(_ new: LensEngineSnapshot) {
        if let pose = new.justCaptured, snapshot.captured[pose] == nil {
            flashTick += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if new.target != lastTarget {
            lastTarget = new.target
            targetSince = Date()
        }
        snapshot = new
    }
}

struct LensCaptureView: View {
    let staffName: String
    let targets: [LensPose]
    let onDone: ([LensPose: LensShot]) -> Void
    let onCancel: () -> Void

    @State private var model = LensCaptureModel()
    @State private var flashOpacity = 0.0
    @State private var arrowPhase = false

    private var requiredDone: Bool {
        targets.filter(\.isRequired).allSatisfy { model.snapshot.captured[$0] != nil }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.camera {
            case .denied:
                cameraMessage(
                    icon: "camera.fill",
                    title: "Camera access is off",
                    detail: "Allow camera access in Settings to record the face photos.",
                    showSettings: true
                )
            case .unavailable:
                cameraMessage(icon: "video.slash", title: "Front camera unavailable", detail: "Try again or use another phone.", showSettings: false)
            case .starting, .running:
                GeometryReader { geo in
                    let oval = ovalRect(in: geo.size)
                    ZStack {
                        LensCameraPreview(session: model.engine.session)
                            .ignoresSafeArea()
                        dimmer(oval: oval, size: geo.size)
                        LensPoseRing(snapshot: model.snapshot, targets: targets, oval: oval)
                        turnArrow(oval: oval)
                        Color.white.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
                    }
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .statusBarHidden()
        .onAppear {
            model.engine.reset(targets: targets)
            model.engine.start()
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { arrowPhase = true }
        }
        .onDisappear { model.engine.stop() }
        .onChange(of: model.flashTick) {
            flashOpacity = 0.75
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
        }
        .onChange(of: model.snapshot.isFinished) { _, finished in
            if finished { onDone(model.snapshot.captured) }
        }
        .task(id: model.snapshot.target) {
            // Optional poses skip themselves if they don't come.
            guard let target = model.snapshot.target, !target.isRequired else { return }
            try? await Task.sleep(for: .seconds(12))
            if model.snapshot.target == target { model.engine.skip(target) }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.6), in: Circle())
            }
            .accessibilityLabel("Cancel")
            VStack(alignment: .leading, spacing: 2) {
                Text(staffName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(model.snapshot.captured.count) of \(targets.count) photos")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if let hint = model.snapshot.hint {
                Label(hint.text, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1F2937))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0xFDE68A), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Text(instruction)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .animation(.easeOut(duration: 0.2), value: instruction)

            HStack(spacing: 8) {
                ForEach(targets) { pose in
                    poseChip(pose)
                }
            }

            HStack(spacing: 10) {
                if let target = model.snapshot.target, !target.isRequired, requiredDone {
                    Button("Skip \(target.title.lowercased())") { model.engine.skip(target) }
                        .buttonStyle(.mconnect(.secondary, compact: true))
                        .environment(\.colorScheme, .dark)
                }
                if requiredDone && !model.snapshot.isFinished && targets.count > 1 {
                    Button("Use these photos") { model.engine.finishNow() }
                        .buttonStyle(.mconnect(.primary, compact: true))
                }
            }
            .frame(minHeight: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .animation(.easeOut(duration: 0.2), value: model.snapshot.hint)
    }

    private func poseChip(_ pose: LensPose) -> some View {
        let done = model.snapshot.captured[pose] != nil
        let skipped = model.snapshot.skipped.contains(pose)
        let current = model.snapshot.target == pose
        return VStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : (skipped ? "minus.circle" : icon(for: pose)))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(done ? Color(hex: 0x22C55E) : (current ? .white : .white.opacity(0.45)))
            Text(pose.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(current ? .white : .white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(current ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
    }

    private func icon(for pose: LensPose) -> String {
        switch pose.side {
        case 0: return "face.dashed"
        case -1: return pose.idealYaw > 20 ? "chevron.left.2" : "chevron.left"
        default: return pose.idealYaw > 20 ? "chevron.right.2" : "chevron.right"
        }
    }

    private var instruction: String {
        if model.snapshot.isFinished { return "All set" }
        guard let target = model.snapshot.target else { return "Look at the camera" }
        if model.snapshot.holdPose == target { return "Hold still…" }
        switch target {
        case .straight: return "Look straight at the camera"
        case .slightLeft: return "Slowly turn your head a little to your left"
        case .moreLeft: return "Turn a bit more to your left"
        case .slightRight: return "Now slowly turn a little to your right"
        case .moreRight: return "Turn a bit more to your right"
        }
    }

    @ViewBuilder
    private func turnArrow(oval: CGRect) -> some View {
        if let target = model.snapshot.target, target.side != 0, model.snapshot.holdPose != target {
            // Preview is mirrored, so the subject's left is the screen's left.
            let left = target.side < 0
            Image(systemName: left ? "chevron.left.2" : "chevron.right.2")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .position(
                    x: left ? oval.minX - 26 + (arrowPhase ? -10 : 6) : oval.maxX + 26 + (arrowPhase ? 10 : -6),
                    y: oval.midY
                )
                .allowsHitTesting(false)
        }
    }

    private func dimmer(oval: CGRect, size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addEllipse(in: oval)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func ovalRect(in size: CGSize) -> CGRect {
        let width = min(size.width * 0.68, 300)
        let height = width * 1.32
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.43 - height / 2, width: width, height: height)
    }

    private func cameraMessage(icon: String, title: String, detail: String, showSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            if showSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.mconnect(.primary))
                .padding(.top, 6)
            }
        }
        .padding(32)
    }
}

/// Oval guide: five arcs (top = straight, sides = turns) that fill as each
/// pose is captured; the target arc pulses and fills with the hold progress.
private struct LensPoseRing: View {
    let snapshot: LensEngineSnapshot
    let targets: [LensPose]
    let oval: CGRect
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(LensPose.guidedOrder) { pose in
                let range = arc(pose)
                let done = snapshot.captured[pose] != nil
                let skipped = snapshot.skipped.contains(pose)
                let isTarget = snapshot.target == pose
                let inPlay = targets.contains(pose)
                EllipseArc(start: range.0, end: range.1)
                    .stroke(Color.white.opacity(inPlay ? 0.28 : 0.1), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                if done {
                    EllipseArc(start: range.0, end: range.1)
                        .stroke(Color(hex: 0x22C55E), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .transition(.opacity)
                } else if skipped {
                    EllipseArc(start: range.0, end: range.1)
                        .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [4, 6]))
                } else if isTarget {
                    EllipseArc(start: range.0, end: range.1)
                        .stroke(Color(hex: 0x3B82F6).opacity(pulse ? 0.95 : 0.5), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    if snapshot.holdPose == pose {
                        EllipseArc(start: range.0, end: range.0 + (range.1 - range.0) * snapshot.holdProgress)
                            .stroke(Color(hex: 0x22C55E), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    }
                }
            }
        }
        .frame(width: oval.width + 24, height: oval.height + 24)
        .position(x: oval.midX, y: oval.midY)
        .animation(.easeOut(duration: 0.25), value: snapshot.captured.count)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .allowsHitTesting(false)
    }

    /// Degrees clockwise from the top. Screen left = subject's left (mirrored preview).
    private func arc(_ pose: LensPose) -> (Double, Double) {
        switch pose {
        case .straight: return (-20, 20)
        case .slightRight: return (28, 64)
        case .moreRight: return (72, 108)
        case .slightLeft: return (-64, -28)
        case .moreLeft: return (-108, -72)
        }
    }
}

private struct EllipseArc: Shape {
    var start: Double
    var end: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 48
        guard end > start else { return path }
        for i in 0...steps {
            let degrees = start + (end - start) * Double(i) / Double(steps)
            let theta = degrees * .pi / 180
            let point = CGPoint(
                x: rect.midX + rect.width / 2 * CGFloat(sin(theta)),
                y: rect.midY - rect.height / 2 * CGFloat(cos(theta))
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Live front-camera preview (mirrored like a selfie).
private struct LensCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
