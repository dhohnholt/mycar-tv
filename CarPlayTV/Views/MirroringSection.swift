import ReplayKit
import SwiftUI

/// Settings section for screen mirroring: Apple's broadcast picker, preselected to Car TV's
/// ScreenRelay extension, plus the current status.
struct MirroringSection: View {
    @ObservedObject private var receiver = MirrorReceiver.shared

    var body: some View {
        Section {
            HStack {
                Label(receiver.isMirroring ? "Mirroring" : "Start mirroring",
                      systemImage: receiver.isMirroring ? "dot.radiowaves.left.and.right" : "rectangle.on.rectangle")
                    .foregroundStyle(receiver.isMirroring ? .green : .primary)
                Spacer()
                BroadcastPicker()
                    .frame(width: 44, height: 44)
            }
        } header: {
            Text("Screen mirroring")
        } footer: {
            Text("Shows your iPhone screen on the car display. Tap the button, choose Car TV Mirror, then Start Broadcast. Stop it from the red indicator or Control Center. Protected video (for example Netflix) appears black. The screen never leaves your iPhone except to the car display.")
        }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = MirrorProtocol.extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
