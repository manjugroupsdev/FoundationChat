import AVFoundation
import SwiftUI
import UIKit

struct MessageAttachementView: View {
  let message: Message
  let isOutgoing: Bool
  @State private var isPresentingFullscreenImage = false

  private var isImageAttachment: Bool {
    message.attachementType == "image"
      || message.attachementMimeType?.hasPrefix("image/") == true
  }

  private var isVideoAttachment: Bool {
    message.attachementType == "video"
      || message.attachementMimeType?.hasPrefix("video/") == true
  }

  private var mediaURL: URL? {
    guard let raw = message.attachementThumbnail else { return nil }
    return URL(string: raw)
  }

  private var attachmentURL: URL? {
    guard let raw = message.attachementURL else { return nil }
    return URL(string: raw)
  }

  private var displayFileName: String? {
    if let name = message.attachementFileName, !name.isEmpty {
      return name
    }
    if let title = message.attachementTitle, !title.isEmpty {
      return title
    }
    return nil
  }

  var body: some View {
    if isImageAttachment, let mediaURL {
      AsyncImage(url: mediaURL) { state in
        if let image = state.image {
          image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 260, maxHeight: 360)
        } else {
          ProgressView()
            .frame(width: 260, height: 180)
        }
      }
      .overlay(
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .stroke(Color.primary.opacity(0.2), lineWidth: 1)
      )
      .contentShape(Rectangle())
      .onTapGesture {
        isPresentingFullscreenImage = true
      }
      .fullScreenCover(isPresented: $isPresentingFullscreenImage) {
        FullscreenImageViewer(imageURL: mediaURL)
      }
    } else if isVideoAttachment, let mediaURL {
      VideoThumbnailPreview(url: mediaURL)
        .clipShape(.rect(cornerRadius: 16))
    } else if let displayFileName {
      HStack(spacing: 8) {
        Image(systemName: "doc")
          .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .primary)
        Text(displayFileName)
          .foregroundStyle(isOutgoing ? .white : .primary)
          .font(.subheadline)
          .lineLimit(2)
        Spacer(minLength: 0)
        if let attachmentURL {
          ShareLink(item: attachmentURL) {
            Image(systemName: "square.and.arrow.up")
              .foregroundStyle(isOutgoing ? .white.opacity(0.95) : .primary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(isOutgoing ? .white.opacity(0.2) : .white.opacity(0.75))
      .clipShape(.rect(cornerRadius: 12))
      .onTapGesture {
        if let attachmentURL {
          UIApplication.shared.open(attachmentURL)
        }
      }
    }
  }
}

private struct FullscreenImageViewer: View {
  let imageURL: URL
  @Environment(\.dismiss) private var dismiss
  @State private var dragOffset: CGFloat = 0

  var body: some View {
    ZStack {
      Color.black
        .opacity(backgroundOpacity)
        .ignoresSafeArea()

      AsyncImage(url: imageURL) { state in
        if let image = state.image {
          image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        } else {
          ProgressView()
            .tint(.white)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 24)
      .offset(y: max(0, dragOffset))
      .gesture(
        DragGesture(minimumDistance: 8)
          .onChanged { value in
            if value.translation.height > 0 {
              dragOffset = value.translation.height
            }
          }
          .onEnded { value in
            if value.translation.height > 140 {
              dismiss()
              return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
              dragOffset = 0
            }
          }
      )
    }
    .safeAreaInset(edge: .top) {
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.55), in: Circle())
            .overlay(
              Circle()
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
    }
  }

  private var backgroundOpacity: Double {
    let progress = min(max(dragOffset / 280, 0), 1)
    return 1 - (progress * 0.35)
  }
}

private struct VideoThumbnailPreview: View {
  let url: URL
  @State private var thumbnail: UIImage?

  var body: some View {
    ZStack {
      if let thumbnail {
        Image(uiImage: thumbnail)
          .resizable()
          .scaledToFill()
      } else {
        Color.secondary
      }

      Image(systemName: "play.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(.white)
        .shadow(radius: 4)
    }
    .frame(height: 220)
    .clipped()
    .task(id: url) {
      thumbnail = await generateThumbnail(for: url)
    }
  }

  private func generateThumbnail(for url: URL) async -> UIImage? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)

        do {
          let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
          continuation.resume(returning: UIImage(cgImage: cgImage))
        } catch {
          continuation.resume(returning: nil)
        }
      }
    }
  }
}
