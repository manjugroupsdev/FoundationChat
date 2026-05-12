import AVKit
import SwiftUI

struct SplashVideoView: View {
    let onFinished: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if let player {
                VideoPlayerLayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { player?.pause() }
    }

    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "mp4") else {
            onFinished()
            return
        }
        let p = AVPlayer(url: url)
        self.player = p

        // Observe end of video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { _ in
            onFinished()
        }

        p.play()
    }
}

// UIViewRepresentable wrapper for AVPlayer without controls
private struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .white
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
