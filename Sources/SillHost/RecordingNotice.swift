import Foundation

/// The Mac's side of a device recording the stream (#284, docs/recording-plan.md): what this host says it
/// does (`generation`, the window list's `recordings`), and the lines its log writes from the devices'
/// reports (`ClientStats.recording`, kind 12, once a second). The menu's words are StatusText's, from
/// `HostStatusSnapshot.Device.recording`.
///
/// A courtesy, never a control: the field is display only, so the host acts on nothing it says, keeps
/// nothing past the connection, and never refuses or changes a stream for it. A device that wants to
/// record without saying so can (iOS's own screen recording, a camera, a modified build); Sill's builds
/// always say so. The log is kept from a device that flips the field: at most one line per connection
/// every `lineSpacing`, the changes in between counted in the next line. Pure: Tests/checks/recording-notice.
package enum RecordingNotice {
    /// `WindowList.recordings` from this host: 1, its menu and its log say that a device is recording.
    package static let generation = 1

    /// The least time between two of one connection's lines, but for the one as it closes.
    package static let lineSpacing: TimeInterval = 10

    /// What a line says of the device: it started, it stopped, or its connection closed while it recorded.
    package enum Event: Equatable, Sendable { case started, stopped, left }

    /// One line: the event, and how many of the device's changes since the line before this one does not
    /// say itself (they came within `lineSpacing` and were held back).
    package struct Line: Equatable, Sendable {
        package var event: Event
        package var held: Int
        package init(event: Event, held: Int) { self.event = event; self.held = held }
    }

    /// One connection's lines (the coordinator keeps one per connection, on the main actor).
    package struct Lines: Equatable, Sendable {
        /// Whether the device's last report says it records.
        package private(set) var recording = false
        /// What the log last said of the device: true after a line that it started, false before any line
        /// and after one that it stopped.
        package private(set) var said = false
        /// When the last line was written (seconds on one monotonic clock), nil before the first.
        package private(set) var lastLineAt: TimeInterval?
        /// The device's changes since the last line.
        package private(set) var changes = 0

        package init() {}

        /// One report, at `now`: the line to write, if any. A change is written at once when the last line
        /// is `lineSpacing` or more behind; otherwise it waits, counted, for the first report after that,
        /// which writes the state then (with the changes it did not say), so the log always comes to say
        /// what the device does within `lineSpacing` of its last change.
        package mutating func report(recording now: Bool, at time: TimeInterval) -> Line? {
            if now != recording {
                recording = now
                changes += 1
            }
            guard changes > 0 else { return nil }
            if let last = lastLineAt, time - last < RecordingNotice.lineSpacing { return nil }
            lastLineAt = time
            return line(recording ? .started : .stopped)
        }

        /// The connection closed: its last line, whatever the spacing. While the device recorded, that it
        /// left while recording; else the stop the log has not written yet (or the changes it held back);
        /// else nothing. A second call says nothing.
        package mutating func closed() -> Line? {
            if recording { return line(.left) }
            return changes > 0 ? line(.stopped) : nil
        }

        /// The line saying `event`, and the log brought up to date: a line that says the state the log
        /// did not hold says one of the changes itself, and holds back the rest.
        private mutating func line(_ event: Event) -> Line {
            let says = event != .stopped
            let held = changes - (says != said ? 1 : 0)
            said = event == .started
            recording = event == .left ? false : recording
            changes = 0
            return Line(event: event, held: held)
        }
    }

    /// The log's words: "Recording: iPad (iPad14,1) started recording the stream.", "… stopped recording
    /// the stream.", "… left while recording the stream.", and the changes held back after it, "(3 more
    /// changes since the last line)". `device` is already clean (SafeText.label, or the address).
    package static func text(_ line: Line, device: String) -> String {
        let what: String
        switch line.event {
        case .started: what = "started recording the stream."
        case .stopped: what = "stopped recording the stream."
        case .left: what = "left while recording the stream."
        }
        let more = line.held > 0 ? " (\(line.held) more change\(line.held == 1 ? "" : "s") since the last line)" : ""
        return "Recording: \(device) \(what)\(more)"
    }
}
