import Foundation

/// Picture in Picture (issue #291, docs/picture-in-picture-plan.md): when Sill lets iOS take a window's
/// picture into its Picture in Picture window as the person leaves Sill, what counts as someone watching or
/// hearing while it shows, what Sill keeps doing by itself meanwhile, and what ends it. PictureInPicture.swift
/// carries it out with AVKit; nothing here knows of AVKit, UIKit or the clock.
///
/// - Offered (`qualifies`, `offered`): the switch on, iOS supporting it, the session connected and streaming
///   a source whose picture has come, no cover over it (a locked Mac, another user, Unlocking…), and this the
///   window Sill offers it for (`chosen`). Sill never starts it itself: iOS does, as the person leaves (App
///   Review rejects an app that starts it on its way to the background).
/// - One window (`chosen`): of Sill's windows in front, the one used last that qualifies; while none is in
///   front (Sill on its way out, or away), the last choice stands, so the scene's own activation never takes
///   the offer away while iOS decides.
/// - Watched (`pictureWatched`), heard (`soundHeard`), running (`running`): Picture in Picture counts as the
///   foreground for the picture's keyframe asks and for the Mac's sound while it plays, and for what Sill
///   does by itself in the foreground (the reconnect's dials, a browser made again) while it is active,
///   paused or not.
/// - Paused (`frozen`, `pauseEnds`): the picture frozen and silent, the connection kept; ten minutes paused
///   ends it.
/// - Ends (`stops`): the session's end, the window back in front, the device's lock, ten minutes paused.
/// - No input (`holdsDeviceInput`): the device's own pointer move waits while the picture shows only there.
///
/// Pure: Foundation only, checked with swiftc (Tests/checks/picture-in-picture). Times are systemUptime.
enum PictureInPicturePolicy {
    /// The switch's default, Settings › This iPad (This iPhone) › Picture in Picture: off until Noah has
    /// tried it (the plan's open question 1), since it keeps the radio, the decoder and the Mac's stream
    /// running while Sill is in the background. The one place the default is written.
    static let defaultOn = false

    /// Paused this long, Picture in Picture stops: nobody is watching, and a paused window must not keep a
    /// Mac streaming all night (DeviceIdlePolicy.idleLimit's ten minutes, the same thought).
    static let pausedLimit: Double = 600

    /// Picture in Picture as AVKit has said it is, for one window's session.
    struct State: Equatable {
        /// From `willStart` to `didStop`, or to a failed start: the picture is in iOS's window, or on its way.
        var active = false
        /// The person paused it in that window (the playback delegate's `setPlaying(false)`); play ends it,
        /// and so does the end of Picture in Picture.
        var paused = false

        static let off = State()
    }

    // MARK: - Offered

    /// One window's session as it is now: everything but the choice among windows.
    struct Session: Equatable {
        /// Settings › This iPad › Picture in Picture.
        var switchOn: Bool
        /// iOS supports Picture in Picture on this device (AVPictureInPictureController).
        var supported: Bool
        /// The session is connected (StreamClient.connected).
        var connected: Bool
        /// A source streams: a window or the Desktop (StreamClient.active).
        var streaming: Bool
        /// Its picture has come: the stream's format is known (StreamClient.videoSize).
        var pictureCame: Bool
        /// A cover hides the picture in Sill: the Mac locked, another user on it, or Unlocking…
        /// (StreamClient.lockShade).
        var covered: Bool
    }

    /// Whether this session's picture may go into Picture in Picture, its window chosen.
    static func qualifies(_ s: Session) -> Bool {
        s.switchOn && s.supported && s.connected && s.streaming && s.pictureCame && !s.covered
    }

    /// Whether iOS may take this window's picture into Picture in Picture as the person leaves Sill
    /// (`canStartPictureInPictureAutomaticallyFromInline`).
    static func offered(_ s: Session, chosen: Bool) -> Bool { chosen && qualifies(s) }

