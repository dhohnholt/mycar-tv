import AVKit
import SwiftUI

struct PhonePlayerView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VideoSurface()
                .ignoresSafeArea()
            HStack(spacing: 24) {
                Button { player.phonePlayerPresented = false } label: {
                    Image(systemName: "chevron.down")
                }
                Text(player.current?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                AirPlayButton()
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("AirPlay")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                }
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding()
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct VideoSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        PlayerController.shared.register(view)
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceView, context: Context) {}

    static func dismantleUIView(_ uiView: VideoSurfaceView, coordinator: ()) {
        PlayerController.shared.unregister(uiView)
    }
}

/// The system AirPlay picker, for sending the current video to an Apple TV, a Mac, or other receiver.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
