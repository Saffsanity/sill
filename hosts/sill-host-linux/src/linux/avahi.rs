//! Advertising `_sill._tcp` on the local network through Avahi: its D-Bus API on the system bus (an
//! EntryGroup with one service and the TXT record, committed; freed when the guard drops), else an
//! `avahi-publish` subprocess killed when the guard drops. A name another host already uses gets
//! " (2)", " (3)"... as Bonjour renames a clash on the Mac.

use std::process::{Child, Command, Stdio};

use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::OwnedObjectPath;

const SERVICE: &str = "_sill._tcp";

pub struct Advertisement {
    inner: Inner,
    pub name: String,
}

enum Inner {
    DBus { _conn: Connection, group: Proxy<'static> },
    Subprocess(Child),
}

impl Drop for Advertisement {
    fn drop(&mut self) {
        match &mut self.inner {
            Inner::DBus { group, .. } => {
                let _: Result<(), _> = group.call("Free", &());
            }
            Inner::Subprocess(child) => {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }
}

fn txt_bytes(txt: &[(String, String)]) -> Vec<Vec<u8>> {
    txt.iter().map(|(k, v)| format!("{k}={v}").into_bytes()).collect()
}

pub fn advertise(instance: &str, port: u16, txt: &[(String, String)]) -> Result<Advertisement, String> {
    match dbus(instance, port, txt) {
        Ok(ad) => Ok(ad),
        Err(dbus_error) => subprocess(instance, port, txt)
            .map_err(|e| format!("Avahi over D-Bus: {dbus_error}; avahi-publish: {e}")),
    }
}

fn dbus(instance: &str, port: u16, txt: &[(String, String)]) -> Result<Advertisement, String> {
    let conn = Connection::system().map_err(|e| format!("system bus: {e}"))?;
    let server = Proxy::new(&conn, "org.freedesktop.Avahi", "/", "org.freedesktop.Avahi.Server")
        .map_err(|e| e.to_string())?;
    let path: OwnedObjectPath = server.call("EntryGroupNew", &()).map_err(|e| format!("EntryGroupNew: {e}"))?;
    let group = Proxy::new(&conn, "org.freedesktop.Avahi", path.into_inner(), "org.freedesktop.Avahi.EntryGroup")
        .map_err(|e| e.to_string())?;
    let txt = txt_bytes(txt);
    let mut name = instance.to_string();
    for n in 2..=20 {
        // AddService(interface -1 = all, protocol -1 = IPv4 and IPv6, flags 0, name, type, domain
        // "" = .local, host "" = this host, port, TXT).
        let added: Result<(), zbus::Error> =
            group.call("AddService", &(-1i32, -1i32, 0u32, name.as_str(), SERVICE, "", "", port, txt.clone()));
        match added {
            Ok(()) => {
                let _: () = group.call("Commit", &()).map_err(|e| format!("Commit: {e}"))?;
                return Ok(Advertisement { inner: Inner::DBus { _conn: conn, group }, name });
            }
            Err(e) if e.to_string().contains("Collision") => {
                let _: Result<(), _> = group.call("Reset", &());
                name = format!("{instance} ({n})");
            }
            Err(e) => return Err(format!("AddService: {e}")),
        }
    }
    Err("every name collided".into())
}

fn subprocess(instance: &str, port: u16, txt: &[(String, String)]) -> Result<Advertisement, String> {
    let mut cmd = Command::new("avahi-publish");
    cmd.arg("-s").arg(instance).arg(SERVICE).arg(port.to_string());
    for (k, v) in txt {
        cmd.arg(format!("{k}={v}"));
    }
    let mut child = cmd.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|e| e.to_string())?;
    // A daemon that is not running makes it exit at once.
    std::thread::sleep(std::time::Duration::from_millis(300));
    if let Ok(Some(status)) = child.try_wait() {
        return Err(format!("exited at once ({status}): is avahi-daemon running?"));
    }
    Ok(Advertisement { inner: Inner::Subprocess(child), name: instance.to_string() })
}
