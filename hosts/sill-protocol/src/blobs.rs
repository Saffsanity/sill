//! Binary payloads: ParameterSets (kind 0), frames (kind 1), ImageBlob (kinds 3 and 4),
//! CursorShapeBlob (kind 14), and HEVC NAL helpers.

/// HEVC VPS/SPS/PPS plus the NAL length-prefix size (4): `nalLen(1) count(1)` then per set
/// `length(2, BE) bytes`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParameterSets {
    pub nal_unit_header_length: u8,
    pub sets: Vec<Vec<u8>>,
}

impl ParameterSets {
    /// VPS, SPS, PPS with 4-byte NAL length prefixes, as VideoToolbox's sessions give them.
    pub fn new(sets: Vec<Vec<u8>>) -> ParameterSets {
        ParameterSets { nal_unit_header_length: 4, sets }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut d = Vec::with_capacity(2 + self.sets.iter().map(|s| s.len() + 2).sum::<usize>());
        d.push(self.nal_unit_header_length);
        d.push(self.sets.len() as u8);
        for s in &self.sets {
            d.extend_from_slice(&(s.len() as u16).to_be_bytes());
            d.extend_from_slice(s);
        }
        d
    }

    pub fn decode(d: &[u8]) -> Option<ParameterSets> {
        if d.len() < 2 {
            return None;
        }
        let count = d[1] as usize;
        let mut off = 2;
        let mut sets = Vec::with_capacity(count);
        for _ in 0..count {
            if d.len() < off + 2 {
                return None;
            }
            let len = u16::from_be_bytes([d[off], d[off + 1]]) as usize;
            off += 2;
            if d.len() < off + len {
                return None;
            }
            sets.push(d[off..off + len].to_vec());
            off += len;
        }
        Some(ParameterSets { nal_unit_header_length: d[0], sets })
    }
}

/// A frame's payload (kind 1): every NAL unit of one access unit with a 4-byte big-endian length
/// in front, hvcC style.
pub fn frame_payload<T: AsRef<[u8]>>(nals: &[T]) -> Vec<u8> {
    let mut d = Vec::with_capacity(nals.iter().map(|n| n.as_ref().len() + 4).sum());
    for n in nals {
        let n = n.as_ref();
        d.extend_from_slice(&(n.len() as u32).to_be_bytes());
        d.extend_from_slice(n);
    }
    d
}

/// The NAL units of a kind 1 payload (4-byte lengths). None when a length runs past the end.
pub fn split_frame_payload(d: &[u8]) -> Option<Vec<&[u8]>> {
    let mut out = Vec::new();
    let mut off = 0;
    while off < d.len() {
        if d.len() < off + 4 {
            return None;
        }
        let len = u32::from_be_bytes(d[off..off + 4].try_into().ok()?) as usize;
        off += 4;
        if d.len() < off + len {
            return None;
        }
        out.push(&d[off..off + len]);
        off += len;
    }
    Some(out)
}

/// Splits an Annex-B byte stream (3- or 4-byte start codes) into NAL units, start codes removed.
/// Trailing zero bytes of a NAL (the next start code's leading zero) are trimmed.
pub fn split_annex_b(d: &[u8]) -> Vec<&[u8]> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= d.len() {
        if d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1 {
            starts.push(i + 3);
            i += 3;
        } else {
            i += 1;
        }
    }
    let mut out = Vec::with_capacity(starts.len());
    for (k, &s) in starts.iter().enumerate() {
        let mut e = if k + 1 < starts.len() { starts[k + 1] - 3 } else { d.len() };
        while e > s && d[e - 1] == 0 {
            e -= 1;
        }
        if e > s {
            out.push(&d[s..e]);
        }
    }
    out
}

/// The HEVC NAL unit type (`(byte0 >> 1) & 0x3F`).
pub fn hevc_nal_type(nal: &[u8]) -> u8 {
    nal.first().map(|b| (b >> 1) & 0x3F).unwrap_or(255)
}

pub mod nal_type {
    pub const VPS: u8 = 32;
    pub const SPS: u8 = 33;
    pub const PPS: u8 = 34;
    pub const AUD: u8 = 35;
    pub const EOS: u8 = 36;
    pub const EOB: u8 = 37;
    pub const FD: u8 = 38;
    pub const PREFIX_SEI: u8 = 39;
    pub const SUFFIX_SEI: u8 = 40;

    /// IRAP pictures (BLA, IDR, CRA, reserved IRAP): a decoder can start here.
    pub fn is_irap(t: u8) -> bool {
        (16..=23).contains(&t)
    }

    pub fn is_vcl(t: u8) -> bool {
        t < 32
    }
}

/// ImageBlob: thumbnails (kind 3) `windowID(4, BE) + JPEG`, icons (kind 4)
/// `bundleIDLength(2, BE) + bundleID UTF-8 + PNG`.
pub mod image_blob {
    pub fn encode_thumbnail(window_id: u32, jpeg: &[u8]) -> Vec<u8> {
        let mut d = Vec::with_capacity(4 + jpeg.len());
        d.extend_from_slice(&window_id.to_be_bytes());
        d.extend_from_slice(jpeg);
        d
    }

    pub fn decode_thumbnail(d: &[u8]) -> Option<(u32, &[u8])> {
        if d.len() <= 4 {
            return None;
        }
        Some((u32::from_be_bytes(d[0..4].try_into().ok()?), &d[4..]))
    }