    /// One of Sill's windows, for the choice.
    struct Window: Equatable {
        /// Which window (the caller's own numbering).
        var id: Int
        /// Its scene is foreground active: the person can see it.
        var foregroundActive: Bool
        /// Its session qualifies (`qualifies`).
        var qualifies: Bool
        /// When the person last used it (DeviceIdlePolicy.lastUse); nil when never.
        var lastUsedAt: Double?
    }

    /// The window whose session Picture in Picture belongs to: of the windows in front whose session
    /// qualifies, the one used last (a window never used counts as used before every other; among windows
    /// used at the same moment, the first listed). While none of Sill's windows is in front, `previous`,
    /// as long as it is still listed: iOS decides as Sill leaves, after its scenes stop being active, and the
    /// choice made while the person was in Sill must stand then. Nil: none.
    static func chosen(_ windows: [Window], previous: Int?) -> Int? {
        guard windows.contains(where: \.foregroundActive) else {
            guard let previous, windows.contains(where: { $0.id == previous }) else { return nil }
            return previous
        }
        var best: Window?
        for w in windows where w.foregroundActive && w.qualifies {
            guard let b = best else { best = w; continue }
            if (w.lastUsedAt ?? -.infinity) > (b.lastUsedAt ?? -.infinity) { best = w }
        }
        return best?.id
    }

    // MARK: - While it shows

    /// The picture is in front of someone: its window's scene is foreground active, or Picture in Picture
    /// shows it playing. KeyframeRecovery asks the Mac for a keyframe for an interrupted picture only then.
    static func pictureWatched(sceneForegroundActive: Bool, pip: State) -> Bool {
        sceneForegroundActive || (pip.active && !pip.paused)
    }

    /// The Mac's sound is heard: the app and this window's scene in the foreground, as before Picture in
    /// Picture, or Picture in Picture playing. (Muted and Send Audio are the sound's own: AudioOutput.)
    static func soundHeard(appForeground: Bool, sceneForeground: Bool, pip: State) -> Bool {
        (appForeground && sceneForeground) || (pip.active && !pip.paused)
    }

    /// Sill runs as in the foreground for what it does by itself only there (the automatic reconnect's dials
    /// of a listed row, a failed browser made again): the app is not in the background, or Picture in Picture
    /// keeps it running, paused or not. A stay in the background that this covered throughout is no trip to
    /// the background: iOS never suspended the app, so the browsers need not be made again on the return.
    static func running(appForeground: Bool, pip: State) -> Bool { appForeground || pip.active }

    /// The picture is frozen: Picture in Picture is paused, so no frame goes onto the layer, which keeps its
    /// last picture; the connection keeps reading.
    static func frozen(_ pip: State) -> Bool { pip.active && pip.paused }

    /// Whether a paused Picture in Picture has been paused long enough to stop: `pausedLimit` since
    /// `pausedAt`, still paused. (A clock gone back reads as a pause just begun.)
    static func pauseEnds(pip: State, pausedAt: Double?, now: Double) -> Bool {
        guard frozen(pip), let pausedAt else { return false }
        return now - pausedAt >= pausedLimit
    }

    /// The device's own input (its pointer's move to the middle of a new frame) waits: Picture in Picture
    /// shows the picture and its window is not in front, so the person is not at it.
    static func holdsDeviceInput(sceneForegroundActive: Bool, pip: State) -> Bool {
        pip.active && !sceneForegroundActive
    }

    /// What ends Picture in Picture.
    enum Ending: Equatable {
        /// The session ended: a goodbye, the Mac quitting Sill, a loss no move carries, Disconnect.
        case sessionEnded
        /// Its window's scene is foreground active again: the person is back in Sill.
        case backInFront
        /// The device locked (iOS says protected data is about to go, which needs a passcode).
        case deviceLocked
        /// Paused for `pausedLimit` (`pauseEnds`).
        case pausedTooLong
    }

