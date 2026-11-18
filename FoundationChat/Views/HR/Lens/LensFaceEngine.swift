import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers
import Vision

// On-device face capture for Lens enrollment.
//
// Front camera frames (portrait, NOT mirrored) go through Vision: face
// rectangles (rev 3: continuous yaw / pitch / roll), landmarks (eyes, lips,
// nose, pupils) and face-capture quality. A frame only counts when exactly one
// face is level, eyes open, mouth closed, big enough, evenly lit, sharp and
// STILL (motion detector over the last ~300 ms). For each pose bucket the best
// still frame is kept; a bucket is done after a short steady hold.
//
// Side comes from geometry, not the sign of Vision's yaw: in an unmirrored
// image a head turned to the subject's left puts the nose right of the eye
// midpoint. Magnitude comes from Vision's yaw.

nonisolated enum LensPose: String, CaseIterable, Identifiable, Sendable {
    case straight
    case slightLeft = "slight_left"
    case moreLeft = "more_left"
    case slightRight = "slight_right"
    case moreRight = "more_right"

    var id: String { rawValue }

    /// The guided turn: centre, left, back to centre, right.
    static let guidedOrder: [LensPose] = [.straight, .slightLeft, .moreLeft, .slightRight, .moreRight]

    var title: String {
        switch self {
        case .straight: return "Straight"
        case .slightLeft: return "Slight left"
        case .moreLeft: return "More left"
        case .slightRight: return "Slight right"
        case .moreRight: return "More right"
        }
    }

    var isRequired: Bool { self == .straight || self == .slightLeft || self == .slightRight }

    /// -1 subject's left, +1 subject's right, 0 straight.
    var side: Int {
        switch self {
        case .straight: return 0
        case .slightLeft, .moreLeft: return -1
        case .slightRight, .moreRight: return 1
        }
    }

    /// Ideal head turn in degrees for scoring.
    var idealYaw: Double {
        switch self {
        case .straight: return 0
        case .slightLeft, .slightRight: return 15
        case .moreLeft, .moreRight: return 38
        }
    }

    static func bucket(yaw: Double, side: Int) -> LensPose? {
        if yaw <= 5 { return .straight }
        guard side != 0 else { return nil }
        // Capture windows sit inside the doc's ranges with gaps between them, so
        // a head held near a boundary (e.g. 20 degrees) can't fill two poses.
        if yaw >= 11 && yaw <= 19 { return side < 0 ? .slightLeft : .slightRight }
        // "More" = a real side turn (slight and more looked the same at 22..30).
        if yaw >= 32 && yaw <= 45 { return side < 0 ? .moreLeft : .moreRight }
        return nil
    }
}

nonisolated enum LensHint: Equatable, Sendable {
    case noFace, multipleFaces, moveCloser, moveBack, centerFace, keepLevel, openEyes, closeMouth
    case tooDark, tooBright, backlight, faceCovered, holdStill, turnLess, turnMore, blurry, turnOtherWay

    var text: String {
        switch self {
        case .noFace: return "Bring your face into the oval"
        case .multipleFaces: return "Only one person in the frame"
        case .moveCloser: return "Move closer"
        case .moveBack: return "Move back a little"
        case .centerFace: return "Centre your face in the oval"
        case .keepLevel: return "Keep your head level"
        case .openEyes: return "Open your eyes"
        case .closeMouth: return "Close your mouth, neutral face"
        case .tooDark: return "Too dark — find more light"
        case .tooBright: return "Too bright — avoid direct light"
        case .backlight: return "Light is behind you — face the light"
        case .faceCovered: return "Remove mask or sunglasses"
        case .holdStill: return "Hold still"
        case .turnLess: return "Turn a little less"
        case .turnMore: return "Turn a little more"
        case .blurry: return "Hold the phone steady"
        case .turnOtherWay: return "Turn the other way"
        }
    }
}

nonisolated struct LensShot: Sendable, Equatable {
    let pose: LensPose
    let jpeg: Data
    let quality: Double      // 0...1 combined score
    let faceWidthPx: Int
}

nonisolated struct LensEngineSnapshot: Sendable {
    var target: LensPose?
    var hint: LensHint?
    var faceFound = false
    var yaw: Double = 0          // signed: negative = subject's left
    var holdPose: LensPose?
    var holdProgress: Double = 0
    var captured: [LensPose: LensShot] = [:]
    var skipped: Set<LensPose> = []
    var justCaptured: LensPose?
    var isFinished = false
}

