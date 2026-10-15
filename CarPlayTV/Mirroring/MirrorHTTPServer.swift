import Foundation
import Network
import OSLog

/// A tiny HTTP server on loopback that serves MirrorHLSStreamer's live stream to Car TV's own player:
/// GET /mirror/index.m3u8, /mirror/init.mp4 and /mirror/seg<N>.m4s. Loopback only, so nothing is
/// reachable from the network.
final class MirrorHTTPServer {
    static let shared = MirrorHTTPServer()
    static let port: UInt16 = 47_232
    static let streamURL = URL(string: "http://127.0.0.1:\(port)/mirror/index.m3u8")!
    private static let log = Logger(subsystem: "com.hohnholt.carplaytv", category: "Mirror")

    private let queue = DispatchQueue(label: "com.hohnholt.carplaytv.MirrorHTTP")
    private var listener: NWListener?

    func start() {
        queue.async { self.startListener() }
    }

    private func startListener() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let newListener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!) else {
            return retry()
        }
        newListener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        newListener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Self.log.error("Mirror HTTP failed: \(error.localizedDescription)")
                self?.retry()
            }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func retry() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startListener() }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    /// Reads until the end of the request headers, answers, and closes (no keep-alive needed).
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var request = buffer
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || request.count > 65_536 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: request)
            }
        }
    }

    private func respond(to request: Data, on connection: NWConnection) {
        let firstLine = String(decoding: request.prefix(while: { $0 != 0x0D }), as: UTF8.self)
        let parts = firstLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : ""
        let streamer = MirrorHLSStreamer.shared

        let body: Data?
        let contentType: String
        switch path {
        case "/mirror/index.m3u8":
            body = streamer.playlist()
            contentType = "application/vnd.apple.mpegurl"
        case "/mirror/init.mp4":
            body = streamer.initializationSegment()
            contentType = "video/mp4"
        default:
            if path.hasPrefix("/mirror/seg"), path.hasSuffix(".m4s"),
               let index = Int(path.dropFirst("/mirror/seg".count).dropLast(".m4s".count)) {
                body = streamer.segment(index)
            } else {
                body = nil
            }
            contentType = "video/iso.segment"
        }

        var response: Data
        if let body {
            response = Data("""
            HTTP/1.1 200 OK\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.count)\r
            Cache-Control: no-cache\r
            Connection: close\r
            \r

            """.utf8)
            response.append(body)
        } else {
            response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
