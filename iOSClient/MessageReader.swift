import Foundation
import Network
// In the app StreamProtocol is its own module; the message-reader check compiles this file together
// with Sources/StreamProtocol/StreamMessage.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// Reads the Mac's messages from one connection: each 14-byte header, then its payload in pieces of
/// at most `piece` bytes, reporting every read (`onBytes`), so that the session's liveness counts
/// bytes rather than whole messages (docs/remote-bundle-plan.md §3.4). Asked for whole, a payload
/// was one read that ended only once all of it had come: a 1.6 MB keyframe on a 2 Mbit/s path is
/// 6.4 s, longer than the 6 s liveness allows, so a slow but live session was declared lost again
/// and again while its bytes kept arriving (the pacing harness's slowkf).
///
/// - A header over the caps (`StreamMessage.maxFramePayload` for a frame,
///   `maxOtherHostPayload` for anything else) ends the reading with `.tooBig`, before anything of
///   its payload is read.
/// - A payload is read with `minimumIncompleteLength` 1 and at most `piece` bytes a read, into a
///   buffer reserved at the announced length, and delivered once complete, in order.
/// - The end of the connection (EOF) or an error, between messages or in the middle of one, ends
///   the reading with `.closed`; a message cut short is never delivered, and one that the end came
///   with is delivered first. Nothing is read after the end (a read then fails with ENODATA, which
///   the reader before this one reported as a read error after a clean close).
/// - `stillReads` false (the connection is no longer the session's, or a move's fence came back)
///   stops the reading at once: no callback, no further read.
///
/// Every callback runs on the connection's queue, one at a time; `start()` is called there too.
/// Network and StreamProtocol only: checked with swiftc against a local listener
/// (Tests/checks/message-reader).
final class MessageReader {
    /// The most one read of a payload asks for.
    static let piece = 256 * 1024

    enum End {
        /// The connection ended (EOF: the Mac closed it) or failed (the error), between messages or
        /// in the middle of one.
        case closed(NWError?)
        /// A header announced more than a Sill host ever sends: nothing after it was read.
        case tooBig(StreamHeader)
    }

    private let connection: NWConnection
    private let stillReads: () -> Bool
    private let onBytes: (Int) -> Void
    private let onMessage: (StreamHeader, Data) -> Void
    private let onEnd: (End) -> Void
    /// The message whose payload is being read, and what has come of it so far. On the queue.
    private var header: StreamHeader?
    private var buffer = Data()

    /// - `stillReads`: whether to go on reading `connection`, asked before every read and in every
    ///   callback.
    /// - `onBytes`: after every read that brought bytes (a header, or a piece of a payload), with
    ///   their number.
    /// - `onMessage`: each complete message, in order.
    /// - `onEnd`: once, when the reading ends by itself (never after `stillReads` said false).
    init(connection: NWConnection, stillReads: @escaping () -> Bool, onBytes: @escaping (Int) -> Void,
         onMessage: @escaping (StreamHeader, Data) -> Void, onEnd: @escaping (End) -> Void) {
        self.connection = connection
        self.stillReads = stillReads
        self.onBytes = onBytes
        self.onMessage = onMessage
        self.onEnd = onEnd
    }

    /// Reads the first header, and from then on every message until the end. On the connection's
    /// queue.
    func start() {
        readHeader()
    }

    private func readHeader() {
        guard stillReads() else { return }
        connection.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [self] data, _, isComplete, error in
            guard stillReads() else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                // EOF (the Mac closed cleanly) or a read error, between messages.
                if isComplete || error != nil { onEnd(.closed(error)) }
                return
            }
            onBytes(data.count)
            // Nothing a Sill host sends is bigger than these (docs/remote-access-plan.md §3.7). A
            // reader that waited for whatever a header announces could be held for ever, or read
            // an SSH banner as a 1.7 GB payload.
            let cap = header.kind == .frame ? StreamMessage.maxFramePayload : StreamMessage.maxOtherHostPayload
            guard header.payloadLength <= cap else {
                onEnd(.tooBig(header))
                return
            }
            let ended = isComplete || error != nil
            // A zero-length payload is legal (an empty window list, say); receive() rejects length 0.
            guard header.payloadLength > 0 else {
                onMessage(header, Data())
                if ended { onEnd(.closed(error)) } else { readHeader() }
                return
            }
            // The end came with the header: its payload never will. (Today Network reports the end
            // with a piece's read, whose minimum is 1, and not with a header's, whose minimum and
            // maximum are both 14; kept for a stack that does.)
            guard !ended else {
                onEnd(.closed(error))
                return
            }
            self.header = header
            buffer = Data()
            readPiece()
        }
    }

    private func readPiece() {
        guard stillReads(), let header else { return }
        let remaining = header.payloadLength - buffer.count
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, Self.piece)) { [self] data, _, isComplete, error in
            guard stillReads() else { return }
            let ended = isComplete || error != nil
            if let data, !data.isEmpty {
                onBytes(data.count)
                if buffer.isEmpty, data.count == header.payloadLength {
                    buffer = data                      // the whole payload in one read: no copy
                } else {
                    if buffer.isEmpty { buffer.reserveCapacity(header.payloadLength) }
                    buffer.append(data)
                }
                if buffer.count == header.payloadLength {
                    let payload = buffer
                    self.header = nil
                    buffer = Data()
                    onMessage(header, payload)
                    // The end can come with the last bytes: then it is the end now. (A read after it
                    // would only fail, with ENODATA, "No message available on STREAM".)
                    if ended { onEnd(.closed(error)) } else { readHeader() }
                    return
                }
            }
            // EOF or an error in the middle of a message is the Mac gone, as it is between messages:
            // what came of the message is dropped, never delivered. (Ignoring it once left a dead
            // connection on screen with a frozen picture.)
            if ended {
                self.header = nil
                buffer = Data()
                onEnd(.closed(error))
                return
            }
            // A read with nothing, no end and no error: as the reader before it, stop (the session's
            // liveness then ends it). Network does not complete a read that way on a stream.
            guard let data, !data.isEmpty else { return }
            readPiece()
        }
    }
}
