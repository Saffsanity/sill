//! TLS for the doors (RemoteTLS.swift), with rustls: TLS 1.3 only; both ends present a self-signed
//! P-256 certificate and each pins the other's key (SHA-256 of its SPKI). Names, dates and chains
//! are never evaluated. ALPN `sill/1` (a session) and `sill-pair/1` (pairing), both offered by a
//! host for good. No tickets, no resumption (a removed device must not come back on an old ticket).
//!
//! Network.framework's server verify block sees the negotiated ALPN during the handshake. rustls'
//! client-certificate verifier does not, so the host reads the ClientHello first
//! (`rustls::server::Acceptor`), picks the ALPN the way the handshake will (the server's order:
//! `sill/1`, then `sill-pair/1`; a device offers exactly one), and builds that connection's config
//! with a verifier that already knows it. An untrusted key is then refused inside the handshake, as
//! on the Mac (the device's handshake completes, then its first read fails).

use crate::identity::{certificate_fingerprint, certificate_spki, p256_point_of_spki, Identity};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::ring as provider;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::server::danger::{ClientCertVerified, ClientCertVerifier};
use rustls::server::{ClientHello, ResolvesServerCert};
use rustls::sign::CertifiedKey;
use rustls::{DigitallySignedStruct, DistinguishedName, Error, SignatureScheme};
use std::sync::Arc;

/// A session: the catalog, frames and input.
pub const SESSION_ALPN: &str = "sill/1";
/// Pairing: one kind 19 from the device, one kind 20 back, then close.
pub const PAIRING_ALPN: &str = "sill-pair/1";
/// What a host offers, in its order of preference, for good (the compatibility floor).
pub const SERVER_ALPNS: [&str; 2] = [SESSION_ALPN, PAIRING_ALPN];
/// The SNI every device sends; the host ignores it.
pub const SERVER_NAME: &str = "sill";

/// Whether to trust a peer: its key's fingerprint (None when its key is not P-256) and the ALPN
/// the handshake negotiates. Must answer at once.
pub type TrustFn = Arc<dyn Fn(Option<[u8; 32]>, Option<&str>) -> bool + Send + Sync>;

fn verify_p256_handshake(message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
    if dss.scheme != SignatureScheme::ECDSA_NISTP256_SHA256 {
        return Err(Error::PeerMisbehaved(rustls::PeerMisbehaved::SignedHandshakeWithUnadvertisedSigScheme));
    }
    let point = certificate_spki(cert.as_ref())
        .and_then(p256_point_of_spki)
        .ok_or(Error::InvalidCertificate(rustls::CertificateError::BadEncoding))?;
    if crate::identity::verify_p256(point, message, dss.signature()) {
        Ok(HandshakeSignatureValid::assertion())
    } else {
        Err(Error::InvalidCertificate(rustls::CertificateError::BadSignature))
    }
}

/// The host's check of a device's certificate: the pin and the protocol, nothing else.
#[derive(Debug)]
struct DeviceVerifier {
    alpn: Option<String>,
    trust: TrustHolder,
}

struct TrustHolder(TrustFn);

impl std::fmt::Debug for TrustHolder {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TrustFn")
    }
}

impl ClientCertVerifier for DeviceVerifier {
    fn offer_client_auth(&self) -> bool {
        true
    }
    fn client_auth_mandatory(&self) -> bool {
        true
    }
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }
    fn verify_client_cert(&self, end_entity: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: UnixTime) -> Result<ClientCertVerified, Error> {
        let fp = certificate_fingerprint(end_entity.as_ref());
        if (self.trust.0)(fp, self.alpn.as_deref()) {
            Ok(ClientCertVerified::assertion())
        } else {
            Err(Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure))
        }
    }
    fn verify_tls12_signature(&self, _: &[u8], _: &CertificateDer<'_>, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
        Err(Error::PeerIncompatible(rustls::PeerIncompatible::Tls12NotOffered))
    }
    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
        verify_p256_handshake(message, cert, dss)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![SignatureScheme::ECDSA_NISTP256_SHA256]
    }
}

#[derive(Debug)]
struct OneCert(Arc<CertifiedKey>);

impl ResolvesServerCert for OneCert {
    fn resolve(&self, _: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        Some(self.0.clone())
    }
}

