//! A TLS session as a `Transport`: one rustls connection shared by the reader and the writer
//! thread. Socket writes are serialized by their own lock (taken before the connection's), so a
//! record the reader must answer never lands inside a frame the writer is sending.

use crate::transport::{tune_socket, Transport};
use rustls::ServerConnection;
use std::io::{self, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpStream};
use std::sync::{Arc, Mutex};

pub struct TlsTransport {
    conn: Arc<Mutex<ServerConnection>>,
    sock: TcpStream,
    sock_write: Arc<Mutex<TcpStream>>,
    peer: SocketAddr,
    fingerprint: [u8; 32],
}

impl TlsTransport {
    /// After the handshake. `sock` must be in blocking mode with no timeouts.
    pub fn new(conn: ServerConnection, sock: TcpStream, fingerprint: [u8; 32]) -> io::Result<TlsTransport> {
        let peer = sock.peer_addr()?;
        tune_socket(&sock);
        let w = sock.try_clone()?;
        Ok(TlsTransport { conn: Arc::new(Mutex::new(conn)), sock, sock_write: Arc::new(Mutex::new(w)), peer, fingerprint })
    }
}

/// Encrypted bytes the connection wants to send, taken out under its lock.
fn drain(conn: &mut ServerConnection) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    while conn.wants_write() {
        conn.write_tls(&mut out)?;
    }
    Ok(out)
}

fn flush_pending(conn: &Mutex<ServerConnection>, sock_write: &Mutex<TcpStream>) -> io::Result<()> {
    let mut s = sock_write.lock().unwrap();
    let out = drain(&mut conn.lock().unwrap())?;
    if !out.is_empty() {
        s.write_all(&out)?;
    }
    Ok(())
}

struct TlsReader {
    conn: Arc<Mutex<ServerConnection>>,
    sock: TcpStream,
    sock_write: Arc<Mutex<TcpStream>>,
    buf: Vec<u8>,
    pending: Vec<u8>,
}

impl Read for TlsReader {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        // TLS bytes read from the socket that rustls has not taken yet: it stops taking them when
        // its received-plaintext buffer is full (a burst of input), until that is read out here.
        let mut stuck = false;
        loop {
            {
                let mut c = self.conn.lock().unwrap();
                match c.reader().read(out) {
                    Ok(n) => return Ok(n), // 0: the peer's close_notify
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {}
                    Err(e) => return Err(e),
                }
            }
            if self.pending.is_empty() {
                let n = self.sock.read(&mut self.buf)?;
                if n == 0 {
                    return Ok(0);
                }
                self.pending.extend_from_slice(&self.buf[..n]);
            }
            let wants_write = {
                let mut c = self.conn.lock().unwrap();
                let mut rd = &self.pending[..];
                let took = c.read_tls(&mut rd);
                let consumed = self.pending.len() - rd.len();
                self.pending.drain(..consumed);
                match took {
                    Ok(_) => stuck = false,
                    // Nothing taken and no plaintext to read out: a real error.
                    Err(e) if stuck || consumed == 0 && !c.wants_read() => return Err(e),
                    Err(_) => stuck = true,
                }
                c.process_new_packets().map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
                c.wants_write()
            };
            if wants_write {
                flush_pending(&self.conn, &self.sock_write)?;
            }
        }
    }
}

struct TlsWriter {
    conn: Arc<Mutex<ServerConnection>>,
    sock_write: Arc<Mutex<TcpStream>>,
}

