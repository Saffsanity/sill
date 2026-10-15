//! Identities for the TLS doors (RemoteIdentity.swift): P-256 keys, pinned as the SHA-256 of the
//! SubjectPublicKeyInfo; the Mac ID; the hand-built self-signed certificate; base64url.

use base64::Engine;
use ring::rand::{SecureRandom, SystemRandom};
use ring::signature::{EcdsaKeyPair, KeyPair, ECDSA_P256_SHA256_ASN1, ECDSA_P256_SHA256_ASN1_SIGNING};

/// base64url without padding (RFC 4648 §5).
pub mod base64url {
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;
    use base64::Engine;

    pub fn encode(d: &[u8]) -> String {
        URL_SAFE_NO_PAD.encode(d)
    }

    /// None for anything that is not canonical unpadded base64url (Swift's `Base64URL.decode`).
    pub fn decode(t: &str) -> Option<Vec<u8>> {
        if !t.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') || t.len() % 4 == 1 {
            return None;
        }
        let d = URL_SAFE_NO_PAD.decode(t).ok()?;
        (encode(&d) == t).then_some(d)
    }
}

/// Standard base64 with padding (kind 18's fields).
pub fn base64_std(d: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(d)
}

pub fn base64_std_decode(t: &str) -> Option<Vec<u8>> {
    base64::engine::general_purpose::STANDARD.decode(t).ok()
}

pub fn sha256(d: &[u8]) -> [u8; 32] {
    let h = ring::digest::digest(&ring::digest::SHA256, d);
    let mut out = [0u8; 32];
    out.copy_from_slice(h.as_ref());
    out
}

/// Just enough DER for one certificate and one SPKI.
pub mod der {
    pub const EC_PUBLIC_KEY: [u8; 7] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01];
    pub const PRIME256V1: [u8; 8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
    pub const ECDSA_WITH_SHA256: [u8; 8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02];
    pub const COMMON_NAME: [u8; 3] = [0x55, 0x04, 0x03];

    pub fn length(n: usize) -> Vec<u8> {
        if n < 0x80 {
            return vec![n as u8];
        }
        let mut b = Vec::new();
        let mut v = n;
        while v > 0 {
            b.insert(0, (v & 0xFF) as u8);
            v >>= 8;
        }
        let mut out = vec![0x80 | b.len() as u8];
        out.extend(b);
        out
    }
    pub fn tlv(tag: u8, content: &[u8]) -> Vec<u8> {
        let mut out = vec![tag];
        out.extend(length(content.len()));
        out.extend_from_slice(content);
        out
    }
    pub fn sequence(parts: &[Vec<u8>]) -> Vec<u8> {
        tlv(0x30, &parts.concat())
    }
    pub fn set(parts: &[Vec<u8>]) -> Vec<u8> {
        tlv(0x31, &parts.concat())
    }
    pub fn oid(b: &[u8]) -> Vec<u8> {
        tlv(0x06, b)
    }
    pub fn bit_string(b: &[u8]) -> Vec<u8> {
        let mut c = vec![0u8];
        c.extend_from_slice(b);
        tlv(0x03, &c)
    }
    /// A non-negative INTEGER from big-endian bytes: minimal, 0x00 in front when the top bit is set.
    pub fn integer(raw: &[u8]) -> Vec<u8> {
        let mut b: Vec<u8> = if raw.is_empty() { vec![0] } else { raw.to_vec() };
        while b.len() > 1 && b[0] == 0 && b[1] & 0x80 == 0 {
            b.remove(0);
        }
        if b[0] & 0x80 != 0 {
            b.insert(0, 0);
        }
        tlv(0x02, &b)
    }

    /// One TLV at `i`: (tag, content start, content end).
    pub fn read_tlv(b: &[u8], i: usize) -> Option<(u8, usize, usize)> {
        let tag = *b.get(i)?;
        let first = *b.get(i + 1)? as usize;
        let mut j = i + 2;
        let len = if first & 0x80 != 0 {
            let k = first & 0x7F;
            if k == 0 || k > 4 {
                return None;
            }
            let mut n = 0usize;
            for _ in 0..k {
                n = (n << 8) | *b.get(j)? as usize;
                j += 1;
            }
            n
        } else {
            first
        };
        let end = j.checked_add(len)?;
        (end <= b.len()).then_some((tag, j, end))
    }
}

