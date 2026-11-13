import SwiftUI

/// Shown on first launch (and again when the terms change). The user must agree before anything plays.
struct TermsAgreementView: View {
    @ObservedObject private var terms = TermsStore.shared
    @State private var agreed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "car.side")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("Before you start")
                        .font(.largeTitle.bold())
                    Text("Please read and agree to these points to use My Car TV.")
                        .foregroundStyle(.secondary)
                }

                TermsPoint(symbol: "parkingsign.circle.fill", color: .red,
                           title: "Only while parked",
                           text: "Watch video only when your vehicle is parked. Never watch, browse or set up video while driving. You are responsible for obeying traffic laws and driving safely.")
                TermsPoint(symbol: "tv", color: .blue,
                           title: "Bring your own content",
                           text: "My Car TV is a player. It doesn't include or sell any channels, movies or subscriptions. You must have the right to watch anything you add or play.")
                TermsPoint(symbol: "lock.fill", color: .green,
                           title: "Your data stays on this iPhone",
                           text: "Playlists, logins and Google sign-in tokens are stored only in this iPhone's Keychain. The app has no analytics or ads.")

                HStack(spacing: 16) {
                    Link("Terms of Service", destination: TermsStore.termsURL)
                    Link("Privacy Policy", destination: TermsStore.privacyURL)
                }
                .font(.subheadline.weight(.semibold))

                Toggle(isOn: $agreed) {
                    Text("I have read and agree to the Terms of Service, and I will only watch video while my vehicle is parked.")
                        .font(.subheadline)
                }
                .toggleStyle(CheckboxToggleStyle())

                Button {
                    terms.accept()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
            }
            .padding(24)
        }
    }
}

private struct TermsPoint: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tappable checkbox for the agreement.
private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        .accessibilityHint("Agree to the terms")
    }
}

#Preview {
    TermsAgreementView()
}
