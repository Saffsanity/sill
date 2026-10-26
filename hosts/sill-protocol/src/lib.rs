//! Sill's wire protocol, byte for byte as the Swift reference has it (Sources/StreamProtocol).
//! Owned by the core agent; see ../README.md.
//!
//! - [`wire`]: the 14-byte header, the message kinds and the size caps.
//! - [`messages`]: every JSON payload, shaped as Swift's synthesized `Codable` writes and reads it
//!   (enums with associated values as `{"case":{"_0":…}}`, nil optionals left out, whole doubles
//!   written as integers like Foundation's `JSONEncoder`).
//! - [`blobs`]: the binary payloads: ParameterSets, ImageBlob, CursorShapeBlob, and the frames'
//!   4-byte length framing of HEVC NAL units (hvcC style), plus an Annex-B splitter.
//! - [`text`]: `SafeText.label` and `SillVersion`.
//! - [`identity`], [`pairing`], [`tls`]: the TLS doors (milestone B): SPKI pins, the Mac ID, the
//!   hand-built self-signed certificate, the typed code, proofs, recognition tags, pairing links,
//!   and rustls configured the way Network.framework's verify blocks expect.

pub mod blobs;
pub mod identity;
pub mod messages;
pub mod pairing;
pub mod text;
pub mod tls;
pub mod wire;

pub use blobs::*;
pub use messages::*;
pub use wire::*;
