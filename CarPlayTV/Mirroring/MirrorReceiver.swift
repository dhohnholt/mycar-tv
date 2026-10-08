import Combine
import ImageIO
import Network
import OSLog
import UIKit

/// Listens on loopback for frames from the ScreenRelay broadcast extension and hands decoded images
/// to whoever is drawing them (the external display). Loopback only: nothing is reachable from the
/// network.
final class MirrorReceiver: ObservableObject {
    static let shared = MirrorReceiver()
    private static let log = Logger(subsystem: "com.hohnholt.carplaytv", category: "Mirror")

    /// True while a broadcast is connected and sending frames. Published on the main thread.
    @Published private(set) var isMirroring = false

    /// Called on the main thread with each decoded frame.
    var onFrame: ((CGImage) -> Void)?

    private let queue = DispatchQueue(label: "com.hohnholt.carplaytv.MirrorReceiver")
    private var listener: NWListener?
    private var connection: NWConnection?

    private init() {}

    func start() {
        queue.async { self.startListener() }
    }

    private func startListener() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let newListener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: MirrorProtocol.port)!) else {
            return retryListener()
        }
        newListener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: Self.log.info("Mirror listener ready on port \(MirrorProtocol.port)")
            case .failed(let error):
                Self.log.error("Mirror listener failed: \(error.localizedDescription)")
                self?.retryListener()
            default: break
            }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func retryListener() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startListener() }
    }

    /// One broadcast at a time; a new connection replaces the old one.
    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let newConnection else { return }
            switch state {
            case .ready:
                Self.log.info("Mirror broadcast connected")
                self.setMirroring(true)
            case .failed, .cancelled:
                if self.connection === newConnection {
                    Self.log.info("Mirror broadcast disconnected")
                    self.connection = nil
                    self.setMirroring(false)
                }
            default:
                break
            }
        }
        newConnection.start(queue: queue)
        readHeader(on: newConnection)
    }

    private func readHeader(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, data.count == 4, error == nil else {
                if isComplete || error != nil { connection.cancel() }
                return
            }
            let length = data.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
            guard length > 0, length <= MirrorProtocol.maxFrameBytes else { return connection.cancel() }
            self.readFrame(of: length, on: connection)
        }
    }

    private func readFrame(of length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, data.count == length, error == nil else {
                if isComplete || error != nil { connection.cancel() }
                return
            }
            if let image = Self.decode(data) {
                Self.log.debug("Mirror frame \(image.width)x\(image.height), \(length) bytes")
                DispatchQueue.main.async { self.onFrame?(image) }
            }
            self.readHeader(on: connection)
        }
    }

    /// Decodes off the main thread so drawing the frame doesn't stall the UI.
    private static func decode(_ jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func setMirroring(_ mirroring: Bool) {
        DispatchQueue.main.async {
            guard self.isMirroring != mirroring else { return }
            self.isMirroring = mirroring
            // Car TV must keep running in the background to receive frames while another app is open.
            if mirroring { BackgroundKeepAlive.shared.start() } else { BackgroundKeepAlive.shared.stop() }
        }
    }
}
