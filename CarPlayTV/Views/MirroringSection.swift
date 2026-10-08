import ReplayKit
import SwiftUI

struct MirroringSection: View {
    @ObservedObject private var receiver = MirrorReceiver.shared
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Section {
            LabeledContent("External display", value: player.externalDisplayConnected ? "Connected" : "Not connected")
            LabeledContent("Screen broadcast", value: receiver.isMirroring ? "Receiving screen" : "Not receiving screen")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receiver.isMirroring ? "Broadcast controls" : "Share your screen")
                        .font(.body.weight(.semibold))
                    Text("Tap the recording button on the right.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                BroadcastPicker()
                    .frame(width: 44, height: 44)
            }
            DisclosureGroup("How screen sharing works") {
                Text("1. Connect a compatible external display. A USB CarPlay connection alone does not guarantee video support.")
                Text("2. Tap the recording button, select Car TV Mirror, then Start Broadcast.")
                Text("3. Stop sharing from the iPhone’s red recording indicator or Control Center.")
                Text("The Screen Mirroring control in Control Center lists AirPlay destinations. Car TV Mirror is a screen-broadcast provider, not a destination in that list.")
                Text("Starting a broadcast does not connect a display. CarPlay video requires a compatible vehicle and an approved app. Use video only while parked.")
                Text("Protected video may appear black. Notifications can appear in the broadcast; enable Do Not Disturb before sharing.")
            }
            .font(.footnote)
        } header: {
            Text("Screen sharing")
        } footer: {
            Text(player.externalDisplayConnected
                 ? "An external display is connected to Car TV. Start a broadcast to share your screen."
                 : "No external display is connected to Car TV. A broadcast can start without showing anything on another screen.")
        }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = MirrorProtocol.extensionBundleID
        picker.showsMicrophoneButton = false
        for button in picker.subviews.compactMap({ $0 as? UIButton }) {
            button.accessibilityLabel = "Screen broadcast controls"
            button.accessibilityHint = "Opens Car TV Mirror to start or stop screen sharing."
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
