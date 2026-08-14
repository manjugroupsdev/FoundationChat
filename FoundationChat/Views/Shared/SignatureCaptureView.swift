import SwiftUI

/// Reusable signature-capture pad (mirrors the Android `SignaturePadView`).
/// Captures strokes as NORMALIZED points (0…1 of the pad size) so the drawn
/// signature rasterizes cleanly at any output size, and hands back PNG `Data`
/// on Done. Building block for the loan-approval e-signature flow.
struct SignatureCaptureView: View {
    var title: String = "Signature"
    var prompt: String = "Sign inside the box"
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Each stroke is a list of normalized points (x,y in 0…1).
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    private var isEmpty: Bool { strokes.isEmpty && current.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    Canvas { context, _ in
                        context.stroke(
                            strokePath(in: geo.size),
                            with: .color(Color(hex: 0x101828)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                current.append(normalize(value.location, in: geo.size))
                            }
                            .onEnded { _ in
                                if !current.isEmpty { strokes.append(current) }
                                current = []
                            }
                    )
                }
                .frame(height: 220)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD0D5DD), lineWidth: 1))

                HStack {
                    Button {
                        strokes = []
                        current = []
                    } label: {
                        Label("Clear", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isEmpty)
                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .disabled(isEmpty)
                }
            }
        }
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(
            x: min(max(point.x / size.width, 0), 1),
            y: min(max(point.y / size.height, 0), 1)
        )
    }

    private func strokePath(in size: CGSize) -> Path {
        var path = Path()
        let all = strokes + (current.isEmpty ? [] : [current])
        for stroke in all {
            guard let first = stroke.first else { continue }
            path.move(to: denormalize(first, in: size))
            for point in stroke.dropFirst() {
                path.addLine(to: denormalize(point, in: size))
            }
        }
        return path
    }

    private func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    @MainActor
    private func finish() {
        let all = strokes + (current.isEmpty ? [] : [current])
        let output = CGSize(width: 600, height: 260)
        let renderer = ImageRenderer(
            content: SignatureRasterView(strokes: all, size: output)
        )
        renderer.scale = 2
        if let image = renderer.uiImage, let data = image.pngData() {
            onDone(data)
        }
        dismiss()
    }
}

/// White-background raster of the captured (normalized) strokes at a fixed size,
/// used by `ImageRenderer` to produce the exported PNG.
private struct SignatureRasterView: View {
    let strokes: [[CGPoint]]
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: scaled(first, canvasSize))
                for point in stroke.dropFirst() {
                    path.addLine(to: scaled(point, canvasSize))
                }
            }
            context.stroke(
                path,
                with: .color(.black),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
    }

    private func scaled(_ point: CGPoint, _ canvasSize: CGSize) -> CGPoint {
        CGPoint(x: point.x * canvasSize.width, y: point.y * canvasSize.height)
    }
}