fn certified_key(identity: &Identity) -> Result<Arc<CertifiedKey>, String> {
    let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(identity.pkcs8.clone()));
    let signer = provider::sign::any_ecdsa_type(&key).map_err(|e| format!("the identity key cannot sign: {e}"))?;
    Ok(Arc::new(CertifiedKey::new(vec![CertificateDer::from(identity.certificate.clone())], signer)))
}

/// The ALPN this host's handshake will choose for a ClientHello that offers `offered`.
pub fn chosen_alpn(offered: &[Vec<u8>]) -> Option<&'static str> {
    SERVER_ALPNS.iter().copied().find(|a| offered.iter().any(|o| o.as_slice() == a.as_bytes()))
}

/// The server config for one connection whose negotiated ALPN will be `alpn`.
pub fn server_config(identity: &Identity, alpn: Option<&str>, trust: TrustFn) -> Result<Arc<rustls::ServerConfig>, String> {
    let verifier = Arc::new(DeviceVerifier { alpn: alpn.map(str::to_string), trust: TrustHolder(trust) });
    let mut config = rustls::ServerConfig::builder_with_provider(Arc::new(provider::default_provider()))
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| e.to_string())?
        .with_client_cert_verifier(verifier)
        .with_cert_resolver(Arc::new(OneCert(certified_key(identity)?)));
    config.alpn_protocols = SERVER_ALPNS.iter().map(|a| a.as_bytes().to_vec()).collect();
    config.send_tls13_tickets = 0;
    config.session_storage = Arc::new(rustls::server::NoServerSessionStorage {});
    config.max_early_data_size = 0;
    Ok(Arc::new(config))
}

/// A device's (or test client's) check of the Mac: its key's fingerprint must equal `pin`
/// (None takes any P-256 key: the typed pairing path, whose proofs bind both keys).
#[derive(Debug)]
struct MacVerifier {
    pin: Option<[u8; 32]>,
}

impl ServerCertVerifier for MacVerifier {
    fn verify_server_cert(&self, end_entity: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: &ServerName<'_>, _: &[u8], _: UnixTime) -> Result<ServerCertVerified, Error> {
        match (certificate_fingerprint(end_entity.as_ref()), self.pin) {
            (Some(_), None) => Ok(ServerCertVerified::assertion()),
            (Some(fp), Some(pin)) if fp == pin => Ok(ServerCertVerified::assertion()),
            _ => Err(Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure)),
        }
    }
    fn verify_tls12_signature(&self, _: &[u8], _: &CertificateDer<'_>, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
        Err(Error::PeerIncompatible(rustls::PeerIncompatible::Tls12NotOffered))
    }
    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
        verify_p256_handshake(message, cert, dss)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        vec![SignatureScheme::ECDSA_NISTP256_SHA256]
    }
}

