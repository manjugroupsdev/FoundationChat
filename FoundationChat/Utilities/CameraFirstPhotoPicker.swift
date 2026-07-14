import SwiftUI
import PhotosUI
import UIKit

struct CameraFirstPhotoPicker<Label: View>: View {
    let maxSelectionCount: Int
    let isDisabled: Bool
    let onPhotos: ([Data]) async -> Void
    @ViewBuilder let label: () -> Label

    @State private var showSourceOptions = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var galleryItems: [PhotosPickerItem] = []
    @State private var capturedImage: UIImage?

    init(
        maxSelectionCount: Int = 1,
        isDisabled: Bool = false,
        onPhotos: @escaping ([Data]) async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.maxSelectionCount = max(1, maxSelectionCount)
        self.isDisabled = isDisabled
        self.onPhotos = onPhotos
        self.label = label
    }

    var body: some View {
        Button {
            showSourceOptions = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .confirmationDialog("Add Photo", isPresented: $showSourceOptions, titleVisibility: .visible) {
            Button("Camera") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    showGallery = true
                }
            }
            Button("Gallery") {
                showGallery = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            NativeCameraCaptureView(image: $capturedImage)
                .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showGallery,
            selection: $galleryItems,
            maxSelectionCount: maxSelectionCount,
            matching: .images
        )
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            capturedImage = nil
            Task {
                if let data = image.cameraFirstJPEGData() {
                    await onPhotos([data])
                }
            }
        }
        .onChange(of: galleryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [Data] = []
                for item in items.prefix(maxSelectionCount) {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let compressed = UIImage(data: data)?.cameraFirstJPEGData() {
                        loaded.append(compressed)
                    } else if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                        loaded.append(data)
                    }
                }
                galleryItems = []
                if !loaded.isEmpty {
                    await onPhotos(loaded)
                }
            }
        }
    }
}

private struct NativeCameraCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if picker.sourceType == .camera {
            picker.cameraCaptureMode = .photo
            picker.showsCameraControls = true
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: NativeCameraCaptureView

        init(parent: NativeCameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension UIImage {
    func cameraFirstJPEGData(maxEdge: CGFloat = 1080, quality: CGFloat = 0.82) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > 0 ? min(1, maxEdge / longest) : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
