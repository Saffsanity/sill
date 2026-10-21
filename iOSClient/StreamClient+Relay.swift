import Foundation
import Network
import StreamProtocol

// Reach from Anywhere on the device (docs/relay-plan.md): joining a saved Mac's own tailnet over a
// session pinned to that Mac, and keeping what it takes to come back (the tailnet's fingerprint and
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

    /// Kind 60 on this session: join the tailnet with its key, and keep the tailnet on the saved Mac
    /// (never the key). Only for the tailnet this session's Mac offers in its signed kind 18
    /// (RelayPolicy.deviceTakes).
    func receiveRelayInvite(_ invite: RelayInvite) {
        guard let v = macInfoVerified, let i = savedMacs.firstIndex(where: { $0.macID == v.info.macID && $0.fingerprintData == v.fingerprint }),
              RelayPolicy.deviceTakes(invite, asked: relayAsked, offered: v.info.relay) else { return }
        savedMacs[i].relay = invite.relay
        persistSavedMacs()
        TailnetController.shared.start(invite.relay, key: invite.key)
        #if DEBUG
        print("relay: joining \(displayName(v.info.macID))'s tailnet through \(invite.relay.domain)")
        #endif
    }
}