/// A client config as a device builds it (tests and tools): its own identity, one ALPN, the pin.
pub fn client_config(identity: &Identity, alpn: &str, pin: Option<[u8; 32]>) -> Result<Arc<rustls::ClientConfig>, String> {
    let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(identity.pkcs8.clone()));
    let mut config = rustls::ClientConfig::builder_with_provider(Arc::new(provider::default_provider()))
        .with_protocol_versions(&[&rustls::version::TLS13])
        .map_err(|e| e.to_string())?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(MacVerifier { pin }))
        .with_client_auth_cert(vec![CertificateDer::from(identity.certificate.clone())], key)
        .map_err(|e| e.to_string())?;
    config.alpn_protocols = vec![alpn.as_bytes().to_vec()];
    config.resumption = rustls::client::Resumption::disabled();
    Ok(Arc::new(config))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};

    type Served = Result<(Option<String>, Option<[u8; 32]>, Vec<u8>), String>;

    fn serve_one(listener: TcpListener, mac: Arc<Identity>, trust: TrustFn) -> std::thread::JoinHandle<Served> {
        std::thread::spawn(move || {
            let (mut tcp, _) = listener.accept().map_err(|e| e.to_string())?;
            let mut acceptor = rustls::server::Acceptor::default();
            let accepted = loop {
                acceptor.read_tls(&mut tcp).map_err(|e| e.to_string())?;
                if let Some(a) = acceptor.accept().map_err(|(e, _)| e.to_string())? {
                    break a;
                }
            };
            let offered: Vec<Vec<u8>> = accepted.client_hello().alpn().map(|i| i.map(|p| p.to_vec()).collect()).unwrap_or_default();
            let alpn = chosen_alpn(&offered);
            let mut conn = accepted.into_connection(server_config(&mac, alpn, trust)?).map_err(|(e, _)| e.to_string())?;
            while conn.is_handshaking() {
                conn.complete_io(&mut tcp).map_err(|e| e.to_string())?;
            }
            let fp = conn.peer_certificates().and_then(|c| c.first()).and_then(|c| certificate_fingerprint(c.as_ref()));
            let mut s = rustls::Stream::new(&mut conn, &mut tcp);
            let mut buf = [0u8; 5];
            s.read_exact(&mut buf).map_err(|e| e.to_string())?;
            s.write_all(b"world").map_err(|e| e.to_string())?;
            s.flush().map_err(|e| e.to_string())?;
            Ok((alpn.map(str::to_string), fp, buf.to_vec()))
        })
    }

    #[test]
    fn mutual_pinned_tls13_with_alpn() {
        let mac = Arc::new(Identity::generate().unwrap());
        let dev = Identity::generate().unwrap();
        let dev_fp = dev.fingerprint;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let trust: TrustFn = Arc::new(move |fp, alpn| fp == Some(dev_fp) && alpn == Some(SESSION_ALPN));
        let server = serve_one(listener, mac.clone(), trust);
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let cfg = client_config(&dev, SESSION_ALPN, Some(mac.fingerprint)).unwrap();
        let mut conn = rustls::ClientConnection::new(cfg, ServerName::try_from(SERVER_NAME).unwrap()).unwrap();
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        s.write_all(b"hello").unwrap();
        let mut buf = [0u8; 5];
        s.read_exact(&mut buf).unwrap();
        assert_eq!(&buf, b"world");
        assert_eq!(conn.alpn_protocol(), Some(SESSION_ALPN.as_bytes()));
        assert_eq!(conn.protocol_version(), Some(rustls::ProtocolVersion::TLSv1_3));
        let (alpn, fp, got) = server.join().unwrap().unwrap();
        assert_eq!(alpn.as_deref(), Some(SESSION_ALPN));
        assert_eq!(fp, Some(dev_fp));
        assert_eq!(got, b"hello");
    }

    #[test]
    fn an_untrusted_key_is_refused_in_the_handshake() {
        let mac = Arc::new(Identity::generate().unwrap());
        let dev = Identity::generate().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let trust: TrustFn = Arc::new(|_, alpn| alpn == Some(PAIRING_ALPN));
        let server = serve_one(listener, mac.clone(), trust);
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let cfg = client_config(&dev, SESSION_ALPN, Some(mac.fingerprint)).unwrap();
        let mut conn = rustls::ClientConnection::new(cfg, ServerName::try_from(SERVER_NAME).unwrap()).unwrap();
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        let _ = s.write_all(b"hello");
        let mut buf = [0u8; 5];
        assert!(s.read_exact(&mut buf).is_err());
        assert!(server.join().unwrap().is_err());
    }

    #[test]
    fn a_wrong_pin_never_completes() {
        let mac = Arc::new(Identity::generate().unwrap());
        let dev = Identity::generate().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = serve_one(listener, mac, Arc::new(|_, _| true));
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let cfg = client_config(&dev, PAIRING_ALPN, Some([0u8; 32])).unwrap();
        let mut conn = rustls::ClientConnection::new(cfg, ServerName::try_from(SERVER_NAME).unwrap()).unwrap();
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        assert!(s.write_all(b"hello").and_then(|_| s.flush()).is_err());
        let _ = server.join();
    }

    #[test]
    fn alpn_choice() {
        assert_eq!(chosen_alpn(&[b"sill-pair/1".to_vec()]), Some(PAIRING_ALPN));
        assert_eq!(chosen_alpn(&[b"sill/1".to_vec(), b"sill-pair/1".to_vec()]), Some(SESSION_ALPN));
        assert_eq!(chosen_alpn(&[b"h2".to_vec()]), None);
    }
}
