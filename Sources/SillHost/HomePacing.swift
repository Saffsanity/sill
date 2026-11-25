import Foundation

/// Frame pacing for a client at home (`!client.route.isRemote`: Wi-Fi, Personal Hotspot over a
/// link-local address, Ethernet, peer-to-peer Wi-Fi, USB cable, loopback).
///
/// Steady state keeps the two-message bound (`maxInflight = 2`): latency beats quality, so a third
/// unacknowledged message drops the frame rather than building a standing queue. Four rules prevent
/// the keyframe livelock seen on Personal Hotspot and congested Wi-Fi (where dropping a delta asked
/// for an immediate keyframe, and the next frame sent that keyframe unconditionally onto the same
/// full queue, encoding and queueing ~28 keyframes a second up to multi-second RTTs):
/// - Parameter sets go out paired with each admitted home keyframe (`sendParameterSets: true`),
///   never ahead of `decide` (where they could raise `inflight` past `maxInflight` and drop their
///   own keyframe or flush the display on a dropped keyframe). Only the first keyframe of a
///   connection or restarted stream (`awaitingFirstKeyframe`) bypasses backpressure; every later
///   recovery keyframe goes out only when no keyframe or video frame remains unacknowledged
///   (`keyframesInFlight == 0`, `inflightFrames == 0`) and `pendingBytes <= backlogBudget`.
/// - Dropping a frame sets `needsKeyframe` without asking the encoder while backed up. A recovery
///   keyframe is asked for once `inflightFrames == 0` and `pendingBytes <= idleBytes` (above
///   `audioCapHome`'s ~19 KB so live audio never starves recovery, while connect catalog bursts and
///   stalled frames drain first), spaced by `keyframeSpacing` across home clients and waiting up to
///   `inFlightKeyframeWait` while another home client is still taking the previous keyframe so two
///   slow home clients on a still window synchronize instead of ping-ponging. Because eligibility
///   follows `needsKeyframe && !awaitingFirstKeyframe` rather than a one-shot latch, a request the
///   encoder drops or refuses retries on the next due check.
/// - While a keyframe is still being taken by `NWConnection` (`keyframesInFlight > 0`), follower
///   deltas reference it and pass up to `holdCap` beyond the in-flight keyframes rather than
///   dropping on the third message behind a large Retina keyframe; another non-first keyframe is
///   never stacked onto one still in flight. When the last in-flight keyframe finishes,
///   `backlogFloor` captures the remaining follower bytes and follows `pendingBytes` down on every
///   completion (`bytesTaken`) and frame (`decide`) until `0`, where `inflight > maxInflight`
///   governs again.
package struct HomePacing: Equatable {
    package static let maxInflight = 2
    package static let backlogBudget = 256 * 1024
    package static let holdCap = 512 * 1024
    package static let backlogSlack = 128 * 1024
    package static let idleBytes = 32 * 1024
    package static let keyframeSpacing: TimeInterval = 0.25
    package static let inFlightKeyframeWait: TimeInterval = 4.0

    /// Shared monotonic spacing across home clients for encoder keyframe requests (`onKeyframeNeeded`).
    package struct Requests: Equatable {
        package private(set) var lastRequestAt: TimeInterval?
        package private(set) var lastKeyframeAt: TimeInterval?

        package init() {}

        package func due(now: TimeInterval, otherHomeKeyframeInFlight: Bool = false) -> Bool {
            if let last = lastRequestAt, now - last < HomePacing.keyframeSpacing {
                return false
            }
            if otherHomeKeyframeInFlight, let kf = lastKeyframeAt,
               now - kf < HomePacing.inFlightKeyframeWait {
                return false
            }
            return true
        }

        package mutating func recordRequest(now: TimeInterval) {
            lastRequestAt = now
        }

        package mutating func recordKeyframe(now: TimeInterval) {
            lastKeyframeAt = now
        }
    }

    /// What `decide` tells `StreamServer` to do with one video frame for one home client.
    package enum Decision: Equatable {
        /// Send `lastParameterSets` first when `sendParameterSets` is true (every admitted
        /// keyframe), then send the frame (`net.sent`, `sentThisSecond += 1`).
        case send(sendParameterSets: Bool)
        /// Skip the frame while already waiting for a keyframe (`net.waitKey`; counts in
        /// `withheldThisSecond` when `countWithheld` is true, never before the stream's first
        /// keyframe). `askKeyframe` is true when the client's queue is idle and `mayAskKeyframe`
        /// allowed a request.
        case waitKey(countWithheld: Bool, askKeyframe: Bool)
        /// Drop the frame because the queue is backed up (`net.dropped`, `withheldThisSecond += 1`).
        case drop
    }

    package private(set) var keyframesInFlight = 0
    package private(set) var keyframeBytesInFlight = 0
    package private(set) var backlogFloor = 0

    package init() {}

    package mutating func decide(
        isKeyframe: Bool,
        hasParameterSets: Bool,
        needsKeyframe: inout Bool,
        awaitingFirstKeyframe: inout Bool,
        inflight: Int,
        inflightFrames: Int,
        pendingBytes: Int,
        mayAskKeyframe: Bool
    ) -> Decision {
        backlogFloor = min(backlogFloor, max(0, pendingBytes))
        if needsKeyframe {
            guard isKeyframe else {
                let countWithheld = !awaitingFirstKeyframe
                let ask = !awaitingFirstKeyframe
                    && inflightFrames == 0
                    && pendingBytes <= Self.idleBytes
                    && mayAskKeyframe
                return .waitKey(countWithheld: countWithheld, askKeyframe: ask)
            }
            guard hasParameterSets else {
                return .waitKey(countWithheld: !awaitingFirstKeyframe, askKeyframe: false)
            }
            let readyForRecovery = keyframesInFlight == 0
                && inflightFrames == 0
                && pendingBytes <= Self.backlogBudget
            guard awaitingFirstKeyframe || readyForRecovery else {
                return .waitKey(countWithheld: true, askKeyframe: false)
            }
            needsKeyframe = false
            awaitingFirstKeyframe = false
            return .send(sendParameterSets: true)
        }

        if isKeyframe, !hasParameterSets {
            needsKeyframe = true
            return .waitKey(countWithheld: true, askKeyframe: false)
        }

        let tooMuch: Bool
        if isKeyframe {
            tooMuch = keyframesInFlight > 0
                || inflight > Self.maxInflight
                || pendingBytes > Self.backlogBudget
        } else if keyframesInFlight > 0 {
            tooMuch = pendingBytes - keyframeBytesInFlight > Self.holdCap
        } else {
            tooMuch = inflight > Self.maxInflight
                && (backlogFloor == 0 || pendingBytes > backlogFloor + Self.backlogSlack)
        }
        if tooMuch {
            needsKeyframe = true
            return .drop
        }
        return .send(sendParameterSets: isKeyframe)
    }

    /// Whether the 1 s sweep should ask for a recovery keyframe on this home client's behalf once
    /// the window has gone still (or an earlier request produced no keyframe).
    package func canAskOnSweep(
        needsKeyframe: Bool,
        awaitingFirstKeyframe: Bool,
        inflightFrames: Int,
        pendingBytes: Int
    ) -> Bool {
        needsKeyframe && !awaitingFirstKeyframe
            && inflightFrames == 0 && pendingBytes <= Self.idleBytes
    }

    /// Records a sent keyframe on the network queue.
    package mutating func keyframeSent(bytes: Int) {
        keyframesInFlight += 1
        keyframeBytesInFlight += bytes
    }

    /// Follows `pendingBytes` down on every send completion (video, catalog, or audio), so a queue
    /// that empties between video frames clears `backlogFloor` immediately.
    package mutating func bytesTaken(pendingBytes: Int) {
        backlogFloor = min(backlogFloor, max(0, pendingBytes))
    }

    /// Marks one in-flight keyframe taken by `NWConnection`; when the last of them finishes, what
    /// remains in `pendingBytes` is the follower wave's initial `backlogFloor`.
    package mutating func keyframeTaken(bytes: Int, pendingBytes: Int) {
        guard keyframesInFlight > 0 else { return }
        keyframesInFlight -= 1
        keyframeBytesInFlight = max(0, keyframeBytesInFlight - bytes)
        if keyframesInFlight == 0 {
            backlogFloor = max(0, pendingBytes)
        }
    }
}
