import SwiftUI
import UIKit

struct PunchCameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.modalPresentationStyle = .fullScreen
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                picker.cameraDevice = .front
            }
            picker.cameraCaptureMode = .photo
            picker.showsCameraControls = true
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PunchCameraView

        init(_ parent: PunchCameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
