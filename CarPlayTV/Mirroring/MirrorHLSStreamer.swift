import AVFoundation
import CoreGraphics
import OSLog
import UniformTypeIdentifiers

/// Turns mirrored screen frames into a live HLS stream (fMP4, ~1 s segments) kept in memory, so the
/// mirror can be played by Car TV's normal player and reach the car display the same way any channel
/// does. MirrorHTTPServer serves it on loopback.
final class MirrorHLSStreamer: NSObject {
    static let shared = MirrorHLSStreamer()
    private static let log = Logger(subsystem: "com.hohnholt.carplaytv", category: "Mirror")

    /// Fixed landscape canvas for the car display; phone frames are letterboxed into it, so rotating
    /// the phone never changes the stream's format.
    private static let width = 1280
    private static let height = 720
    private static let framesPerSecond: Int32 = 15
    private static let segmentsInPlaylist = 6

    private let queue = DispatchQueue(label: "com.hohnholt.carplaytv.MirrorHLS")

    // All state below is only touched on `queue`.
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var timer: DispatchSourceTimer?
    private var latestFrame: CGImage?
    private var frameIndex: Int64 = 0
    private var initSegment: Data?
    private var segments: [(index: Int, duration: Double, data: Data)] = []
    private var nextSegmentIndex = 0

    func start() {
        queue.async { self.startWriting() }
    }

    func stop() {
        queue.async { self.stopWriting() }
    }

    /// Called with each decoded mirror frame; the timer encodes whatever is latest, which also repeats
    /// the last frame when the screen isn't changing (ReplayKit only sends frames on change).
    func submit(_ frame: CGImage) {
        queue.async { self.latestFrame = frame }
    }

    var isStreaming: Bool { queue.sync { initSegment != nil && !segments.isEmpty } }

    // MARK: Served content

    func playlist() -> Data? {
        queue.sync {
            guard initSegment != nil, let first = segments.first else { return nil }
            let target = Int((segments.map(\.duration).max() ?? 1).rounded(.up))
            var text = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:\(max(target, 1))
            #EXT-X-MEDIA-SEQUENCE:\(first.index)
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MAP:URI="init.mp4"

            """
            for segment in segments {
                text += String(format: "#EXTINF:%.3f,\n", segment.duration)
                text += "seg\(segment.index).m4s\n"
            }
            return Data(text.utf8)
        }
    }

    func initializationSegment() -> Data? {
        queue.sync { initSegment }
    }

    func segment(_ index: Int) -> Data? {
        queue.sync { segments.first(where: { $0.index == index })?.data }
    }

    // MARK: Writing

    private func startWriting() {
        guard writer == nil else { return }
        let newWriter = AVAssetWriter(contentType: UTType(AVFileType.mp4.rawValue)!)
        newWriter.outputFileTypeProfile = .mpeg4AppleHLS
        newWriter.preferredOutputSegmentInterval = CMTime(seconds: 1, preferredTimescale: 1)
        newWriter.initialSegmentStartTime = .zero
        newWriter.delegate = self

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 3_000_000,
                AVVideoExpectedSourceFrameRateKey: Self.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: Self.framesPerSecond, // a keyframe at every 1 s segment
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let newInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        newInput.expectsMediaDataInRealTime = true
        let newAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: newInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
        ])
        guard newWriter.canAdd(newInput) else { return Self.log.error("Mirror HLS: can't add video input") }
        newWriter.add(newInput)
        guard newWriter.startWriting() else {
            return Self.log.error("Mirror HLS: startWriting failed: \(newWriter.error?.localizedDescription ?? "unknown")")
        }
        newWriter.startSession(atSourceTime: .zero)

        writer = newWriter
        input = newInput
        adaptor = newAdaptor
        frameIndex = 0
        segments = []
        initSegment = nil
        nextSegmentIndex = 0

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: 1.0 / Double(Self.framesPerSecond))
        newTimer.setEventHandler { [weak self] in self?.appendFrame() }
        newTimer.resume()
        timer = newTimer
        Self.log.info("Mirror HLS: started")
    }

    private func stopWriting() {
        timer?.cancel()
        timer = nil
        input?.markAsFinished()
        writer?.cancelWriting()
        writer = nil
        input = nil
        adaptor = nil
        latestFrame = nil
        initSegment = nil
        segments = []
        Self.log.info("Mirror HLS: stopped")
    }

    private func appendFrame() {
        guard let frame = latestFrame, let input, let adaptor, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return }
        Self.draw(frame, into: pixelBuffer)
        let time = CMTime(value: frameIndex, timescale: Self.framesPerSecond)
        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            frameIndex += 1
        }
    }

    /// Letterboxes the frame (aspect fit) onto a black canvas.
    private static func draw(_ image: CGImage, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: origin, size: size))
    }
}

extension MirrorHLSStreamer: AVAssetWriterDelegate {
    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
                     segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?) {
        // Delivered on the writer's own queue; hop to ours for the shared state.
        queue.async {
            guard writer === self.writer else { return }
            switch segmentType {
            case .initialization:
                self.initSegment = segmentData
            case .separable:
                let duration = segmentReport?.trackReports.first?.duration.seconds ?? 1
                self.segments.append((self.nextSegmentIndex, duration, segmentData))
                self.nextSegmentIndex += 1
                if self.segments.count > Self.segmentsInPlaylist {
                    self.segments.removeFirst(self.segments.count - Self.segmentsInPlaylist)
                }
            @unknown default:
                break
            }
        }
    }
}
