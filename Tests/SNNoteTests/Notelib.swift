// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import ImageIO
import Network
import SNNote
import Synchronization

/// The Private Cloud's renderer, as the oracle the bitmaps are checked against.
///
/// The Supernote Private Cloud ships `notelib` — the converter behind its web
/// UI's "view as picture" — as a container of its own. It speaks JSON over TCP
/// on port 6000, reachable only from inside the compose network, and works
/// entirely by URL: it downloads the `.note` from one address and uploads a
/// PNG per page to others. So the test brings both ends: a loopback HTTP
/// server here that serves the file and takes the uploads, and a one-line Perl
/// client run inside the service container (`docker exec`) that sends the
/// request — Perl because that container has it and has no `curl`.
///
/// Opt-in, by naming the container: `SNNOTE_NOTELIB_CONTAINER=sn-supernote-service`.
/// `SNNOTE_NOTELIB_HOST` is how containers reach this machine,
/// `host.docker.internal` by default (Docker Desktop). Nothing is uploaded to
/// the cloud and no account is involved; the file only ever travels between
/// this process and the converter.
enum Notelib {
    static var container: String? {
        ProcessInfo.processInfo.environment["SNNOTE_NOTELIB_CONTAINER"].flatMap { $0.isEmpty ? nil : $0 }
    }

    static var isAvailable: Bool { container != nil }

    private static var hostAlias: String {
        ProcessInfo.processInfo.environment["SNNOTE_NOTELIB_HOST"] ?? "host.docker.internal"
    }

    /// The pages of `note` as the converter renders them, as 8-bit grey rasters.
    static func render(_ note: Data) async throws -> [SNRaster] {
        let server = try await LoopbackHTTPServer.start(serving: note)
        defer { server.stop() }
        let base = "http://\(hostAlias):\(server.port)"

        let count = try request(#"{"busCode":"T03","downloadUrl":"\#(base)/file.note","fileServer":null}"#)
        guard let pages = count["totalPageNo"] as? Int, pages > 0 else {
            throw NotelibError.reply("T03: \(count)")
        }
        let targets = (1...pages).map { page in
            #"{"pageNo":\#(page),"url":"\#(base)/up/\#(page)","postAuthorization":null,"#
                + #""putAuthorization":null,"s3Authorization":null,"fileServer":null,"xamzDate":null}"#
        }
        let rendered = try request(
            #"{"busCode":"T02","downloadUrl":"\#(base)/file.note","transferUrlDTOList":["#
                + targets.joined(separator: ",")
                + #"],"fileServer":null,"innerName":"oracle"}"#
        )
        guard rendered["success"] as? Bool == true else { throw NotelibError.reply("T02: \(rendered)") }

        return try (1...pages).map { page in
            guard let png = server.upload(named: String(page)) else { throw NotelibError.missingPage(page) }
            return try grayRaster(png: png)
        }
    }

    /// One request to notelib: an eight-digit length, then the JSON. The reply
    /// is bare JSON.
    private static func request(_ json: String) throws -> [String: Any] {
        guard let container else { throw NotelibError.notConfigured }
        let script = """
        use IO::Socket::INET; my $j = shift;
        my $s = IO::Socket::INET->new(PeerAddr => 'notelib', PeerPort => 6000, Proto => 'tcp', Timeout => 30)
          or die "connect: $!";
        print $s sprintf('%08d', length($j)) . $j;
        my ($b, $r) = ('', ''); while (sysread($s, $r, 65536)) { $b .= $r } print $b;
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "exec", container, "perl", "-e", script, json]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let reply = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
        else {
            throw NotelibError.reply(String(decoding: reply, as: UTF8.self))
        }
        return object
    }

    /// A PNG reduced to grey the same way the package reduces one.
    static func grayRaster(png: Data) throws -> SNRaster {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw NotelibError.badImage }
        let width = image.width
        let height = image.height
        var gray = [UInt8](repeating: 255, count: width * height)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let raster = SNRaster(
            width: width,
            height: height,
            gray: gray,
            alpha: [UInt8](repeating: 255, count: width * height)
        ) else { throw NotelibError.badImage }
        return raster
    }
}

enum NotelibError: Error {
    case notConfigured
    case reply(String)
    case missingPage(Int)
    case badImage
}

/// Just enough HTTP for notelib: `GET` of the one file, and `POST`/`PUT` of
/// uploads — multipart or raw — kept by the last path component.
final class LoopbackHTTPServer: Sendable {
    private let listener: NWListener
    private let note: Data
    private let uploads = Mutex<[String: Data]>([:])

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    private init(listener: NWListener, note: Data) {
        self.listener = listener
        self.note = note
    }

    static func start(serving note: Data) async throws -> LoopbackHTTPServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        let server = LoopbackHTTPServer(listener: try NWListener(using: parameters), note: note)
        let listener = server.listener
        listener.newConnectionHandler = { [server] connection in server.serve(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Mutex(false)
            let claim: @Sendable () -> Bool = { resumed.withLock { done -> Bool in
                if done { return false }
                done = true
                return true
            } }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if claim() { continuation.resume() }
                case let .failed(error):
                    if claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        return server
    }

    func stop() {
        listener.cancel()
    }

    func upload(named name: String) -> Data? {
        uploads.withLock { $0[name] }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] chunk, _, finished, error in
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if let request = Request(buffer) {
                if request.needsContinue, !request.isComplete {
                    connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
                }
                if request.isComplete {
                    respond(to: request, on: connection)
                    return
                }
            }
            if finished || error != nil {
                connection.cancel()
                return
            }
            receive(on: connection, buffer: buffer)
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let status: String
        var body = Data()
        switch request.method {
        case "GET", "HEAD":
            status = "200 OK"
            if request.method == "GET" { body = note }
        case "POST", "PUT":
            let name = request.path.split(separator: "/").last.map(String.init) ?? "upload"
            uploads.withLock { $0[name] = request.uploadedFile }
            status = "200 OK"
            body = Data(#"{"success":true}"#.utf8)
        default:
            status = "405 Method Not Allowed"
        }
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(request.method == "HEAD" ? note.count : body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
        let expectedLength: Int

        var isComplete: Bool { body.count >= expectedLength }
        var needsContinue: Bool { headers["expect"]?.lowercased() == "100-continue" }

        init?(_ buffer: Data) {
            guard let split = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
            let lines = String(decoding: buffer[..<split.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = lines[0].split(separator: " ")
            guard first.count >= 2 else { return nil }
            method = String(first[0])
            path = String(first[1])
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
            }
            self.headers = headers
            body = Data(buffer[split.upperBound...])
            expectedLength = Int(headers["content-length"] ?? "0") ?? 0
        }

        /// The `file` part of a multipart body, or the body itself.
        var uploadedFile: Data {
            guard let type = headers["content-type"], let range = type.range(of: "boundary=") else { return body }
            let name = type[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let boundary = Data(("--" + name).utf8)
            guard let start = body.firstRange(of: boundary),
                  let headEnd = body[start.upperBound...].firstRange(of: Data("\r\n\r\n".utf8))
            else { return body }
            let content = body[headEnd.upperBound...]
            guard let end = content.firstRange(of: Data("\r\n".utf8) + boundary) else { return Data(content) }
            return Data(content[..<end.lowerBound])
        }
    }
}
