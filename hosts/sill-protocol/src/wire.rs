//! The 14-byte header and the message kinds (StreamMessage.swift).
//!
//! Header, big endian: kind (1) · timestamp (8, an IEEE double: the host's wall clock in seconds
//! since 1970) · isKeyframe (1, 1 or 0) · payload length (4).

use std::time::{SystemTime, UNIX_EPOCH};

/// The header's length in bytes.
pub const HEADER_LEN: usize = 14;

/// Any client → host message, on both doors. The largest real one is a few hundred bytes.
pub const MAX_CLIENT_PAYLOAD: usize = 1 << 20;
/// The one message of a pairing connection (kind 19).
pub const MAX_PAIRING_PAYLOAD: usize = 4096;
/// A video frame as a device accepts it.
pub const MAX_FRAME_PAYLOAD: usize = 32 << 20;
/// Any other host → device message (window lists, icons, thumbnails, the app list).
pub const MAX_OTHER_HOST_PAYLOAD: usize = 4 << 20;

/// `SillProtocol.current`: the wire's generation.
pub const PROTOCOL_CURRENT: i64 = 1;

/// The message kinds, numbered as StreamMessageKind. A kind this build does not know reads as
/// `Unknown(raw)` and is skipped by readers, never a reason to stop reading.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Kind {
    ParameterSets,
    Frame,
    WindowList,
    Thumbnail,
    AppIcon,
    AppList,
    SelectSource,
    LaunchApp,
    Input,
    Viewport,
    Ping,
    Pong,
    ClientStats,
    Tick,
    CursorShape,
    WindowCommand,
    HostSettings,
    ChangeSettings,
    MacInfo,
    PairRequest,
    PairResult,
    PairingWanted,
    Goodbye,
    Hello,
    MacMenu,
    PressMenuItem,
    MacPointer,
    FetchMenu,
    Gesture,
    Unknown(u8),
}

impl Kind {
    pub fn from_u8(v: u8) -> Kind {
        use Kind::*;
        match v {
            0 => ParameterSets,
            1 => Frame,
            2 => WindowList,
            3 => Thumbnail,
            4 => AppIcon,
            5 => AppList,
            6 => SelectSource,
            7 => LaunchApp,
            8 => Input,
            9 => Viewport,
            10 => Ping,
            11 => Pong,
            12 => ClientStats,
            13 => Tick,
            14 => CursorShape,
            15 => WindowCommand,
            16 => HostSettings,
            17 => ChangeSettings,
            18 => MacInfo,
            19 => PairRequest,
            20 => PairResult,
            21 => PairingWanted,
            22 => Goodbye,
            23 => Hello,
            24 => MacMenu,
            25 => PressMenuItem,
            26 => MacPointer,
            27 => FetchMenu,
            28 => Gesture,
            other => Unknown(other),
        }
    }

    pub fn as_u8(self) -> u8 {
        use Kind::*;
        match self {
            ParameterSets => 0,
            Frame => 1,
            WindowList => 2,
            Thumbnail => 3,
            AppIcon => 4,
            AppList => 5,
            SelectSource => 6,
            LaunchApp => 7,
            Input => 8,
            Viewport => 9,
            Ping => 10,
            Pong => 11,
            ClientStats => 12,
            Tick => 13,
            CursorShape => 14,
            WindowCommand => 15,
            HostSettings => 16,
            ChangeSettings => 17,
            MacInfo => 18,
            PairRequest => 19,
            PairResult => 20,
            PairingWanted => 21,
            Goodbye => 22,
            Hello => 23,
            MacMenu => 24,
            PressMenuItem => 25,
            MacPointer => 26,
            FetchMenu => 27,
            Gesture => 28,
            Unknown(v) => v,
        }
    }
}

/// A parsed header.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Header {
    pub kind: Kind,
    /// Host wall clock, seconds since 1970 (approximate across devices).
    pub timestamp: f64,
    pub keyframe: bool,
    pub payload_len: u32,
}