/// The SPKI of a 65-byte uncompressed P-256 point.
pub fn spki_der(point: &[u8]) -> Vec<u8> {
    der::sequence(&[der::sequence(&[der::oid(&der::EC_PUBLIC_KEY), der::oid(&der::PRIME256V1)]), der::bit_string(point)])
}

/// SHA-256 of `spki_der(point)`: the fingerprint every pin compares.
pub fn fingerprint_of_point(point: &[u8]) -> [u8; 32] {
    sha256(&spki_der(point))
}

/// A certificate's SubjectPublicKeyInfo TLV (the 6th field of TBSCertificate after the optional
/// [0] version), as sillclient.py reads it.
pub fn certificate_spki(cert: &[u8]) -> Option<&[u8]> {
    let (_, cs, _) = der::read_tlv(cert, 0)?;
    let (_, ts, te) = der::read_tlv(cert, cs)?;
    let mut fields = Vec::new();
    let mut i = ts;
    while i < te {
        let (tag, _, end) = der::read_tlv(cert, i)?;
        fields.push((tag, i, end));
        i = end;
    }
    if fields.first()?.0 == 0xA0 {
        fields.remove(0);
    }
    let (_, start, end) = *fields.get(5)?;
    Some(&cert[start..end])
}

/// The 65-byte point of a P-256 SPKI; None for any other key.
pub fn p256_point_of_spki(spki: &[u8]) -> Option<&[u8]> {
    let prefix = &spki_der(&[0u8; 65])[..26];
    (spki.len() == 91 && spki[..26] == *prefix && spki[26] == 0x04).then(|| &spki[26..])
}

/// The fingerprint of a certificate's key when it is P-256, else None. Nothing else about the
/// certificate is looked at: names, dates and chains mean nothing to a pin.
pub fn certificate_fingerprint(cert: &[u8]) -> Option<[u8; 32]> {
    let spki = certificate_spki(cert)?;
    p256_point_of_spki(spki)?;
    Some(sha256(spki))
}

/// The Mac ID: Crockford base32 of the fingerprint's first 10 bytes, 16 characters.
pub fn mac_id(fingerprint: &[u8]) -> String {
    const ALPHABET: &[u8] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    if fingerprint.len() < 10 {
        return String::new();
    }
    let mut out = String::new();
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for &b in &fingerprint[..10] {
        buffer = (buffer << 8) | b as u32;
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(ALPHABET[((buffer >> bits) & 31) as usize] as char);
        }
        buffer &= (1 << bits) - 1;
    }
    out
}

/// "5KD2Q7": the first characters of a fingerprint's Mac ID, for log lines.
pub fn short_name(fingerprint: &[u8]) -> String {
    mac_id(fingerprint).chars().take(6).collect()
}

/// A P-256 key with its certificate, ready for TLS (`RemoteIdentity`).
pub struct Identity {
    /// PKCS#8 of the private key (what the config directory stores).
    pub pkcs8: Vec<u8>,
    key: EcdsaKeyPair,
    /// The 65-byte uncompressed public point.
    pub point: Vec<u8>,
    pub fingerprint: [u8; 32],
    /// The hand-built self-signed certificate (rebuilt each launch: the pin is the key).
    pub certificate: Vec<u8>,
}

