//! A session's byte stream, plain TCP or TLS, split into a reading half (the client's reader
//! thread) and a writing half (its writer thread), plus a way to close it from anywhere.

use std::io::{self, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpStream};
use std::time::Duration;

pub trait Transport: Send {
    /// The reading half; called once.
    fn take_reader(&mut self) -> io::Result<Box<dyn Read + Send>>;
    /// The writing half; called once. Every write is a whole message's bytes.
    fn take_writer(&mut self) -> io::Result<Box<dyn Write + Send>>;
    /// Closes the connection both ways (unblocks the reader and the writer).
    fn closer(&self) -> io::Result<Box<dyn Fn() + Send + Sync>>;
    fn peer(&self) -> SocketAddr;
    /// TLS: the peer's key fingerprint; None on the plain door.
    fn peer_fingerprint(&self) -> Option<[u8; 32]> {
        None
    }
    fn encrypted(&self) -> bool {
        false
    }
}

/// TCP options of both doors (StreamServer.makeListener): no Nagle; keepalive after 5 s idle,
/// every 2 s, 3 probes, so a peer that vanished is noticed.
pub fn tune_socket(s: &TcpStream) {
    let _ = s.set_nodelay(true);
    let sock = socket2::SockRef::from(s);
    let ka = socket2::TcpKeepalive::new().with_time(Duration::from_secs(5)).with_interval(Duration::from_secs(2));
    #[cfg(not(windows))]
    let ka = ka.with_retries(3);
    let _ = sock.set_tcp_keepalive(&ka);
}

/// The remote door's sockets keep at most this much unsent data in the kernel (TCP_NOTSENT_LOWAT):
/// beyond it a write blocks, so what a slow link cannot take stays in the client's queue, where the
/// pacing counts it (`pending_bytes`) and drops frames, instead of seconds of video piling up in
/// an autotuned send buffer. Measured through sillrelay.py at 2 Mbit/s +150 ms with a stream the
/// size of the link: without it the round trip grew to 4–5 s. In-flight data is not limited, so a
/// long fat link (Tailscale) keeps its throughput. Not on Windows (no such option): there the
/// send buffer's own autotuning applies.
pub fn limit_unsent(s: &TcpStream, bytes: u32) {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "android", target_os = "ios"))]
    {
        use std::os::fd::AsRawFd;
        #[cfg(target_os = "linux")]
        const TCP_NOTSENT_LOWAT: libc::c_int = 25;
        #[cfg(target_os = "android")]
        const TCP_NOTSENT_LOWAT: libc::c_int = 25;
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        const TCP_NOTSENT_LOWAT: libc::c_int = 0x201;
        let v: libc::c_int = bytes as libc::c_int;
        // SAFETY: a valid socket descriptor and a c_int-sized option value.
        unsafe {
            libc::setsockopt(
                s.as_raw_fd(),
                libc::IPPROTO_TCP,
                TCP_NOTSENT_LOWAT,
                &v as *const libc::c_int as *const libc::c_void,
                std::mem::size_of::<libc::c_int>() as libc::socklen_t,
            );
        }
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "android", target_os = "ios")))]
    {
        let _ = (s, bytes);
    }
}

pub struct PlainTransport {
    stream: TcpStream,
    peer: SocketAddr,
}

impl PlainTransport {
    pub fn new(stream: TcpStream) -> io::Result<PlainTransport> {
        let peer = stream.peer_addr()?;
        tune_socket(&stream);
        Ok(PlainTransport { stream, peer })
    }
}

impl Transport for PlainTransport {
    fn take_reader(&mut self) -> io::Result<Box<dyn Read + Send>> {
        Ok(Box::new(self.stream.try_clone()?))
    }
    fn take_writer(&mut self) -> io::Result<Box<dyn Write + Send>> {
        Ok(Box::new(self.stream.try_clone()?))
    }
    fn closer(&self) -> io::Result<Box<dyn Fn() + Send + Sync>> {
        let s = self.stream.try_clone()?;
        Ok(Box::new(move || {
            let _ = s.shutdown(Shutdown::Both);
        }))
    }
    fn peer(&self) -> SocketAddr {
        self.peer
    }
}

/// An endpoint as Network.framework prints it: `127.0.0.1:52111`, `::1.52111` for IPv6 (NWEndpoint
/// writes IPv6 host and port with a dot); we keep the bracketed form for IPv6, which is clearer.
pub fn endpoint_text(a: &SocketAddr) -> String {
    match a {
        SocketAddr::V4(v) => format!("{}:{}", v.ip(), v.port()),
        SocketAddr::V6(v) => match v.ip().to_ipv4_mapped() {
            Some(ip4) => format!("{}:{}", ip4, v.port()),
            None => format!("[{}]:{}", v.ip(), v.port()),
        },
    }
}
