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
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = .clear

            let bar = UIView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            overlay.addSubview(bar)

            let shutter = UIButton(type: .system)
            shutter.translatesAutoresizingMaskIntoConstraints = false
            shutter.layer.cornerRadius = 35
            shutter.backgroundColor = .white
            shutter.layer.borderWidth = 4
            shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
            shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
            bar.addSubview(shutter)

            let cancel = UIButton(type: .system)
            cancel.translatesAutoresizingMaskIntoConstraints = false
            cancel.setTitle("Cancel", for: .normal)
            cancel.setTitleColor(.white, for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
            cancel.contentHorizontalAlignment = .left
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            bar.addSubview(cancel)

            let hint = UILabel()
            hint.translatesAutoresizingMaskIntoConstraints = false
            hint.text = "Front camera only"
            hint.textAlignment = .center
            hint.textColor = UIColor.white.withAlphaComponent(0.85)
            hint.font = .systemFont(ofSize: 12, weight: .regular)
            bar.addSubview(hint)

            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
                bar.heightAnchor.constraint(equalToConstant: 140),

                shutter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
                shutter.topAnchor.constraint(equalTo: bar.topAnchor, constant: 30),
                shutter.widthAnchor.constraint(equalToConstant: 70),
                shutter.heightAnchor.constraint(equalToConstant: 70),

                cancel.leadingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                cancel.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
                cancel.widthAnchor.constraint(equalToConstant: 96),
                cancel.heightAnchor.constraint(equalToConstant: 36),

                hint.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
                hint.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
                hint.topAnchor.constraint(equalTo: shutter.bottomAnchor, constant: 10),
                hint.heightAnchor.constraint(equalToConstant: 22)
            ])

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