impl Header {
    /// Parses the first 14 bytes. `isKeyframe` is true only for the byte 1, as Swift reads it.
    pub fn parse(b: &[u8]) -> Option<Header> {
        if b.len() < HEADER_LEN {
            return None;
        }
        let ts = f64::from_bits(u64::from_be_bytes(b[1..9].try_into().ok()?));
        Some(Header {
            kind: Kind::from_u8(b[0]),
            timestamp: ts,
            keyframe: b[9] == 1,
            payload_len: u32::from_be_bytes(b[10..14].try_into().ok()?),
        })
    }

    pub fn encode(&self) -> [u8; HEADER_LEN] {
        let mut h = [0u8; HEADER_LEN];
        h[0] = self.kind.as_u8();
        h[1..9].copy_from_slice(&self.timestamp.to_bits().to_be_bytes());
        h[9] = if self.keyframe { 1 } else { 0 };
        h[10..14].copy_from_slice(&self.payload_len.to_be_bytes());
        h
    }
}

/// The host's wall clock as the header carries it.
pub fn now_seconds() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

/// One whole message: header then payload (`StreamMessage.serialized()`).
pub fn message(kind: Kind, timestamp: f64, keyframe: bool, payload: &[u8]) -> Vec<u8> {
    let mut v = Vec::with_capacity(HEADER_LEN + payload.len());
    v.extend_from_slice(
        &Header { kind, timestamp, keyframe, payload_len: payload.len() as u32 }.encode(),
    );
    v.extend_from_slice(payload);
    v
}

/// A message stamped now, not a keyframe.
pub fn message_now(kind: Kind, payload: &[u8]) -> Vec<u8> {
    message(kind, now_seconds(), false, payload)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn header_round_trip_and_python_struct_layout() {
        // struct.pack(">BdBI", 6, 1234.5, 0, 14), as sillclient.py writes it.
        let mut bytes = vec![6u8];
        bytes.extend_from_slice(&1234.5f64.to_bits().to_be_bytes());
        bytes.push(0);
        bytes.extend_from_slice(&14u32.to_be_bytes());
        let h = Header::parse(&bytes).unwrap();
        assert_eq!(h.kind, Kind::SelectSource);
        assert_eq!(h.timestamp, 1234.5);
        assert!(!h.keyframe);
        assert_eq!(h.payload_len, 14);
        assert_eq!(h.encode().to_vec(), bytes);
    }

    #[test]
    fn every_kind_round_trips_and_unknown_is_kept() {
        for v in 0..=255u8 {
            assert_eq!(Kind::from_u8(v).as_u8(), v);
        }
        assert_eq!(Kind::from_u8(29), Kind::Unknown(29));
        assert_eq!(Kind::from_u8(200), Kind::Unknown(200));
        assert_eq!(Kind::Gesture.as_u8(), 28);
        assert_eq!(Kind::Hello.as_u8(), 23);
    }

    #[test]
    fn keyframe_byte_only_one_counts() {
        let mut b = message(Kind::Frame, 1.0, true, b"x");
        assert!(Header::parse(&b).unwrap().keyframe);
        b[9] = 2;
        assert!(!Header::parse(&b).unwrap().keyframe);
    }

    #[test]
    fn swift_header_sample() {
        // The first bytes of a parameter-sets message captured from SillHost --synthetic:
        // kind 0, isKeyframe 1, 73 payload bytes.
        let mut b = vec![0u8];
        b.extend_from_slice(&1_792_000_000.25f64.to_bits().to_be_bytes());
        b.push(1);
        b.extend_from_slice(&73u32.to_be_bytes());
        let h = Header::parse(&b).unwrap();
        assert_eq!(h.kind, Kind::ParameterSets);
        assert!(h.keyframe);
        assert_eq!(h.payload_len, 73);
    }
}
