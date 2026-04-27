import SwiftUI
import UIKit

struct PunchCameraView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                picker.cameraDevice = .front
            }
            picker.cameraCaptureMode = .photo
            picker.showsCameraControls = false
            picker.cameraOverlayView = context.coordinator.makeOverlay(for: picker)
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
        weak var picker: UIImagePickerController?

        init(_ parent: PunchCameraView) {
            self.parent = parent
        }

        func makeOverlay(for picker: UIImagePickerController) -> UIView {
            self.picker = picker
            let bounds = UIScreen.main.bounds
            let overlay = UIView(frame: bounds)
            overlay.backgroundColor = .clear

            let bar = UIView(frame: CGRect(x: 0, y: bounds.height - 140, width: bounds.width, height: 140))
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            overlay.addSubview(bar)

            let shutter = UIButton(type: .system)
            shutter.frame = CGRect(x: bounds.width / 2 - 35, y: 30, width: 70, height: 70)
            shutter.layer.cornerRadius = 35
            shutter.backgroundColor = .white
            shutter.layer.borderWidth = 4
            shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
            bar.addSubview(shutter)

            let cancel = UIButton(type: .system)
            cancel.frame = CGRect(x: 16, y: 50, width: 80, height: 30)
            cancel.setTitle("Cancel", for: .normal)
            cancel.setTitleColor(.white, for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
            cancel.contentHorizontalAlignment = .left
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            bar.addSubview(cancel)

            let hint = UILabel(frame: CGRect(x: 0, y: 110, width: bounds.width, height: 22))
            hint.text = "Front camera only"
            hint.textAlignment = .center
            hint.textColor = UIColor.white.withAlphaComponent(0.85)
            hint.font = .systemFont(ofSize: 12, weight: .regular)
            bar.addSubview(hint)

            return overlay
        }

        @objc private func takePhoto() {
            picker?.takePicture()
        }

        @objc private func cancelTapped() {
            parent.dismiss()
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
