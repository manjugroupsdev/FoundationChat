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
    /** Back camera by default (an admin photographs the staff member). */
    var usingFront = false
    @ObservationIgnored private(set) var engine: LensFaceEngine! = nil
    @ObservationIgnored private var lastTarget: LensPose?

    init() {
        engine = LensFaceEngine(
            onSnapshot: { [weak self] snapshot in self?.apply(snapshot) },
            onCamera: { [weak self] state in self?.camera = state }
        )
    }

    func switchCamera() {
        usingFront.toggle()
        engine.switchCamera(toFront: usingFront)
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
                        LensPoseRing(snapshot: model.snapshot, targets: targets, oval: oval, mirrored: model.usingFront)
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
            Button { model.switchCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.6), in: Circle())
            }
            .accessibilityLabel("Switch camera")
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
            // Front preview is mirrored (subject's left = screen left); the back
            // camera's isn't (subject's left = screen right).
            let left = model.usingFront ? target.side < 0 : target.side > 0
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
    /// Front camera (mirrored preview). The back camera's sides swap.
    var mirrored: Bool = true
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
                    // Progress bar for the asked-for pose: fills as the head turns
                    // toward it (0..0.75), then through the still hold (0.75..1).
                    let p = progress(for: pose)
                    let span = filledRange(range, p)
                    EllipseArc(start: span.0, end: span.1)
                        .stroke(p >= 0.75 ? Color(hex: 0x22C55E) : Color(hex: 0x3B82F6),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .animation(.easeOut(duration: 0.15), value: p)
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

    /// 0..1 progress toward `pose` from the live yaw (signed: negative = subject's left).
    private func progress(for pose: LensPose) -> Double {
        if snapshot.holdPose == pose { return 0.75 + 0.25 * snapshot.holdProgress }
        guard snapshot.faceFound else { return 0 }
        let yaw = snapshot.yaw
        let turn: Double
        if pose.side == 0 {
            let a = abs(yaw)
            turn = a <= 5 ? 1 : max(0, 1 - (a - 5) / 20)
        } else {
            let toward = pose.side < 0 ? -yaw : yaw
            let lo: Double = pose.idealYaw > 20 ? 26 : 11
            let hi: Double = pose.idealYaw > 20 ? 40 : 19
            if toward <= 0 { turn = 0 }
            else if toward < lo { turn = toward / lo }
            else if toward <= hi { turn = 1 }
            else { turn = max(0.4, 1 - (toward - hi) / 12) }
        }
        return 0.75 * turn
    }

    /// The filled part of an arc: from the end nearest the top outward (sides),
    /// or out from the middle (straight).
    private func filledRange(_ r: (Double, Double), _ p: Double) -> (Double, Double) {
        let p = min(max(p, 0), 1)
        if r.0 < 0 && r.1 > 0 {
            let mid = (r.0 + r.1) / 2, half = (r.1 - r.0) / 2 * p
            return (mid - half, mid + half)
        }
        let near = abs(r.0) < abs(r.1) ? r.0 : r.1
        let far = near == r.0 ? r.1 : r.0
        let end = near + (far - near) * p
        return (min(near, end), max(near, end))
    }

    /// Degrees clockwise from the top. Screen left = subject's left on a mirrored
    /// (front) preview; the back camera's preview flips the sides.
    private func arc(_ pose: LensPose) -> (Double, Double) {
        let base = mirroredArc(pose)
        return mirrored ? base : (-base.1, -base.0)
    }

    private func mirroredArc(_ pose: LensPose) -> (Double, Double) {
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

/// Live camera preview (the layer mirrors the front camera like a selfie).
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
