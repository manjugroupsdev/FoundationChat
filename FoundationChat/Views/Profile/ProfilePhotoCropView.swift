import SwiftUI
import UIKit

struct ProfilePhotoCropView: View {
  @Environment(\.dismiss) private var dismiss

  let image: UIImage
  let onCrop: (Data) -> Void

  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var currentCropSide: CGFloat = 340

  var body: some View {
    NavigationStack {
      VStack(spacing: 22) {
        GeometryReader { proxy in
          let side = min(proxy.size.width - 40, proxy.size.height)
          ZStack {
            Color.black.opacity(0.92)

            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: side, height: side)
              .scaleEffect(scale)
              .offset(offset)
              .clipShape(Rectangle())

            Circle()
              .stroke(.white, lineWidth: 2)
              .frame(width: side, height: side)
              .allowsHitTesting(false)

            cropMask(side: side)
              .allowsHitTesting(false)
          }
          .frame(width: side, height: side)
          .clipShape(Rectangle())
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
          .gesture(dragGesture(cropSide: side))
          .simultaneousGesture(magnifyGesture(cropSide: side))
          .task(id: side) {
            currentCropSide = side
          }
        }
        .frame(height: 380)

        Text("Pinch to zoom and drag to position your profile photo.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }
      .padding(.top, 18)
      .navigationTitle("Crop Photo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Use Photo") {
            let data = image.croppedProfileJPEG(
              cropSide: currentCropSide,
              displayScale: scale,
              displayOffset: offset
            )
            onCrop(data)
            dismiss()
          }
        }
      }
    }
  }

  private func dragGesture(cropSide: CGFloat) -> some Gesture {
    DragGesture()
      .onChanged { value in
        let proposed = CGSize(
          width: lastOffset.width + value.translation.width,
          height: lastOffset.height + value.translation.height
        )
        offset = clampedOffset(proposed, cropSide: cropSide, scale: scale)
      }
      .onEnded { _ in
        offset = clampedOffset(offset, cropSide: cropSide, scale: scale)
        lastOffset = offset
      }
  }

  private func magnifyGesture(cropSide: CGFloat) -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        scale = min(max(lastScale * value, 1), 5)
        offset = clampedOffset(offset, cropSide: cropSide, scale: scale)
      }
      .onEnded { _ in
        scale = min(max(scale, 1), 5)
        offset = clampedOffset(offset, cropSide: cropSide, scale: scale)
        lastScale = scale
        lastOffset = offset
      }
  }

  private func clampedOffset(_ proposed: CGSize, cropSide: CGFloat, scale: CGFloat) -> CGSize {
    let baseScale = max(cropSide / image.size.width, cropSide / image.size.height)
    let displayedSize = CGSize(
      width: image.size.width * baseScale * scale,
      height: image.size.height * baseScale * scale
    )
    let maxX = max(0, (displayedSize.width - cropSide) / 2)
    let maxY = max(0, (displayedSize.height - cropSide) / 2)
    return CGSize(
      width: min(max(proposed.width, -maxX), maxX),
      height: min(max(proposed.height, -maxY), maxY)
    )
  }

  private func cropMask(side: CGFloat) -> some View {
    Rectangle()
      .fill(.black.opacity(0.36))
      .frame(width: side, height: side)
      .mask {
        Rectangle()
          .overlay {
            Circle()
              .frame(width: side, height: side)
              .blendMode(.destinationOut)
          }
      }
      .compositingGroup()
  }
}

extension UIImage {
  func normalizedForProfileCrop() -> UIImage {
    let maxDimension: CGFloat = 2048
    let drawSize: CGSize
    if max(size.width, size.height) > maxDimension {
      let ratio = maxDimension / max(size.width, size.height)
      drawSize = CGSize(width: size.width * ratio, height: size.height * ratio)
    } else {
      drawSize = size
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: drawSize, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: drawSize))
    }
  }

  func croppedProfileJPEG(cropSide: CGFloat, displayScale: CGFloat, displayOffset: CGSize) -> Data {
    let baseScale = max(cropSide / size.width, cropSide / size.height)
    let effectiveScale = baseScale * displayScale
    let displayedWidth = size.width * effectiveScale
    let displayedHeight = size.height * effectiveScale

    let originX = ((displayedWidth - cropSide) / 2 - displayOffset.width) / effectiveScale
    let originY = ((displayedHeight - cropSide) / 2 - displayOffset.height) / effectiveScale
    let side = cropSide / effectiveScale
    let cropRect = CGRect(
      x: min(max(originX, 0), max(size.width - side, 0)),
      y: min(max(originY, 0), max(size.height - side, 0)),
      width: min(side, size.width),
      height: min(side, size.height)
    )

    guard let cgImage,
          let cropped = cgImage.cropping(to: cropRect.integral) else {
      return jpegData(compressionQuality: 0.86) ?? Data()
    }

    let square = UIImage(cgImage: cropped)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let output = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
      .image { _ in
        square.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
      }
    return output.jpegData(compressionQuality: 0.86) ?? Data()
  }
}
