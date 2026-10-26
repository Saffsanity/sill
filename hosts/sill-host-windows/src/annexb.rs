//! Media Foundation's HEVC encoders write Annex-B: NAL units behind 00 00 01 or 00 00 00 01 start
//! codes. The core wants each access unit's NAL units bare, with the parameter sets (VPS, SPS, PPS)
//! apart (platform.rs's `EncodedFrame`). This splits and sorts them, keeps the latest parameter
//! sets (from the stream itself, or from the output type's MF_MT_MPEG_SEQUENCE_HEADER), and says
//! whether the access unit is a keyframe (an IRAP picture: IDR, CRA or BLA). Pure: tested anywhere.

use sill_host_core::platform::EncodedFrame;

pub const NAL_VPS: u8 = 32;
pub const NAL_SPS: u8 = 33;
pub const NAL_PPS: u8 = 34;
pub const NAL_AUD: u8 = 35;
pub const NAL_EOS: u8 = 36;
pub const NAL_EOB: u8 = 37;
pub const NAL_FD: u8 = 38;

/// The NAL units of an Annex-B byte stream, without their start codes. Leading bytes before the
/// first start code are skipped; the zero bytes before a 4-byte start code (and trailing zeros at
/// the end) are not part of the NAL unit.
pub fn split(data: &[u8]) -> Vec<&[u8]> {
    let mut starts = Vec::new(); // index of the first payload byte after each start code
    let mut i = 0;
    while i + 3 <= data.len() {
        if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
            starts.push(i + 3);
            i += 3;
        } else {
            i += 1;
        }
    }
    let mut nals = Vec::with_capacity(starts.len());
    for (n, &start) in starts.iter().enumerate() {
        let mut end = if n + 1 < starts.len() { starts[n + 1] - 3 } else { data.len() };
        // A 4-byte start code's leading zero, and trailing_zero_8bits, belong to no NAL unit.
        while end > start && data[end - 1] == 0 {
            end -= 1;
        }
        if end > start {
            nals.push(&data[start..end]);
        }
    }
    nals
}

/// The type of an HEVC NAL unit (the 6 bits after the forbidden zero bit).
pub fn nal_type(nal: &[u8]) -> u8 {
    nal.first().map(|b| (b >> 1) & 0x3F).unwrap_or(0xFF)
}

/// IRAP pictures (BLA, IDR, CRA, and the reserved IRAP types): a decoder can start there.
pub fn is_irap(nal_type: u8) -> bool {
    (16..=23).contains(&nal_type)
}

/// Turns the encoder's output into `EncodedFrame`s, keeping the stream's parameter sets.
#[derive(Default, Debug)]
pub struct AccessUnits {
    vps: Option<Vec<u8>>,
    sps: Option<Vec<u8>>,
    pps: Option<Vec<u8>>,
    /// Whether the parameter sets went out with a frame since they last changed.
    sent: bool,
}

impl AccessUnits {
    pub fn new() -> Self {
        Self::default()
    }

    /// The parameter sets from MF_MT_MPEG_SEQUENCE_HEADER (Annex-B, as MF writes it). Ones the
    /// stream carries itself later replace them.
    pub fn set_sequence_header(&mut self, header: &[u8]) {
        for nal in split(header) {
            self.take_parameter_set(nal);
        }
    }

    /// VPS, SPS, PPS, when all three are known.
    pub fn parameter_sets(&self) -> Option<Vec<Vec<u8>>> {
        Some(vec![self.vps.clone()?, self.sps.clone()?, self.pps.clone()?])
    }

