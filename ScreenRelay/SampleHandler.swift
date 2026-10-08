import CoreImage
import ImageIO
import Network
import ReplayKit

/// Broadcast upload extension: receives the iPhone's screen while a broadcast is running and relays
/// downscaled JPEG frames to the Car TV app over loopback, which draws them on the external display.
/// Frames never leave the phone.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let maxDimension: CGFloat = 1280
    private static let minFrameInterval: CFAbsoluteTime = 1.0 / 20
    private static let jpegQuality: CGFloat = 0.6

    private let queue = DispatchQueue(label: "com.hohnholt.carplaytv.ScreenRelay")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()

    // Guarded by `lock`.
    private var connection: NWConnection?
    private var isConnected = false
    private var isSending = false
    private var isFinished = false
    private var lastFrameTime: CFAbsoluteTime = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        connect()
    }

    override func broadcastFinished() {
        lock.lock()
        isFinished = true
        let current = connection
        connection = nil
        isConnected = false
        lock.unlock()
        current?.cancel()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, claimFrameSlot(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(Self.orientation(of: sampleBuffer))
        let scale = min(1, Self.maxDimension / max(image.extent.width, image.extent.height))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: Self.jpegQuality]
        guard let jpeg = ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else {
            releaseFrameSlot()
            return
        }
        send(jpeg)
    }

    // MARK: Connection

    private func connect() {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        let newConnection = NWConnection(host: .ipv4(.loopback),
                                         port: NWEndpoint.Port(rawValue: MirrorProtocol.port)!,
                                         using: .tcp)
        connection = newConnection
        lock.unlock()

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let newConnection else { return }
            switch state {
            case .ready:
                self.lock.lock()
                self.isConnected = true
                self.isSending = false
                self.lock.unlock()
            case .failed, .waiting:
                self.reconnect(after: newConnection)
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    /// The app may not be listening yet (or was relaunched), so keep retrying once a second.
    private func reconnect(after failed: NWConnection) {
        lock.lock()
        guard connection === failed, !isFinished else { lock.unlock(); return }
        connection = nil
        isConnected = false
        lock.unlock()
        failed.cancel()
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.connect() }
    }

    private func send(_ jpeg: Data) {
        lock.lock()
        let current = connection
        lock.unlock()
        guard let current else { return releaseFrameSlot() }

        var length = UInt32(jpeg.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(jpeg)
        current.send(content: frame, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.releaseFrameSlot()
            if error != nil { self.reconnect(after: current) }
        })
    }

    // MARK: Frame pacing

    /// Only one frame in flight and at most ~20 fps; extra frames are dropped rather than queued,
    /// which keeps latency and memory low (broadcast extensions have a tight memory limit).
    private func claimFrameSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        guard isConnected, !isSending, now - lastFrameTime >= Self.minFrameInterval else { return false }
        isSending = true
        lastFrameTime = now
        return true
    }

    private func releaseFrameSlot() {
        lock.lock()
        isSending = false
        lock.unlock()
    }

    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString,
                                          attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else { return .up }
        return orientation
    }
}
