import SwiftUI

struct PhonePlayerView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VideoSurface(role: .phone)
                .ignoresSafeArea()
            HStack(spacing: 24) {
                Button { player.phonePlayerPresented = false } label: {
                    Image(systemName: "chevron.down")
                }
                Text(player.current?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
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
    let role: PlayerController.SurfaceRole

    func makeUIView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        PlayerController.shared.register(view, as: role)
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceView, context: Context) {}

    static func dismantleUIView(_ uiView: VideoSurfaceView, coordinator: ()) {
        PlayerController.shared.unregister(uiView)
    }
}