    /// One encoded sample's bytes as an access unit. `clean_point` is what the encoder said
    /// (MFSampleExtension_CleanPoint); the NAL types decide too. None when it held no picture.
    /// The parameter sets go with the first frame, every keyframe, and the first frame after they
    /// changed.
    pub fn frame(&mut self, data: &[u8], clean_point: bool, width: u32, height: u32) -> Option<EncodedFrame> {
        let mut nals = Vec::new();
        let mut irap = false;
        for nal in split(data) {
            let t = nal_type(nal);
            match t {
                NAL_VPS | NAL_SPS | NAL_PPS => self.take_parameter_set(nal),
                NAL_AUD | NAL_EOS | NAL_EOB | NAL_FD => {}
                _ => {
                    irap |= is_irap(t);
                    nals.push(nal.to_vec());
                }
            }
        }
        if nals.is_empty() {
            return None;
        }
        // A clean point without an IRAP NAL (an encoder that marks recovery points) is not a place
        // a decoder can start: trust the NAL types when they disagree, but take a clean point when
        // the types are not HEVC's picture types at all.
        let keyframe = irap || (clean_point && !nals.iter().any(|n| nal_type(n) <= 21));
        let parameter_sets = if keyframe || !self.sent { self.parameter_sets() } else { None };
        if parameter_sets.is_some() {
            self.sent = true;
        }
        Some(EncodedFrame { nals, keyframe, parameter_sets, width, height })
    }

    fn take_parameter_set(&mut self, nal: &[u8]) {
        let slot = match nal_type(nal) {
            NAL_VPS => &mut self.vps,
            NAL_SPS => &mut self.sps,
            NAL_PPS => &mut self.pps,
            _ => return,
        };
        if slot.as_deref() != Some(nal) {
            *slot = Some(nal.to_vec());
            self.sent = false;
        }
    }
}