    pub fn encode_icon(bundle_id: &str, png: &[u8]) -> Vec<u8> {
        let id = bundle_id.as_bytes();
        let id = &id[..id.len().min(u16::MAX as usize)];
        let mut d = Vec::with_capacity(2 + id.len() + png.len());
        d.extend_from_slice(&(id.len() as u16).to_be_bytes());
        d.extend_from_slice(id);
        d.extend_from_slice(png);
        d
    }

    pub fn decode_icon(d: &[u8]) -> Option<(String, &[u8])> {
        if d.len() <= 2 {
            return None;
        }
        let len = u16::from_be_bytes([d[0], d[1]]) as usize;
        if d.len() <= 2 + len {
            return None;
        }
        let id = String::from_utf8(d[2..2 + len].to_vec()).ok()?;
        Some((id, &d[2 + len..]))
    }
}

/// CursorShapeBlob (kind 14): hotX, hotY, width, height as Float32 big-endian, then the PNG.
pub mod cursor_blob {
    pub fn encode(hot_x: f64, hot_y: f64, width: f64, height: f64, png: &[u8]) -> Vec<u8> {
        let mut d = Vec::with_capacity(16 + png.len());
        for v in [hot_x, hot_y, width, height] {
            d.extend_from_slice(&(v as f32).to_bits().to_be_bytes());
        }
        d.extend_from_slice(png);
        d
    }

    /// (hotX, hotY, width, height, PNG); None for 16 bytes or fewer, as Swift.
    pub fn decode(d: &[u8]) -> Option<(f32, f32, f32, f32, &[u8])> {
        if d.len() <= 16 {
            return None;
        }
        let f = |i: usize| f32::from_bits(u32::from_be_bytes(d[i * 4..i * 4 + 4].try_into().unwrap()));
        Some((f(0), f(1), f(2), f(3), &d[16..]))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A parameter-sets payload captured from SillHost --synthetic (software encoder, 1512×948).
    const SWIFT_PS: &str = "0403001740010c01ffff216000000300b0000003000003007b3c090022420101216000000300b0000003000003007ba002f4803b9f79cf924489bf9713600800084401c0252f053240";

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn parameter_sets_round_trip_swift_bytes() {
        let bytes = hex(SWIFT_PS);
        let ps = ParameterSets::decode(&bytes).unwrap();
        assert_eq!(ps.nal_unit_header_length, 4);
        assert_eq!(ps.sets.len(), 3);
        assert_eq!(hevc_nal_type(&ps.sets[0]), nal_type::VPS);
        assert_eq!(hevc_nal_type(&ps.sets[1]), nal_type::SPS);
        assert_eq!(hevc_nal_type(&ps.sets[2]), nal_type::PPS);
        assert_eq!(ps.encode(), bytes);
        assert_eq!(ParameterSets::decode(&bytes[..10]), None);
    }

    #[test]
    fn frame_framing_and_annex_b() {
        let annex = [0, 0, 0, 1, 0x40, 1, 2, 0, 0, 1, 0x42, 1, 0, 0, 0, 1, 0x26, 1, 9, 9, 0];
        let nals = split_annex_b(&annex);
        assert_eq!(nals, vec![&[0x40, 1, 2][..], &[0x42, 1][..], &[0x26, 1, 9, 9][..]]);
        let p = frame_payload(&nals);
        assert_eq!(&p[0..4], &[0, 0, 0, 3]);
        assert_eq!(split_frame_payload(&p).unwrap(), nals);
        assert!(nal_type::is_irap(hevc_nal_type(nals[2])));
        assert_eq!(split_frame_payload(&[0, 0, 0, 9, 1]), None);
    }

    #[test]
    fn swift_frame_sample() {
        // The first 12 bytes of a keyframe captured from SillHost: one NAL of 0x4a8 bytes, type 19.
        let head = hex("000004a82601ad0e8f110486");
        assert_eq!(u32::from_be_bytes(head[0..4].try_into().unwrap()), 0x4a8);
        assert_eq!(hevc_nal_type(&head[4..]), 19);
    }

    #[test]
    fn image_and_cursor_blobs() {
        let t = image_blob::encode_thumbnail(0x3881, b"\xff\xd8jpeg");
        assert_eq!(&t[..4], &hex("00003881")[..]);
        assert_eq!(image_blob::decode_thumbnail(&t), Some((0x3881, &b"\xff\xd8jpeg"[..])));
        let i = image_blob::encode_icon("com.apple.Passwords", b"\x89PNG");
        assert_eq!(&i[..2], &[0, 0x13]);
        assert_eq!(image_blob::decode_icon(&i), Some(("com.apple.Passwords".to_string(), &b"\x89PNG"[..])));
        // A cursor captured from SillHost: hotspot 5,5, size 28×40.
        let c = cursor_blob::encode(5.0, 5.0, 28.0, 40.0, b"\x89PNG\r\n\x1a\n");
        assert_eq!(&c[..16], &hex("40a0000040a0000041e0000042200000")[..]);
        let (hx, hy, w, h, png) = cursor_blob::decode(&c).unwrap();
        assert_eq!((hx, hy, w, h), (5.0, 5.0, 28.0, 40.0));
        assert_eq!(png, b"\x89PNG\r\n\x1a\n");
    }
}
