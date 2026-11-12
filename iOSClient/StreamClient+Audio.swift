import Foundation
import QuartzCore
import StreamProtocol
import UIKit

// MARK: - The Mac's sound (docs/audio-plan.md §7.5)

extension StreamClient {
    /// Where this device's mute is kept: local, per device, remembered across launches.
    static let soundMutedKey = "Sill.soundMuted"

    /// The Mac has sound: its settings on this connection carry Send Audio, on or off (Sill for Mac with
    /// sound, and SillHost), so the Settings panel's Mute switch shows (Noah, 2026-10-27: Send Audio and
    /// Mute as the panel's switches). Nil from a Mac without sound, and no settings yet, read as no.
    /// Across a move's hand-over, what the last connection said until the new one says
    /// (`soundAcrossMove`), so the switch never blinks out.
    var macHasSound: Bool {
        if let shown = settings.displayed { return shown.sendAudio != nil }
        return soundAcrossMove ?? false
    }

    /// The Settings panel's Mute (This iPad's group), and headphones taken out: mute or unmute this
    /// device alone, at once, without asking the Mac (it keeps sending), and remember it. Main thread.
    func setSoundMuted(_ on: Bool) {
        noteAction()
        guard soundMuted != on else { return }
        soundMuted = on
        UserDefaults.standard.set(on, forKey: Self.soundMutedKey)
        #if DEBUG
        print("audio: Mute \(on ? "on: mutes" : "off: unmutes") this device")
        #endif
    }

    /// Headphones taken out while the sound played (AudioOutput): muted, as a video app pauses, and
    /// said. Main thread.
    func headphonesOut() {
        guard !soundMuted else { return }
        setSoundMuted(true)
        UIAccessibility.post(notification: .announcement, argument: "Sound muted: headphones disconnected.")
    }

    /// A kind 43 on the session's connection, handed to the sound's queue as it came. On `queue`.
    func receiveAudio(_ header: StreamHeader, _ data: Data) {
        guard let message = AudioMessage.parse(data) else { return }
        switch message {
        case .format(let f): sound.format(f)
        case .packets(let p): sound.packets(p, stamp: header.timestamp)
        }
    }

    /// For the sound's guard (rule 3): each frame's stamp, taken as it came, on the monotonic clock the
    /// sound's packets are taken on; until the session's first format the output only keeps the last
    /// few, so a session without sound hands its queue nothing. On `queue`.
    func frameForSound(_ header: StreamHeader) {
        sound.frame(stamp: header.timestamp, arrival: CACurrentMediaTime())
    }

    #if DEBUG
    /// `-SillSoundToggle <s>[,<s>…]`: at each of these seconds after the stream screen shows, the panel's
    /// Mute switch is flipped as a tap would flip it (the harness cannot tap); `-SillSoundSwitchAt <s>`
    /// turns it on, then off a second later. Once per launch.
    func runSoundArguments() {
        guard !Self.soundArgumentsRan else { return }
        Self.soundArgumentsRan = true
        let defaults = UserDefaults.standard
        let times = (defaults.string(forKey: "SillSoundToggle") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self else { return }
                print("audio: harness: Mute flipped at \(t) s")
                self.setSoundMuted(!self.soundMuted)
            }
        }
        let at = defaults.double(forKey: "SillSoundSwitchAt")
        if at > 0 {
            for (dt, mute) in [(0.0, true), (1.0, false)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at + dt) { [weak self] in
                    print("audio: harness: Mute turned \(mute ? "on" : "off")")
                    self?.setSoundMuted(mute)
                }
            }
        }
    }
    private static var soundArgumentsRan = false
    #endif
}