impl Write for TlsWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        // rustls buffers at most 64 KB of unsent records (its buffer limit), so a keyframe of a
        // megabyte goes through in pieces: encrypt what it takes, send that, repeat.
        let mut s = self.sock_write.lock().unwrap();
        let mut off = 0;
        while off < buf.len() {
            let out = {
                let mut c = self.conn.lock().unwrap();
                let n = c.writer().write(&buf[off..])?;
                off += n;
                let out = drain(&mut c)?;
                if n == 0 && out.is_empty() {
                    return Err(io::Error::new(io::ErrorKind::WriteZero, "TLS took nothing"));
                }
                out
            };
            s.write_all(&out)?;
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Transport for TlsTransport {
    fn take_reader(&mut self) -> io::Result<Box<dyn Read + Send>> {
        Ok(Box::new(TlsReader {
            conn: self.conn.clone(),
            sock: self.sock.try_clone()?,
            sock_write: self.sock_write.clone(),
            buf: vec![0u8; 64 * 1024],
            pending: Vec::new(),
        }))
    }

    fn take_writer(&mut self) -> io::Result<Box<dyn Write + Send>> {
        Ok(Box::new(TlsWriter { conn: self.conn.clone(), sock_write: self.sock_write.clone() }))
    }

    fn closer(&self) -> io::Result<Box<dyn Fn() + Send + Sync>> {
        let conn = self.conn.clone();
        let sock_write = self.sock_write.clone();
        let sock = self.sock.try_clone()?;
        Ok(Box::new(move || {
            // close_notify when the socket is not busy with a write (a stuck peer must not hold us).
            if let Ok(mut s) = sock_write.try_lock() {
                if let Ok(mut c) = conn.try_lock() {
                    c.send_close_notify();
                    if let Ok(out) = drain(&mut c) {
                        let _ = s.write_all(&out);
                    }
                }
            }
            let _ = sock.shutdown(Shutdown::Both);
        }))
    }

    fn peer(&self) -> SocketAddr {
        self.peer
    }

    fn peer_fingerprint(&self) -> Option<[u8; 32]> {
        Some(self.fingerprint)
    }

    fn encrypted(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sill_protocol::identity::Identity;
    use sill_protocol::tls::{client_config, server_config, SESSION_ALPN, SERVER_NAME};
    use std::net::TcpListener;

    /// A 2 MB message (a large keyframe) and the device's reply both cross a TLS session whose
    /// halves run on two threads, as a client's reader and writer do.
    #[test]
    fn large_writes_and_concurrent_reads() {
        let mac = Arc::new(Identity::generate().unwrap());
        let dev = Identity::generate().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let m = mac.clone();
        let server = std::thread::spawn(move || {
            let (mut tcp, _) = listener.accept().unwrap();
            let mut conn = rustls::ServerConnection::new(server_config(&m, Some(SESSION_ALPN), Arc::new(|_, _| true)).unwrap()).unwrap();
            while conn.is_handshaking() {
                conn.complete_io(&mut tcp).unwrap();
            }
            let mut t = TlsTransport::new(conn, tcp, [0u8; 32]).unwrap();
            let mut r = t.take_reader().unwrap();
            let mut w = t.take_writer().unwrap();
            let big: Vec<u8> = (0..2_000_000u32).map(|i| (i % 251) as u8).collect();
            let writer = std::thread::spawn(move || w.write_all(&big).unwrap());
            let mut reply = [0u8; 5];
            r.read_exact(&mut reply).unwrap();
            writer.join().unwrap();
            reply
        });
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let cfg = client_config(&dev, SESSION_ALPN, Some(mac.fingerprint)).unwrap();
        let mut conn = rustls::ClientConnection::new(cfg, rustls::pki_types::ServerName::try_from(SERVER_NAME).unwrap()).unwrap();
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        s.write_all(b"hello").unwrap();
        let mut got = vec![0u8; 2_000_000];
        s.read_exact(&mut got).unwrap();
        assert!(got.iter().enumerate().all(|(i, b)| *b == (i as u32 % 251) as u8));
        assert_eq!(&server.join().unwrap(), b"hello");
    }

    /// A burst of client messages larger than rustls' received-plaintext buffer arrives whole.
    #[test]
    fn a_burst_of_input() {
        let mac = Arc::new(Identity::generate().unwrap());
        let dev = Identity::generate().unwrap();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let m = mac.clone();
        let server = std::thread::spawn(move || {
            let (mut tcp, _) = listener.accept().unwrap();
            let mut conn = rustls::ServerConnection::new(server_config(&m, Some(SESSION_ALPN), Arc::new(|_, _| true)).unwrap()).unwrap();
            while conn.is_handshaking() {
                conn.complete_io(&mut tcp).unwrap();
            }
            let mut t = TlsTransport::new(conn, tcp, [0u8; 32]).unwrap();
            let mut r = t.take_reader().unwrap();
            // Read slowly, after the whole burst has arrived.
            std::thread::sleep(std::time::Duration::from_millis(200));
            let mut got = vec![0u8; 1_000_000];
            r.read_exact(&mut got).unwrap();
            got
        });
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).unwrap();
        let cfg = client_config(&dev, SESSION_ALPN, Some(mac.fingerprint)).unwrap();
        let mut conn = rustls::ClientConnection::new(cfg, rustls::pki_types::ServerName::try_from(SERVER_NAME).unwrap()).unwrap();
        let mut s = rustls::Stream::new(&mut conn, &mut tcp);
        let burst: Vec<u8> = (0..1_000_000u32).map(|i| (i % 249) as u8).collect();
        for chunk in burst.chunks(100) {
            s.write_all(chunk).unwrap();
        }
        s.flush().unwrap();
        assert_eq!(server.join().unwrap(), burst);
    }
}
