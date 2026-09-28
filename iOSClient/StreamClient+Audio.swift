import Foundation
import QuartzCore
import StreamProtocol
import UIKit

// MARK: - The Mac's sound (docs/audio-plan.md §7.5)

extension StreamClient {
    /// Where this device's mute is kept: local, per device, remembered across launches.
    static let soundMutedKey = "Sill.soundMuted"

    /// The Mac sends its sound (Send Audio on, as its settings on this connection say): the Sound
    /// button shows, and the panel's Sound switch. Nil from a Mac without sound reads as no.
    var soundAvailable: Bool { settings.displayed?.sendAudio == true }

    /// The Sound button and switch: mute or unmute this device alone, at once, without asking the Mac
    /// (it keeps sending), and remember it. Main thread.
    func setSoundMuted(_ on: Bool) {
        noteAction()
        guard soundMuted != on else { return }
        soundMuted = on
        UserDefaults.standard.set(on, forKey: Self.soundMutedKey)
        #if DEBUG
        print("audio: the Sound control \(on ? "mutes" : "unmutes") this device")
        #endif
    }

    func toggleSound() { setSoundMuted(!soundMuted) }

    /// Headphones taken out while the sound played (AudioOutput): muted, as a video app pauses, and
    /// said. Main thread.
    func headphonesOut() {
        guard !soundMuted else { return }
        setSoundMuted(true)
        UIAccessibility.post(notification: .announcement, argument: "Sound muted: headphones disconnected.")
    }

    /// A kind 29 on the session's connection, handed to the sound's queue as it came. On `queue`.
    func receiveAudio(_ header: StreamHeader, _ data: Data) {
        guard let message = AudioMessage.parse(data) else { return }
        switch message {
        case .format(let f): sound.format(f)
        case .packets(let p): sound.packets(p, stamp: header.timestamp)
        }
    }

    /// For the sound's guard (rule 3): each frame's stamp, taken as it came, on the monotonic clock the
    /// sound's packets are taken on. On `queue`.
    func frameForSound(_ header: StreamHeader) {
        sound.frame(stamp: header.timestamp, arrival: CACurrentMediaTime())
    }

    #if DEBUG
    /// `-SillSoundToggle <s>[,<s>…]`: at each of these seconds after the stream screen shows, the Sound
    /// control is used as a tap would use it (the harness cannot tap); `-SillSoundSwitchAt <s>` the
    /// panel's switch, off then on, a second apart. Once per launch.
    func runSoundArguments() {
        guard !Self.soundArgumentsRan else { return }
        Self.soundArgumentsRan = true
        let defaults = UserDefaults.standard
        let times = (defaults.string(forKey: "SillSoundToggle") ?? "")
            .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 >= 0 }
        for t in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                guard let self else { return }
                print("audio: harness: the Sound button tapped at \(t) s")
                self.toggleSound()
            }
        }
        let at = defaults.double(forKey: "SillSoundSwitchAt")
        if at > 0 {
            for (dt, on) in [(0.0, false), (1.0, true)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at + dt) { [weak self] in
                    print("audio: harness: the Sound switch turned \(on ? "on" : "off")")
                    self?.setSoundMuted(!on)
                }
            }
        }
    }
    private static var soundArgumentsRan = false
    #endif
}
