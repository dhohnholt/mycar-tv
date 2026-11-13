import Foundation

/// Whether the user has agreed to the current terms (watch only while parked, bring your own content).
/// Nothing plays, on the phone or the car screen, until they have.
@MainActor
final class TermsStore: ObservableObject {
    static let shared = TermsStore()

    /// Bump when the terms change materially; everyone is asked again once.
    static let currentVersion = 1
    static let termsURL = URL(string: "https://cartv.tmechsmonitor.org/terms.html")!
    static let privacyURL = URL(string: "https://cartv.tmechsmonitor.org/privacy.html")!

    private static let versionKey = "termsAcceptedVersion"
    private static let dateKey = "termsAcceptedDate"

    @Published private(set) var accepted: Bool
    @Published private(set) var acceptedDate: Date?

    private init() {
        let defaults = UserDefaults.standard
        accepted = defaults.integer(forKey: Self.versionKey) >= Self.currentVersion
        acceptedDate = defaults.object(forKey: Self.dateKey) as? Date
    }

    func accept() {
        let now = Date()
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.versionKey)
        UserDefaults.standard.set(now, forKey: Self.dateKey)
        acceptedDate = now
        accepted = true
        Diagnostics.log("Terms v\(Self.currentVersion) accepted")
    }
}
