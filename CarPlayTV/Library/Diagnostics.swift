import AVFoundation
import Combine
import Foundation

/// A small timestamped log of what CarPlay and the system report (car video support, external screens,
/// external playback, audio route), shown in Settings so a test drive can be read back without a Mac.
/// Kept on this iPhone only (UserDefaults; contains no stream URLs or credentials).
@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        let date: Date
        let message: String
    }

    @Published private(set) var entries: [Entry]

    private static let key = "diagnostics.entries"
    private static let limit = 200
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        entries = (UserDefaults.standard.data(forKey: Self.key))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        observeAudioRoute()
    }

    nonisolated static func log(_ message: String) {
        Task { @MainActor in shared.add(message) }
    }

    func clear() {
        entries = []
        save()
    }

    /// Plain text for sharing.
    var report: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm:ss"
        return entries.map { "\(formatter.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
    }

    private func add(_ message: String) {
        entries.insert(Entry(date: Date(), message: message), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
        #if DEBUG
        DebugLogUploader.shared.upload()
        #endif
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }

    private func observeAudioRoute() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.add("Audio route: \(Self.describeRoute())") }
            .store(in: &cancellables)
    }

    nonisolated static func describeRoute() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard !outputs.isEmpty else { return "none" }
        return outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
    }
}
