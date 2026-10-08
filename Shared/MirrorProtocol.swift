import Foundation

/// Wire format between the ScreenRelay broadcast extension and the app: over a loopback TCP
/// connection, each frame is a 4-byte big-endian length followed by that many bytes of JPEG.
enum MirrorProtocol {
    static let port: UInt16 = 47_231
    static let maxFrameBytes = 8_000_000
    static let extensionBundleID = "com.hohnholt.carplaytv.ScreenRelay"
}