/// Writes an `EncodedFrame` back as Annex-B (parameter sets first when present): the self-test's
/// .h265 file, which ffplay and VLC play.
pub fn to_annexb(frame: &EncodedFrame) -> Vec<u8> {
    let mut out = Vec::new();
    for nal in frame.parameter_sets.iter().flatten().chain(frame.nals.iter()) {
        out.extend_from_slice(&[0, 0, 0, 1]);
        out.extend_from_slice(nal);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nal(t: u8, body: &[u8]) -> Vec<u8> {
        let mut v = vec![t << 1, 0x01];
        v.extend_from_slice(body);
        v
    }

    fn annexb(nals: &[Vec<u8>], four: bool) -> Vec<u8> {
        let mut out = Vec::new();
        for n in nals {
            if four {
                out.extend_from_slice(&[0, 0, 0, 1]);
            } else {
                out.extend_from_slice(&[0, 0, 1]);
            }
            out.extend_from_slice(n);
        }
        out
    }

    #[test]
    fn splits_three_and_four_byte_start_codes() {
        let a = nal(1, &[0xAA, 0xBB]);
        let b = nal(19, &[0x10, 0x00, 0x00, 0x03, 0x01]); // an emulation prevention byte inside
        let mut data = vec![0, 0, 0, 1];
        data.extend_from_slice(&a);
        data.extend_from_slice(&[0, 0, 1]);
        data.extend_from_slice(&b);
        data.extend_from_slice(&[0, 0]); // trailing_zero_8bits
        assert_eq!(split(&data), vec![&a[..], &b[..]]);
    }

    #[test]
    fn junk_before_the_first_start_code_is_skipped() {
        let a = nal(1, &[7]);
        let mut data = vec![9, 9, 9];
        data.extend_from_slice(&annexb(std::slice::from_ref(&a), false));
        assert_eq!(split(&data), vec![&a[..]]);
        assert!(split(&[1, 2, 3]).is_empty());
        assert!(split(&[]).is_empty());
    }

    #[test]
    fn types() {
        assert_eq!(nal_type(&nal(NAL_VPS, &[])), 32);
        assert_eq!(nal_type(&[0x26, 0x01]), 19); // IDR_W_RADL
        assert_eq!(nal_type(&[0x02, 0x01]), 1); // TRAIL_R
        assert!(is_irap(19) && is_irap(20) && is_irap(21) && is_irap(16));
        assert!(!is_irap(1) && !is_irap(0) && !is_irap(32));
    }

    #[test]
    fn keyframe_with_in_band_parameter_sets() {
        let mut au = AccessUnits::new();
        let (vps, sps, pps) = (nal(32, &[1]), nal(33, &[2]), nal(34, &[3]));
        let idr = nal(19, &[4, 5]);
        let aud = nal(35, &[0x50]);
        let data = annexb(&[aud, vps.clone(), sps.clone(), pps.clone(), idr.clone()], true);
        let f = au.frame(&data, true, 1920, 1080).unwrap();
        assert!(f.keyframe);
        assert_eq!(f.nals, vec![idr]);
        assert_eq!(f.parameter_sets, Some(vec![vps, sps, pps]));
        assert_eq!((f.width, f.height), (1920, 1080));

        let p = nal(1, &[9]);
        let f = au.frame(&annexb(std::slice::from_ref(&p), false), false, 1920, 1080).unwrap();
        assert!(!f.keyframe);
        assert_eq!(f.nals, vec![p]);
        assert_eq!(f.parameter_sets, None);
    }

    #[test]
    fn parameter_sets_from_the_sequence_header() {
        let mut au = AccessUnits::new();
        let (vps, sps, pps) = (nal(32, &[1]), nal(33, &[2]), nal(34, &[3]));
        au.set_sequence_header(&annexb(&[vps.clone(), sps.clone(), pps.clone()], true));
        let f = au.frame(&annexb(&[nal(20, &[1])], true), false, 64, 64).unwrap();
        assert!(f.keyframe);
        assert_eq!(f.parameter_sets, Some(vec![vps.clone(), sps.clone(), pps.clone()]));
        // A later keyframe carries them again (the core sends them only when they change).
        let f = au.frame(&annexb(&[nal(21, &[1])], true), false, 64, 64).unwrap();
        assert!(f.parameter_sets.is_some());
    }

    #[test]
    fn first_frame_carries_parameter_sets_even_without_irap() {
        let mut au = AccessUnits::new();
        let (vps, sps, pps) = (nal(32, &[1]), nal(33, &[2]), nal(34, &[3]));
        au.set_sequence_header(&annexb(&[vps, sps, pps], true));
        let f = au.frame(&annexb(&[nal(1, &[1])], true), false, 64, 64).unwrap();
        assert!(!f.keyframe);
        assert!(f.parameter_sets.is_some());
        let f = au.frame(&annexb(&[nal(1, &[2])], true), false, 64, 64).unwrap();
        assert!(f.parameter_sets.is_none());
    }

    #[test]
    fn changed_parameter_sets_go_out_again() {
        let mut au = AccessUnits::new();
        let data = annexb(&[nal(32, &[1]), nal(33, &[2]), nal(34, &[3]), nal(19, &[0])], true);
        assert!(au.frame(&data, true, 64, 64).unwrap().parameter_sets.is_some());
        // A new SPS (a new size) in a non-IRAP access unit still goes out.
        let data = annexb(&[nal(33, &[7]), nal(1, &[0])], true);
        let f = au.frame(&data, false, 64, 64).unwrap();
        assert_eq!(f.parameter_sets.unwrap()[1], nal(33, &[7]));
    }

    #[test]
    fn a_sample_with_only_parameter_sets_is_no_frame() {
        let mut au = AccessUnits::new();
        let data = annexb(&[nal(32, &[1]), nal(33, &[2]), nal(34, &[3])], true);
        assert!(au.frame(&data, false, 64, 64).is_none());
        assert!(au.parameter_sets().is_some());
    }

    #[test]
    fn round_trip_to_annexb() {
        let mut au = AccessUnits::new();
        let data = annexb(&[nal(32, &[1]), nal(33, &[2]), nal(34, &[3]), nal(19, &[4]), nal(19, &[5])], true);
        let f = au.frame(&data, true, 64, 64).unwrap();
        assert_eq!(to_annexb(&f), data);
    }
}