nonisolated final class LensFaceEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum CameraState: Sendable { case starting, running, denied, unavailable }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.manju.lens.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.manju.lens.video", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Tunables (contract capture rules).
    // Stillness is time-based (two samples spanning the window), so a slow
    // Vision loop still reaches "still"; limits sit above detector jitter.
    private let stableWindow: Double = 0.40
    private let holdDuration: Double = 0.50
    private let maxAngleDrift: Double = 6.0
    private let maxCentreDrift: Double = 0.05
    private let minFaceWidthPx: Double = 120
    private let goodFaceWidthPx: Double = 200
    private let maxPitch: Double = 15
    private let maxRoll: Double = 12
    private let minEyeOpenRatio: Double = 0.14
    private let maxMouthOpenRatio: Double = 0.16
    private let minQuality: Double = 0.18
    private let minSharpness: Double = 12

    // State below is touched on videoQueue only.
    private var targets: [LensPose] = LensPose.guidedOrder
    private var captured: [LensPose: LensShot] = [:]
    /// Signed yaw each captured pose was taken at (separation check).
    private var capturedYaw: [LensPose: Double] = [:]
    private var skipped: Set<LensPose> = []
    private var history: [(t: Double, yaw: Double, pitch: Double, roll: Double, cx: Double, cy: Double)] = []
    private var holdPose: LensPose?
    private var holdStart: Double = 0
    private var holdBest: (score: Double, image: CGImage, widthPx: Int)?
    private var lastPublish: Double = 0
    private var finished = false

    private let onSnapshot: @MainActor @Sendable (LensEngineSnapshot) -> Void
    private let onCamera: @MainActor @Sendable (CameraState) -> Void

    init(
        onSnapshot: @escaping @MainActor @Sendable (LensEngineSnapshot) -> Void,
        onCamera: @escaping @MainActor @Sendable (CameraState) -> Void
    ) {
        self.onSnapshot = onSnapshot
        self.onCamera = onCamera
        super.init()
    }

    // MARK: Control

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndRun() }
                } else {
                    self.report(.denied)
                }
            }
        default:
            report(.denied)
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Capture these poses (all five for a new recording, one for a retake).
    func reset(targets: [LensPose]) {
        videoQueue.async {
            self.targets = LensPose.guidedOrder.filter { targets.contains($0) }
            self.captured = [:]
            self.capturedYaw = [:]
            self.skipped = []
            self.history = []
            self.holdPose = nil
            self.holdBest = nil
            self.finished = false
            self.publish(now: CACurrentMediaTime(), force: true)
        }
    }

    func skip(_ pose: LensPose) {
        videoQueue.async {
            guard !pose.isRequired, self.captured[pose] == nil else { return }
            self.skipped.insert(pose)
            if self.holdPose == pose { self.holdPose = nil; self.holdBest = nil }
            self.checkFinished()
            self.publish(now: CACurrentMediaTime(), force: true)
        }
    }

    /// Stop early once the required poses are in.
    func finishNow() {
        videoQueue.async {
            guard LensPose.guidedOrder.filter({ $0.isRequired && self.targets.contains($0) })
                .allSatisfy({ self.captured[$0] != nil }) else { return }
            for pose in self.targets where self.captured[pose] == nil { self.skipped.insert(pose) }
            self.finished = true
            self.publish(now: CACurrentMediaTime(), force: true)
        }
    }

    private func report(_ state: CameraState) {
        let handler = onCamera
        Task { @MainActor in handler(state) }
    }

    /// Back camera by default: an admin photographs the staff member. Touched on sessionQueue.
    private var position: AVCaptureDevice.Position = .back

    private func cameraDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position == .back ? .front : .back)
    }

    private func applyConnectionSettings() {
        for output in session.outputs {
            guard let connection = output.connection(with: .video) else { continue }
            // Upright portrait pixels, not mirrored: what Lens receives.
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    /// Flip between the back and front camera; stillness history restarts.
    func switchCamera(toFront front: Bool) {
        sessionQueue.async {
            self.position = front ? .front : .back
            guard !self.session.inputs.isEmpty, let device = self.cameraDevice(),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for old in self.session.inputs { self.session.removeInput(old) }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            self.applyConnectionSettings()
            self.session.commitConfiguration()
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            }
            self.videoQueue.async {
                self.history = []
                self.holdPose = nil
                self.holdBest = nil
            }
        }
    }

    private func configureAndRun() {
        if session.inputs.isEmpty {
            guard let device = cameraDevice(),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                report(.unavailable)
                return
            }
            session.beginConfiguration()
            session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                report(.unavailable)
                return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
            applyConnectionSettings()
            session.commitConfiguration()
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            }
        }
        if !session.isRunning { session.startRunning() }
        report(.running)
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        let analysis = analyze(pixelBuffer)
        process(analysis, pixelBuffer: pixelBuffer, now: now)
    }

    private struct Analysis {
        var faceCount = 0
        var yaw: Double = 0          // magnitude, degrees
        var side = 0
        var pitch: Double = 0
        var roll: Double = 0
        var cx: Double = 0.5
        var cy: Double = 0.5
        var widthNorm: Double = 0
        var widthPx: Double = 0
        var rectTopLeft = CGRect.zero // normalized, top-left origin
        var eyesOpen = true
        var mouthClosed = true
        var landmarksOK = false
        var quality: Double = 0
        var sharpness: Double = 0
        var faceLuma: Double = 128
        var frameLuma: Double = 128
    }

    private func analyze(_ pixelBuffer: CVPixelBuffer) -> Analysis {
        var result = Analysis()
        let width = Double(CVPixelBufferGetWidth(pixelBuffer))
        let height = Double(CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        guard (try? handler.perform([rectangles])) != nil,
              let faces = rectangles.results, !faces.isEmpty else { return result }
        result.faceCount = faces.count
        // Ignore tiny background faces when counting people.
        let meaningful = faces.filter { $0.boundingBox.width > 0.12 }
        result.faceCount = max(1, meaningful.count)
        guard let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else { return result }

        let box = face.boundingBox
        result.widthNorm = Double(box.width)
        result.widthPx = Double(box.width) * width
        result.rectTopLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        result.cx = Double(box.midX)
        result.cy = Double(1 - box.midY)
        let yawDeg = (face.yaw?.doubleValue ?? 0) * 180 / .pi
        result.pitch = abs((face.pitch?.doubleValue ?? 0) * 180 / .pi)
        result.roll = abs((face.roll?.doubleValue ?? 0) * 180 / .pi)

        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarks.inputFaceObservations = [face]
        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = [face]
        try? handler.perform([landmarks, quality])
        result.quality = Double(quality.results?.first?.faceCaptureQuality ?? 0)

        let size = CGSize(width: width, height: height)
        if let marks = landmarks.results?.first?.landmarks,
           let leftEye = marks.leftEye?.pointsInImage(imageSize: size),
           let rightEye = marks.rightEye?.pointsInImage(imageSize: size),
           let nose = (marks.nose ?? marks.noseCrest)?.pointsInImage(imageSize: size),
           !leftEye.isEmpty, !rightEye.isEmpty, !nose.isEmpty {
            result.landmarksOK = true
            let eyeA = centroid(leftEye), eyeB = centroid(rightEye)
            let eyeMidX = (eyeA.x + eyeB.x) / 2
            let interocular = max(1, hypot(eyeA.x - eyeB.x, eyeA.y - eyeB.y))
            let noseX = centroid(nose).x
            let offset = Double((noseX - eyeMidX) / interocular)
            // Unmirrored image: nose right of the eyes = turned to subject's left.
            result.side = abs(offset) < 0.03 ? 0 : (offset > 0 ? -1 : 1)
            // Vision's yaw for magnitude; geometry estimate when it's missing.
            let geometric = min(45, asin(min(1, abs(offset) * 1.7)) * 180 / .pi)
            result.yaw = face.yaw == nil ? geometric : abs(yawDeg)
            if result.yaw > 8 && result.side == 0 { result.side = yawDeg < 0 ? 1 : -1 }

            result.eyesOpen = openness(leftEye) >= minEyeOpenRatio && openness(rightEye) >= minEyeOpenRatio
            if let inner = marks.innerLips?.pointsInImage(imageSize: size), inner.count >= 4 {
                result.mouthClosed = openness(inner) <= maxMouthOpenRatio
            }
        } else {
            // No eye/nose landmarks (typical of a real side turn): Vision's yaw
            // still gives the angle and the side.
            result.yaw = abs(yawDeg)
            if result.yaw > 8 { result.side = yawDeg < 0 ? 1 : -1 }
        }

        lumaAndSharpness(pixelBuffer, faceTopLeft: result.rectTopLeft, into: &result)
        return result
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    /// Height / width of a contour's bounding box (eye or inner-lip opening).
    private func openness(_ points: [CGPoint]) -> Double {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return 0 }
        return Double((maxY - minY) / (maxX - minX))
    }

    /// Mean luma of the face and of the frame, and Laplacian variance of the
    /// face (motion blur / focus), sampled on a grid straight from BGRA.
    private func lumaAndSharpness(_ pixelBuffer: CVPixelBuffer, faceTopLeft: CGRect, into result: inout Analysis) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        func luma(_ x: Int, _ y: Int) -> Double {
            let px = min(max(x, 0), width - 1), py = min(max(y, 0), height - 1)
            let p = bytes + py * rowBytes + px * 4
            return 0.114 * Double(p[0]) + 0.587 * Double(p[1]) + 0.299 * Double(p[2])
        }

        var frameSum = 0.0
        let coarse = 24
        for gy in 0..<coarse {
            for gx in 0..<coarse {
                frameSum += luma(gx * width / coarse + width / (2 * coarse), gy * height / coarse + height / (2 * coarse))
            }
        }
        result.frameLuma = frameSum / Double(coarse * coarse)

        guard faceTopLeft.width > 0 else { return }
        let n = 72
        let fx = faceTopLeft.minX * CGFloat(width), fy = faceTopLeft.minY * CGFloat(height)
        let fw = faceTopLeft.width * CGFloat(width), fh = faceTopLeft.height * CGFloat(height)
        var grid = [Double](repeating: 0, count: n * n)
        var faceSum = 0.0
        for gy in 0..<n {
            for gx in 0..<n {
                let x = Int(fx + fw * (CGFloat(gx) + 0.5) / CGFloat(n))
                let y = Int(fy + fh * (CGFloat(gy) + 0.5) / CGFloat(n))
                let v = luma(x, y)
                grid[gy * n + gx] = v
                faceSum += v
            }
        }
        result.faceLuma = faceSum / Double(n * n)
        var lapSum = 0.0, lapSq = 0.0, count = 0.0
        for gy in 1..<(n - 1) {
            for gx in 1..<(n - 1) {
                let i = gy * n + gx
                let lap = grid[i - 1] + grid[i + 1] + grid[i - n] + grid[i + n] - 4 * grid[i]
                lapSum += lap
                lapSq += lap * lap
                count += 1
            }
        }
        let mean = lapSum / count
        result.sharpness = lapSq / count - mean * mean
    }

    // MARK: Decisions

    private func hint(for a: Analysis) -> LensHint? {
        if a.faceCount == 0 { return .noFace }
        if a.faceCount > 1 { return .multipleFaces }
        if a.widthPx < minFaceWidthPx { return .moveCloser }
        if a.widthNorm > 0.78 { return .moveBack }
        if abs(a.cx - 0.5) > 0.2 || abs(a.cy - 0.45) > 0.22
            || a.rectTopLeft.minY < 0.02 || a.rectTopLeft.maxY > 0.98 { return .centerFace }
        // Side turns (more left/right, >= 26 deg) hide the far eye: no landmark
        // or eye rule there, one clear, still, sharp face is enough.
        let sideTurn = a.yaw >= 32
        if !a.landmarksOK && !sideTurn { return .faceCovered }
        if a.yaw > 45 { return .turnLess }
        if a.pitch > maxPitch || a.roll > maxRoll { return .keepLevel }
        if !a.eyesOpen && !sideTurn { return .openEyes }
        if !a.mouthClosed { return .closeMouth }
        if a.faceLuma < 55 { return .tooDark }
        if a.faceLuma > 220 { return .tooBright }
        if a.frameLuma - a.faceLuma > 55 { return .backlight }
        if a.sharpness < minSharpness || a.quality < minQuality { return .blurry }
        return nil
    }

    private func isStill(now: Double) -> Bool {
        // Newest sample at or before the window start anchors the window.
        guard let anchorIndex = history.lastIndex(where: { now - $0.t >= stableWindow }) else { return false }
        let recent = Array(history[anchorIndex...])
        guard recent.count >= 2 else { return false }
        func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }
        return spread(recent.map(\.yaw)) <= maxAngleDrift
            && spread(recent.map(\.pitch)) <= maxAngleDrift
            && spread(recent.map(\.roll)) <= maxAngleDrift
            && spread(recent.map(\.cx)) <= maxCentreDrift
            && spread(recent.map(\.cy)) <= maxCentreDrift
    }

    private var remaining: [LensPose] {
        targets.filter { captured[$0] == nil && !skipped.contains($0) }
    }

    private var currentTarget: LensPose? { remaining.first }

    private func process(_ a: Analysis, pixelBuffer: CVPixelBuffer, now: Double) {
        var liveHint = hint(for: a)
        if a.faceCount == 1 {
            history.append((now, a.yaw * Double(a.side == 0 ? 1 : a.side), a.pitch, a.roll, a.cx, a.cy))
        } else {
            history.removeAll()
        }
        history.removeAll { now - $0.t > 1.0 }

        let bucket = liveHint == nil ? LensPose.bucket(yaw: a.yaw, side: a.side) : nil
        // Only the pose being asked for (guided order) can capture, and only from a
        // head angle clearly different from the photos already taken (8 deg).
        let signedYaw = a.yaw * Double(a.side == 0 ? 1 : a.side)
        let distinct = capturedYaw.allSatisfy { pose, yaw in pose == bucket || abs(signedYaw - yaw) >= 15 }
        let wanted = bucket != nil && bucket == currentTarget && distinct
        let still = isStill(now: now)

        if liveHint == nil, let target = currentTarget, !wanted {
            // Guide toward the target pose.
            if target.side == 0 {
                liveHint = a.yaw > 5 ? .turnLess : nil
            } else if a.side == -target.side && a.yaw > 5 {
                liveHint = .turnOtherWay
            } else if a.side == target.side || a.yaw <= 5 {
                liveHint = a.yaw < target.idealYaw - 5 ? .turnMore : (a.yaw > target.idealYaw + 5 ? .turnLess : nil)
            }
        }

        if let pose = bucket, wanted, still {
            let score = self.score(a, pose: pose)
            if holdPose != pose {
                holdPose = pose
                holdStart = now
                holdBest = nil
            }
            if holdBest == nil || score > holdBest!.score, let image = makeImage(pixelBuffer) {
                holdBest = (score, image, Int(a.widthPx))
            }
            if now - holdStart >= holdDuration, let best = holdBest, let jpeg = jpegData(best.image) {
                captured[pose] = LensShot(pose: pose, jpeg: jpeg, quality: best.score, faceWidthPx: best.widthPx)
                capturedYaw[pose] = signedYaw
                holdPose = nil
                holdBest = nil
                checkFinished()
                publish(now: now, force: true, hint: nil, analysis: a, justCaptured: pose)
                return
            }
        } else {
            if bucket != nil && wanted && !still && liveHint == nil { liveHint = .holdStill }
            if holdPose != nil && !(bucket == holdPose && wanted) {
                holdPose = nil
                holdBest = nil
            }
        }
        publish(now: now, force: false, hint: liveHint, analysis: a)
    }

    private func score(_ a: Analysis, pose: LensPose) -> Double {
        let size = min(1, a.widthPx / goodFaceWidthPx)
        let sharp = min(1, a.sharpness / 180)
        let angle = max(0, 1 - abs(a.yaw - pose.idealYaw) / 10)
        let level = max(0, 1 - (a.pitch + a.roll) / 20)
        return a.quality * 0.5 + sharp * 0.2 + size * 0.1 + angle * 0.1 + level * 0.1
    }

    private func checkFinished() {
        if remaining.isEmpty { finished = true }
    }

    private func makeImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    private func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: Publishing

    // Hint hysteresis: a new hint shows only after holding 0.45 s, so the line
    // doesn't flicker between reasons frame to frame.
    private var shownHint: LensHint?
    private var candidateHint: LensHint?
    private var candidateSince: Double = 0
    private var hintShownOnce = false

    private func stableHint(_ hint: LensHint?, now: Double) -> LensHint? {
        if hint != candidateHint {
            candidateHint = hint
            candidateSince = now
        }
        if !hintShownOnce || hint == shownHint || now - candidateSince >= 0.45 {
            shownHint = hint
            hintShownOnce = true
        }
        return shownHint
    }

    private func publish(now: Double, force: Bool, hint: LensHint? = nil, analysis: Analysis? = nil, justCaptured: LensPose? = nil) {
        let steadyHint = stableHint(hint, now: now)
        guard force || now - lastPublish >= 1.0 / 15.0 else { return }
        lastPublish = now
        var snapshot = LensEngineSnapshot()
        snapshot.target = currentTarget
        snapshot.hint = steadyHint
        snapshot.faceFound = (analysis?.faceCount ?? 0) > 0
        if let analysis { snapshot.yaw = analysis.yaw * Double(analysis.side == 0 ? 1 : analysis.side) }
        snapshot.holdPose = holdPose
        snapshot.holdProgress = holdPose == nil ? 0 : min(1, (now - holdStart) / holdDuration)
        snapshot.captured = captured
        snapshot.skipped = skipped
        snapshot.justCaptured = justCaptured
        snapshot.isFinished = finished
        let handler = onSnapshot
        Task { @MainActor in handler(snapshot) }
    }
}