impl Identity {
    /// A fresh key.
    pub fn generate() -> Result<Identity, String> {
        let rng = SystemRandom::new();
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, &rng).map_err(|_| "key generation failed")?;
        Identity::from_pkcs8(pkcs8.as_ref())
    }

    pub fn from_pkcs8(pkcs8: &[u8]) -> Result<Identity, String> {
        let rng = SystemRandom::new();
        let key = EcdsaKeyPair::from_pkcs8(&ECDSA_P256_SHA256_ASN1_SIGNING, pkcs8, &rng).map_err(|_| "not a P-256 PKCS#8 key")?;
        let point = key.public_key().as_ref().to_vec();
        let fingerprint = fingerprint_of_point(&point);
        let mut id = Identity { pkcs8: pkcs8.to_vec(), key, point, fingerprint, certificate: Vec::new() };
        id.certificate = id.self_signed_certificate()?;
        Ok(id)
    }

    /// DER ECDSA P-256 / SHA-256 signature over `msg`.
    pub fn sign(&self, msg: &[u8]) -> Result<Vec<u8>, String> {
        let rng = SystemRandom::new();
        self.key.sign(&rng, msg).map(|s| s.as_ref().to_vec()).map_err(|_| "signing failed".to_string())
    }

    /// `SelfSignedCertificate.make`: version 3, no extensions, a 16-byte random serial, issuer =
    /// subject = a CN of 16 random hex characters, valid from 2026-01-01 to 9999-12-31.
    fn self_signed_certificate(&self) -> Result<Vec<u8>, String> {
        let rng = SystemRandom::new();
        let mut cn = [0u8; 8];
        let mut serial = [0u8; 16];
        rng.fill(&mut cn).map_err(|_| "random failed")?;
        rng.fill(&mut serial).map_err(|_| "random failed")?;
        serial[0] = (serial[0] & 0x7F) | 0x01;
        let hex: String = cn.iter().map(|b| format!("{b:02x}")).collect();
        let name = der::sequence(&[der::set(&[der::sequence(&[der::oid(&der::COMMON_NAME), der::tlv(0x0C, hex.as_bytes())])])]);
        let algorithm = der::sequence(&[der::oid(&der::ECDSA_WITH_SHA256)]);
        let tbs = der::sequence(&[
            der::tlv(0xA0, &der::integer(&[2])),
            der::integer(&serial),
            algorithm.clone(),
            name.clone(),
            der::sequence(&[der::tlv(0x17, b"260101000000Z"), der::tlv(0x18, b"99991231235959Z")]),
            name,
            spki_der(&self.point),
        ]);
        let sig = self.sign(&tbs)?;
        Ok(der::sequence(&[tbs, algorithm, der::bit_string(&sig)]))
    }
}

/// Verifies a DER ECDSA P-256/SHA-256 signature by a 65-byte point.
pub fn verify_p256(point: &[u8], msg: &[u8], sig: &[u8]) -> bool {
    ring::signature::UnparsedPublicKey::new(&ECDSA_P256_SHA256_ASN1, point).verify(msg, sig).is_ok()
}

/// Random bytes from the system's source.
pub fn random_bytes(n: usize) -> Vec<u8> {
    let mut v = vec![0u8; n];
    let _ = SystemRandom::new().fill(&mut v);
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spki_prefix_matches_sillclient() {
        // sillclient.py's SPKI_PREFIX.
        let p = spki_der(&[4u8; 65]);
        assert_eq!(p.len(), 91);
        let hexp: String = p[..26].iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(hexp, "3059301306072a8648ce3d020106082a8648ce3d030107034200");
    }

    #[test]
    fn mac_id_matches_sillclient() {
        // sillclient.py's macid(): big-endian 80 bits, 5 at a time.
        let fp: Vec<u8> = (0..32).collect();
        let n = u128::from_be_bytes([0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
        let crock = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        let want: String = (0..16).map(|i| crock[((n >> (75 - 5 * i)) & 31) as usize] as char).collect();
        assert_eq!(mac_id(&fp), want);
        assert_eq!(mac_id(&fp).len(), 16);
    }

    #[test]
    fn certificate_parses_and_pins() {
        let id = Identity::generate().unwrap();
        assert_eq!(certificate_fingerprint(&id.certificate), Some(id.fingerprint));
        assert!(id.certificate.len() > 250 && id.certificate.len() < 400);
        let sig = id.sign(b"hello").unwrap();
        assert!(verify_p256(&id.point, b"hello", &sig));
        assert!(!verify_p256(&id.point, b"hellO", &sig));
        let again = Identity::from_pkcs8(&id.pkcs8).unwrap();
        assert_eq!(again.fingerprint, id.fingerprint);
    }

    #[test]
    fn base64url_is_canonical() {
        assert_eq!(base64url::encode(&[0xfb, 0xff]), "-_8");
        assert_eq!(base64url::decode("-_8"), Some(vec![0xfb, 0xff]));
        assert_eq!(base64url::decode("-_8="), None);
        assert_eq!(base64url::decode("+/8"), None);
        assert_eq!(base64url::decode("-_9"), None);
    }
}
