//! The host on the local network as `_sill._tcp`, through Windows' own mDNS responder
//! (DnsServiceRegister, Windows 10 1809 and later): no Bonjour install needed.

use std::ffi::c_void;
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use windows::core::PCWSTR;
use windows::Win32::Foundation::DNS_REQUEST_PENDING;
use windows::Win32::NetworkManagement::Dns::{
    DnsServiceConstructInstance, DnsServiceDeRegister, DnsServiceFreeInstance, DnsServiceRegister,
    DNS_QUERY_REQUEST_VERSION1, DNS_SERVICE_INSTANCE, DNS_SERVICE_REGISTER_REQUEST,
};

use super::util::{log, wide};

/// What the completion callback reports: the status of the last registration or deregistration.
struct Signal {
    status: Mutex<Option<u32>>,
    done: Condvar,
}

/// Keeps the service registered until dropped.
pub struct Advertisement {
    request: Box<DNS_SERVICE_REGISTER_REQUEST>,
    instance: *mut DNS_SERVICE_INSTANCE,
    signal: Arc<Signal>,
    name: String,
}

unsafe impl Send for Advertisement {}

unsafe extern "system" fn completed(status: u32, context: *const c_void, instance: *const DNS_SERVICE_INSTANCE) {
    if !instance.is_null() {
        unsafe { DnsServiceFreeInstance(instance) };
    }
    if context.is_null() {
        return;
    }
    // The context is a leaked Arc<Signal> (see `advertise`): valid for the process's life.
    let signal = unsafe { &*(context as *const Signal) };
    if let Ok(mut s) = signal.status.lock() {
        *s = Some(status);
    }
    signal.done.notify_all();
}

/// Registers `instance._sill._tcp.local` on `port` with the TXT record's keys and values.
pub fn advertise(instance: &str, host: &str, port: u16, txt: &[(String, String)]) -> Result<Advertisement, String> {
    let service = wide(&format!("{}._sill._tcp.local", escape_instance(instance)));
    let hostname = wide(&format!("{host}.local"));
    let keys_w: Vec<Vec<u16>> = txt.iter().map(|(k, _)| wide(k)).collect();
    let values_w: Vec<Vec<u16>> = txt.iter().map(|(_, v)| wide(v)).collect();
    let keys: Vec<PCWSTR> = keys_w.iter().map(|k| PCWSTR(k.as_ptr())).collect();
    let values: Vec<PCWSTR> = values_w.iter().map(|v| PCWSTR(v.as_ptr())).collect();
    let instance_ptr = unsafe {
        DnsServiceConstructInstance(
            PCWSTR(service.as_ptr()),
            PCWSTR(hostname.as_ptr()),
            None,
            None,
            port,
            0,
            0,
            keys.len() as u32,
            if keys.is_empty() { std::ptr::null() } else { keys.as_ptr() },
            if values.is_empty() { std::ptr::null() } else { values.as_ptr() },
        )
    };
    if instance_ptr.is_null() {
        return Err("DnsServiceConstructInstance failed".into());
    }
    let signal = Arc::new(Signal { status: Mutex::new(None), done: Condvar::new() });
    // One reference is leaked on purpose: Windows may call back after the guard is gone.
    let context = Arc::into_raw(signal.clone()) as *mut c_void;
    let request = Box::new(DNS_SERVICE_REGISTER_REQUEST {
        Version: DNS_QUERY_REQUEST_VERSION1.0,
        InterfaceIndex: 0,
        pServiceInstance: instance_ptr,
        pRegisterCompletionCallback: Some(completed),
        pQueryContext: context,
        ..Default::default()
    });
    let status = unsafe { DnsServiceRegister(&*request, None) };
    if status != DNS_REQUEST_PENDING as u32 {
        unsafe { DnsServiceFreeInstance(instance_ptr) };
        return Err(format!("DnsServiceRegister failed ({status}); mDNS needs Windows 10 1809 or later"));
    }
    // Say how it went, without holding the caller up for long.
    let ok = wait(&signal, Duration::from_secs(2));
    match ok {
        Some(0) => log(&format!("Advertising {instance} as _sill._tcp on port {port}")),
        Some(code) => log(&format!("mDNS registration reported {code}; devices may not list this PC")),
        None => log("mDNS registration still pending after 2 s"),
    }
    Ok(Advertisement { request, instance: instance_ptr, signal, name: instance.to_string() })
}

fn wait(signal: &Signal, timeout: Duration) -> Option<u32> {
    let guard = signal.status.lock().ok()?;
    let (mut guard, _) = signal.done.wait_timeout_while(guard, timeout, |s| s.is_none()).ok()?;
    guard.take()
}

impl Drop for Advertisement {
    fn drop(&mut self) {
        if let Ok(mut s) = self.signal.status.lock() {
            *s = None;
        }
        let status = unsafe { DnsServiceDeRegister(&*self.request, None) };
        if status == DNS_REQUEST_PENDING as u32 {
            let _ = wait(&self.signal, Duration::from_secs(2));
        }
        unsafe { DnsServiceFreeInstance(self.instance) };
        log(&format!("Stopped advertising {}", self.name));
    }
}

/// An instance name as one DNS label. Whether DnsServiceConstructInstance takes RFC 6763's
/// escaped dots is not documented, so a dot (rare in a PC's name) becomes a hyphen.
fn escape_instance(name: &str) -> String {
    name.chars().map(|c| if c == '.' { '-' } else { c }).collect()
}
