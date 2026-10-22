import Foundation
import Network
import StreamProtocol

// Reach from Anywhere on the device (docs/relay-plan.md): joining a Mac's own tailnet from its QR
// code (the usual way: `pair(link:)`), or over a session pinned to that Mac (a device paired before
// the Mac turned it on), and keeping what it takes to come back (the tailnet's fingerprint and
// relay domain, on the saved Mac). The dial through it is StreamClient+Remote's (`dialSaved`), with
// TailnetController's forwarder as the last candidate. Main thread.
extension StreamClient {
    /// The Mac's verified kind 18 on this session said (or stopped saying) it offers a tailnet.
    /// Saved Mac only, pinned session only (receiveMacInfo has checked both): ask for a key once a
    /// session, unless this device already joined that very tailnet (RelayPolicy.deviceAsks). A Mac
    /// that turned it off keeps the record, so a device that joined comes back when it is on again.
    func relayOffered(_ offered: RelayInfo?, macID: String) {
        guard TailnetController.available, let i = savedMacs.firstIndex(where: { $0.macID == macID }) else { return }
        guard RelayPolicy.deviceAsks(pinned: true, offered: offered, joined: savedMacs[i].relay?.fingerprint,
                                     askedThisSession: relayAsked) else { return }
        relayAsked = true
        send(.relayJoin, payload: Wire.encode(RelayJoin()))
        #if DEBUG
        print("relay: asked \(displayName(macID)) for a key to its tailnet")
        #endif
    }

    /// The tailnet a saved Mac's dial waited for said it was removed (the Mac's Remove, or its
    /// Headscale set up again): forget it there, so the next session asks for a fresh key.
    func relayRemoved(macID: String, fingerprint: String) {
        guard let i = savedMacs.firstIndex(where: { $0.macID == macID }), savedMacs[i].relay?.fingerprint == fingerprint else { return }
        savedMacs[i].relay = nil
        persistSavedMacs()
    }

    /// Kind 60 on this session: join the tailnet with its key, and keep the tailnet on the saved Mac
    /// (never the key). Only for the tailnet this session's Mac offers in its signed kind 18
    /// (RelayPolicy.deviceTakes).
    func receiveRelayInvite(_ invite: RelayInvite) {
        guard let v = macInfoVerified, let i = savedMacs.firstIndex(where: { $0.macID == v.info.macID && $0.fingerprintData == v.fingerprint }),
              RelayPolicy.deviceTakes(invite, asked: relayAsked, offered: v.info.relay) else { return }
        joinRelay(invite, macID: savedMacs[i].macID)
    }

    /// Joins the tailnet `invite` names with its key, for the Mac `macID`. Kept on that saved Mac
    /// only once the join runs (TailnetController.onJoined): a join that fails (no network within the
    /// key's ten minutes, the relay down) is asked for again at the next session, as is a tailnet this
    /// device was removed from (`relayRemoved`). From a QR code the Mac may not be saved yet: the
    /// pairing keeps it then (`paired`), if the tailnet already runs.
    func joinRelay(_ invite: RelayInvite, macID: String) {
        TailnetController.shared.onJoined = { [weak self] fingerprint, ok in
            guard let self, fingerprint == invite.relay.fingerprint else { return }
            #if DEBUG
            print("relay: \(ok ? "joined" : "couldn't join") \(self.displayName(macID))'s tailnet")
            #endif
            guard let j = self.savedMacs.firstIndex(where: { $0.macID == macID }) else { return }
            let next: RelayInfo? = ok ? invite.relay : nil
            if self.savedMacs[j].relay != next {
                self.savedMacs[j].relay = next
                self.persistSavedMacs()
            }
        }
        TailnetController.shared.start(invite.relay, key: invite.key)
        #if DEBUG
        print("relay: joining \(displayName(macID))'s tailnet through \(invite.relay.domain)")
        #endif
    }
}
