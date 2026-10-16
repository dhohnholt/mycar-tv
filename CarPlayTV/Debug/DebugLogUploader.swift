#if DEBUG
import Foundation
import OSLog
import UIKit

/// Debug builds only: sends Diagnostics entries to the local receiver on the developer's Mac
/// (tools/debug-log-server) whenever the phone is on the same network. Entries recorded away from
/// home (e.g. in the car) wait on the phone and upload once it's back on the network. Nothing goes
/// anywhere but that Mac.
@MainActor
final class DebugLogUploader {
    static let shared = DebugLogUploader()
    private static let log = Logger(subsystem: "com.hohnholt.carplaytv", category: "DebugLog")
    private static let uploadedKey = "debuglog.uploadedIDs"

    private var uploaded: Set<UUID>
    private var isUploading = false
    private var uploadAgain = false
    private var retryTask: Task<Void, Never>?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.uploadedKey) ?? []
        uploaded = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    func start() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DebugLogUploader.shared.upload() }
        }
        upload()
    }

    /// Sends every entry the Mac hasn't confirmed yet. Safe to call often.
    func upload() {
        // An entry added mid-upload is sent right after the current upload finishes.
        guard !isUploading else { uploadAgain = true; return }
        let pending = Diagnostics.shared.entries.filter { !uploaded.contains($0.id) }
        guard !pending.isEmpty else { return }
        isUploading = true
        Task {
            defer {
                isUploading = false
                if uploadAgain {
                    uploadAgain = false
                    upload()
                }
            }
            for host in [DebugLogConfig.host, DebugLogConfig.fallbackIP] {
                if await send(pending, to: host) {
                    pending.forEach { uploaded.insert($0.id) }
                    // Forget IDs that have aged out of the Diagnostics list.
                    let live = Set(Diagnostics.shared.entries.map(\.id))
                    uploaded.formIntersection(live.union(pending.map(\.id)))
                    UserDefaults.standard.set(uploaded.map(\.uuidString), forKey: Self.uploadedKey)
                    return
                }
            }
            scheduleRetry()
        }
    }

    /// Not on the home network (e.g. in the car): try again in a minute.
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            upload()
        }
    }

    private func send(_ entries: [Diagnostics.Entry], to host: String) async -> Bool {
        guard let url = URL(string: "http://\(host):\(DebugLogConfig.port)/log") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DebugLogConfig.token, forHTTPHeaderField: "X-Debug-Token")
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: Any] = [
            "device": UIDevice.current.name,
            "entries": entries.map { ["id": $0.id.uuidString, "date": iso.string(from: $0.date), "message": $0.message] },
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await session.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok { Self.log.info("Uploaded \(entries.count) diagnostics entries to \(host)") }
            return ok
        } catch {
            return false
        }
    }
}
#endif