    /// Whether `ending` stops Picture in Picture now. A move to another path is none of these: the session
    /// goes on, and so does Picture in Picture.
    static func stops(_ ending: Ending, pip: State) -> Bool {
        switch ending {
        case .sessionEnded, .backInFront, .deviceLocked: return pip.active
        case .pausedTooLong: return frozen(pip)
        }
    }

    // MARK: - One window's Picture in Picture over time

    /// One window's Picture in Picture across AVKit's callbacks and Sill's own endings: its state, when it
    /// was paused, and what each event asks of PictureInPicture.swift, which only carries the answers out
    /// (AVKit's calls, the frozen picture, the sound, the next look). Main thread there.
    struct Lifecycle: Equatable {
        private(set) var state = State.off
        /// When the person paused it (`setPlaying(false)`); nil while it plays or is off.
        private(set) var pausedAt: Double?

        /// What the glue does after an event.
        struct Effects: Equatable {
            /// Stop Picture in Picture (AVPictureInPictureController.stopPictureInPicture); AVKit's didStop follows.
            var stop = false
            /// Tell AVKit the playback state changed (invalidatePlaybackState), after a play or a pause.
            var invalidate = false
            /// Look again at this time (`tick`): a pause's end.
            var lookAt: Double?

            static let none = Effects()
        }

        /// AVKit's willStart (iOS started it as the person left Sill, or DEBUG's stand-in did): it plays.
        mutating func willStart() -> Effects {
            guard !state.active else { return .none }
            state = State(active: true, paused: false)
            pausedAt = nil
            return .none
        }

        /// AVKit's didStop, or a failed start: off, whatever it was.
        mutating func ended() -> Effects {
            state = .off
            pausedAt = nil
            return .none
        }

        /// The playback delegate's setPlaying, from the window's play and pause button: a pause freezes the
        /// picture and the sound and is looked at again when it has lasted `pausedLimit`; a play lets the live
        /// picture back. Only while it is active (AVKit asks nothing else); a repeat of what it is already
        /// changes nothing but AVKit's view of it.
        mutating func setPlaying(_ playing: Bool, now: Double) -> Effects {
            guard state.active else { return .none }
            var effects = Effects(invalidate: true)
            if playing {
                state.paused = false
                pausedAt = nil
            } else if !state.paused {
                state.paused = true
                pausedAt = now
            }
            if let pausedAt { effects.lookAt = pausedAt + PictureInPicturePolicy.pausedLimit }
            return effects
        }

        /// One of Sill's endings: stops it when `stops` says so.
        mutating func ending(_ ending: Ending) -> Effects {
            Effects(stop: PictureInPicturePolicy.stops(ending, pip: state))
        }

        /// A look at the clock: a pause that has lasted `pausedLimit` stops it; one that has not is looked
        /// at again then.
        mutating func tick(now: Double) -> Effects {
            if PictureInPicturePolicy.pauseEnds(pip: state, pausedAt: pausedAt, now: now) {
                return ending(.pausedTooLong)
            }
            guard PictureInPicturePolicy.frozen(state), let pausedAt else { return .none }
            return Effects(lookAt: pausedAt + PictureInPicturePolicy.pausedLimit)
        }
    }

    // MARK: - Words

    enum Copy {
        /// The switch's title, in the Settings panel's This iPad (This iPhone) group.
        static let title = "Picture in Picture"

        /// Under the switch: what it does, what the window shows, how to come back, and iOS's own switch,
        /// without which iOS never starts it (the plan's open question 2).
        static func footnote(mac: String) -> String {
            "Leave Sill while \(mac)’s picture shows, and it keeps playing in a small window over your other apps, "
                + "with its sound when Send Audio is on. That window only shows the picture: tap it to come back to Sill. "
                + "iOS starts it only while Start PiP Automatically is on, in Settings › General › Picture in Picture."
        }
    }
}
