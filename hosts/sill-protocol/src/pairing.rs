//! Pairing (Pairing.swift): the typed code, the proofs, the recognition tag, the TXT record's `p`
//! and the `sill://pair` link.

use crate::identity::{base64url, mac_id, random_bytes};
use ring::hmac;
use std::num::NonZeroU32;

/// Damm's quasigroup of order 10.
const DAMM: [[u8; 10]; 10] = [
    [0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
    [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
    [4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
    [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
    [6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
    [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
    [5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
    [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
    [9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
    [2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
];

pub const CODE_LENGTH: usize = 12;

pub fn damm_check_digit(digits: &[u8]) -> u8 {
    digits.iter().fold(0u8, |i, &d| DAMM[i as usize][d as usize])
}

/// A fresh code: 11 uniformly random digits (rejection sampling), then the check digit.
pub fn generate_code() -> String {
    let mut digits = Vec::with_capacity(CODE_LENGTH);
    while digits.len() < CODE_LENGTH - 1 {
        for b in random_bytes(16) {
            if b < 250 && digits.len() < CODE_LENGTH - 1 {
                digits.push(b % 10);
            }
        }
    }
    let check = damm_check_digit(&digits);
    digits.push(check);
    digits.iter().map(|d| char::from(b'0' + d)).collect()
}

/// Typed input as a code: spaces and hyphens removed, 12 ASCII digits, check digit valid.
pub fn check_code(input: &str) -> Option<String> {
    let kept: String = input.chars().filter(|c| *c != ' ' && *c != '-' && *c != '\u{00A0}').collect();
    if kept.len() != CODE_LENGTH || !kept.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let digits: Vec<u8> = kept.bytes().map(|b| b - b'0').collect();
    (damm_check_digit(&digits) == 0).then_some(kept)
}

/// "4829 1355 7208".
pub fn grouped(code: &str) -> String {
    code.as_bytes().chunks(4).map(|c| String::from_utf8_lossy(c).to_string()).collect::<Vec<_>>().join(" ")
}

pub const PBKDF2_ROUNDS: u32 = 600_000;
const LABEL: &str = "sill-pair-v1";

/// The typed path's key: PBKDF2-HMAC-SHA256(code, "sill-pair-v1" ‖ fp_mac, 600,000 rounds, 32 bytes).
pub fn code_key(code: &str, mac_fingerprint: &[u8]) -> Option<[u8; 32]> {
    if code.len() != CODE_LENGTH || !code.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut salt = LABEL.as_bytes().to_vec();
    salt.extend_from_slice(mac_fingerprint);
    let mut out = [0u8; 32];
    ring::pbkdf2::derive(ring::pbkdf2::PBKDF2_HMAC_SHA256, NonZeroU32::new(PBKDF2_ROUNDS)?, &salt, code.as_bytes(), &mut out);
    Some(out)
}

fn device_message(device_fp: &[u8], mac_fp: &[u8]) -> Vec<u8> {
    let mut m = format!("{LABEL} device").into_bytes();
    m.push(0);
    m.extend_from_slice(device_fp);
    m.extend_from_slice(mac_fp);
    m
}

fn mac_message(mac_fp: &[u8], device_fp: &[u8]) -> Vec<u8> {
    let mut m = format!("{LABEL} mac").into_bytes();
    m.push(0);
    m.extend_from_slice(mac_fp);
    m.extend_from_slice(device_fp);
    m
}

/// proof_D = HMAC-SHA256(key, "sill-pair-v1 device" ‖ 0 ‖ fp_device ‖ fp_mac).
pub fn device_proof(key: &[u8], device_fp: &[u8], mac_fp: &[u8]) -> Vec<u8> {
    hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, key), &device_message(device_fp, mac_fp)).as_ref().to_vec()
}

/// proof_M = HMAC-SHA256(key, "sill-pair-v1 mac" ‖ 0 ‖ fp_mac ‖ fp_device).
pub fn mac_proof(key: &[u8], mac_fp: &[u8], device_fp: &[u8]) -> Vec<u8> {
    hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, key), &mac_message(mac_fp, device_fp)).as_ref().to_vec()
}

/// The Mac's constant-time check of proof_D.
pub fn is_valid_device_proof(proof: &[u8], key: &[u8], device_fp: &[u8], mac_fp: &[u8]) -> bool {
    hmac::verify(&hmac::Key::new(hmac::HMAC_SHA256, key), &device_message(device_fp, mac_fp), proof).is_ok()
}

/// The TXT key of the recognition tag.
pub const TXT_RECOGNITION: &str = "r";
/// The TXT key of the home door's mode.
pub const TXT_HOME_DOOR: &str = "p";

/// `p ‖ HMAC-SHA256(recognitionKey, "sill-tag-v1" ‖ p)[0..6]`, base64url (16 characters), `p` 6
/// fresh random bytes (or `nonce` for test vectors).
pub fn recognition_tag(recognition_key: &[u8], nonce: Option<&[u8]>) -> String {
    let p: Vec<u8> = match nonce {
        Some(n) if n.len() == 6 => n.to_vec(),
        _ => random_bytes(6),
    };
    let mut msg = b"sill-tag-v1".to_vec();
    msg.extend_from_slice(&p);
    let mac = hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, recognition_key), &msg);
    let mut tag = p;
    tag.extend_from_slice(&mac.as_ref()[..6]);
    base64url::encode(&tag)
}

/// The value a TLS home door advertises as `p`.
pub fn home_door_value(require_pairing: bool) -> &'static str {
    if require_pairing {
        "1"
    } else {
        "0"
    }
}

/// The QR code's content: `sill://pair?v=1&m=…&k=…&s=…&n=…&p=…&a=…`.
pub fn pair_link(fingerprint: &[u8], secret: &[u8], name: &str, port: u16, addresses: &[String]) -> String {
    let clean = crate::text::safe_label(name, 64);
    let name = if clean.is_empty() { "Mac".to_string() } else { clean };
    let mut items = vec![
        ("v", "1".to_string()),
        ("m", mac_id(fingerprint)),
        ("k", base64url::encode(fingerprint)),
        ("s", base64url::encode(secret)),
        ("n", name),
        ("p", port.to_string()),
    ];
    for a in addresses.iter().take(5) {
        items.push(("a", a.clone()));
    }
    let q: Vec<String> = items.iter().map(|(k, v)| format!("{k}={}", escape(v))).collect();
    format!("sill://pair?{}", q.join("&"))
}

/// Percent-encodes everything but RFC 3986's unreserved characters and ":".
fn escape(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~:".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes() {
        for _ in 0..50 {
            let c = generate_code();
            assert_eq!(c.len(), 12);
            assert_eq!(check_code(&c), Some(c.clone()));
            assert_eq!(check_code(&grouped(&c)), Some(c.clone()));
            // A single substitution is always caught.
            let mut b = c.clone().into_bytes();
            b[3] = if b[3] == b'9' { b'0' } else { b[3] + 1 };
            assert_eq!(check_code(std::str::from_utf8(&b).unwrap()), None);
        }
        assert_eq!(grouped("482913557208"), "4829 1355 7208");
    }

    #[test]
    fn proofs_match_python_hmac_and_pbkdf2() {
        // sillclient.py: hashlib.pbkdf2_hmac("sha256", code, b"sill-pair-v1" + fp_mac, 600_000, 32)
        // and hmac.new(k, b"sill-pair-v1 device\x00" + fp_dev + fp_mac, sha256). Values computed with
        // Python 3, fp_mac = bytes(range(32)), fp_dev = bytes(range(32, 64)).
        let fp_mac: Vec<u8> = (0..32).collect();
        let fp_dev: Vec<u8> = (32..64).collect();
        let k = code_key("482913557208", &fp_mac).unwrap();
        let pd = device_proof(&k, &fp_dev, &fp_mac);
        let pm = mac_proof(&k, &fp_mac, &fp_dev);
        assert!(is_valid_device_proof(&pd, &k, &fp_dev, &fp_mac));
        assert!(!is_valid_device_proof(&pm, &k, &fp_dev, &fp_mac));
        let hex = |v: &[u8]| v.iter().map(|b| format!("{b:02x}")).collect::<String>();
        assert_eq!(hex(&k), include_str!("../testdata/pbkdf2_key.hex").trim());
        assert_eq!(hex(&pd), include_str!("../testdata/proof_d.hex").trim());
        assert_eq!(hex(&pm), include_str!("../testdata/proof_m.hex").trim());
    }

    #[test]
    fn link_shape() {
        let fp = [7u8; 32];
        let link = pair_link(&fp, &[1u8; 16], "Tom & Jerry's PC", 7455, &["100.64.0.1".into()]);
        assert!(link.starts_with("sill://pair?v=1&m="));
        assert!(link.contains("&n=Tom%20%26%20Jerry%27s%20PC&p=7455&a=100.64.0.1"));
    }

    #[test]
    fn tags() {
        let t = recognition_tag(&[9u8; 32], Some(&[1, 2, 3, 4, 5, 6]));
        assert_eq!(t.len(), 16);
        assert_eq!(&base64url::decode(&t).unwrap()[..6], &[1, 2, 3, 4, 5, 6]);
    }
}
