//! Who the home door admits (OriginPolicy.swift): loopback, link-local addresses, and this
//! machine's own networks. A source through a VPN or from the internet is refused before a byte
//! is sent, and only counted (one line a minute).

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Origin {
    Loopback,
    /// Link-local (the USB cable's network, AWDL-like links, zero-conf).
    Direct,
    /// One of this machine's own networks.
    Lan,
    Vpn,
    Internet,
}

impl Origin {
    pub fn home_admits(self) -> bool {
        matches!(self, Origin::Loopback | Origin::Direct | Origin::Lan)
    }
}

fn is_vpn_interface(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    ["utun", "tun", "tap", "wg", "tailscale", "zt", "ppp", "ipsec", "nordlynx", "proton", "mullvad"]
        .iter()
        .any(|p| n.starts_with(p))
}

fn in_cgnat(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 100 && (o[1] & 0xC0) == 64
}

fn v4_mask_match(a: Ipv4Addr, b: Ipv4Addr, mask: Ipv4Addr) -> bool {
    u32::from(a) & u32::from(mask) == u32::from(b) & u32::from(mask)
}

fn v6_mask_match(a: Ipv6Addr, b: Ipv6Addr, mask: Ipv6Addr) -> bool {
    let (a, b, m) = (a.octets(), b.octets(), mask.octets());
    (0..16).all(|i| a[i] & m[i] == b[i] & m[i])
}

/// Classifies a peer address against this machine's interfaces.
pub fn classify(peer: IpAddr) -> Origin {
    let peer = match peer {
        IpAddr::V6(v6) => v6.to_ipv4_mapped().map(IpAddr::V4).unwrap_or(IpAddr::V6(v6)),
        other => other,
    };
    if peer.is_loopback() {
        return Origin::Loopback;
    }
    match peer {
        IpAddr::V4(v4) if v4.is_link_local() => return Origin::Direct,
        IpAddr::V6(v6) if (v6.segments()[0] & 0xFFC0) == 0xFE80 => return Origin::Direct,
        IpAddr::V4(v4) if in_cgnat(v4) => return Origin::Vpn,
        _ => {}
    }
    let Ok(ifaces) = if_addrs::get_if_addrs() else { return Origin::Internet };
    for i in &ifaces {
        let local = i.ip();
        if local == peer {
            // One of this machine's own addresses.
            return if is_vpn_interface(&i.name) { Origin::Vpn } else { Origin::Loopback };
        }
        let same = match (&i.addr, peer) {
            (if_addrs::IfAddr::V4(a), IpAddr::V4(p)) => v4_mask_match(a.ip, p, a.netmask),
            (if_addrs::IfAddr::V6(a), IpAddr::V6(p)) => v6_mask_match(a.ip, p, a.netmask),
            _ => false,
        };
        if same {
            return if is_vpn_interface(&i.name) { Origin::Vpn } else { Origin::Lan };
        }
    }
    Origin::Internet
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basics() {
        assert_eq!(classify("127.0.0.1".parse().unwrap()), Origin::Loopback);
        assert_eq!(classify("::1".parse().unwrap()), Origin::Loopback);
        assert_eq!(classify("::ffff:127.0.0.1".parse().unwrap()), Origin::Loopback);
        assert_eq!(classify("169.254.3.4".parse().unwrap()), Origin::Direct);
        assert_eq!(classify("fe80::1".parse().unwrap()), Origin::Direct);
        assert_eq!(classify("100.101.102.103".parse().unwrap()), Origin::Vpn);
        assert_eq!(classify("8.8.8.8".parse().unwrap()), Origin::Internet);
        assert!(!Origin::Vpn.home_admits());
        assert!(Origin::Lan.home_admits());
    }
}
