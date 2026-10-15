//! The JSON payloads, field for field as Swift's synthesized `Codable` writes them.
//!
//! Rules (HostSettings.swift): JSON keys are the Swift property names; an optional that is nil is
//! left out (Swift's `encodeIfPresent`); a missing optional decodes as nil; unknown keys are
//! ignored. Swift writes a `Double` that holds a whole number without a fraction (`2`, not `2.0`),
//! so every `f64` here is written the same way ([`swift_f64`]), which keeps `sillclient.py`'s
//! printouts and byte comparisons identical. Enums with associated values (`StreamSource`,
//! `InputEvent`) use Swift's synthesized shape: an object with one key, the case name, whose value
//! is an object of the labelled values, unlabelled ones as `_0`, `_1`…; a case without values is
//! `{"case":{}}`.

use serde::de::{self, Deserializer};
use serde::ser::{SerializeMap, Serializer};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// Serializes an `f64` as Foundation's JSONEncoder does: a whole number in the exactly
/// representable range without a fraction, anything else as the shortest round-trip decimal.
pub mod swift_f64 {
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(v: &f64, s: S) -> Result<S::Ok, S::Error> {
        if v.is_finite() && v.fract() == 0.0 && v.abs() < 9.007_199_254_740_992e15 {
            s.serialize_i64(*v as i64)
        } else {
            s.serialize_f64(*v)
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<f64, D::Error> {
        f64::deserialize(d)
    }

    pub mod opt {
        use serde::{Deserialize, Deserializer, Serializer};

        pub fn serialize<S: Serializer>(v: &Option<f64>, s: S) -> Result<S::Ok, S::Error> {
            match v {
                Some(x) => super::serialize(x, s),
                None => s.serialize_none(),
            }
        }

        pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<f64>, D::Error> {
            Option::<f64>::deserialize(d)
        }
    }
}

/// JSON bytes of `v` (`Wire.encode`). Never fails for these types.
pub fn to_json<T: Serialize>(v: &T) -> Vec<u8> {
    serde_json::to_vec(v).unwrap_or_default()
}

/// `Wire.decode`: nil (None) for anything that does not decode.
pub fn from_json<'a, T: Deserialize<'a>>(b: &'a [u8]) -> Option<T> {
    serde_json::from_slice(b).ok()
}

// MARK: Switcher.swift

/// What the host streams (`StreamSource`): `{"none":{}}`, `{"window":{"_0":ID}}`, `{"desktop":{}}`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum StreamSource {
    #[default]
    None,
    Window(u32),
    Desktop,
}

impl Serialize for StreamSource {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(1))?;
        match self {
            StreamSource::None => m.serialize_entry("none", &Map::new())?,
            StreamSource::Desktop => m.serialize_entry("desktop", &Map::new())?,
            StreamSource::Window(id) => {
                let mut inner = Map::new();
                inner.insert("_0".into(), Value::from(*id));
                m.serialize_entry("window", &inner)?
            }
        }
        m.end()
    }
}

impl<'de> Deserialize<'de> for StreamSource {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let v = Value::deserialize(d)?;
        let (case, inner) = single_case(&v).map_err(de::Error::custom)?;
        match case {
            "none" => Ok(StreamSource::None),
            "desktop" => Ok(StreamSource::Desktop),
            "window" => {
                let id = inner
                    .get("_0")
                    .and_then(Value::as_u64)
                    .filter(|v| *v <= u32::MAX as u64)
                    .ok_or_else(|| de::Error::custom("window needs _0"))?;
                Ok(StreamSource::Window(id as u32))
            }
            other => Err(de::Error::custom(format!("unknown StreamSource case {other}"))),
        }
    }
}

/// Swift's synthesized enum decoding: exactly one key, whose value is an object.
fn single_case(v: &Value) -> Result<(&str, &Map<String, Value>), String> {
    let obj = v.as_object().ok_or("not an object")?;
    if obj.len() != 1 {
        return Err("an enum case is an object with exactly one key".into());
    }
    let (k, inner) = obj.iter().next().unwrap();
    let inner = inner.as_object().ok_or("an enum case's value is an object")?;
    Ok((k.as_str(), inner))
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WindowInfo {
    pub id: u32,
    pub title: String,
    #[serde(rename = "appName")]
    pub app_name: String,
    #[serde(rename = "bundleID")]
    pub bundle_id: String,
    /// Points on the Mac; the backend's own units here.
    pub width: i64,
    pub height: i64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppInfo {
    pub name: String,
    #[serde(rename = "bundleID")]
    pub bundle_id: String,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct WindowList {
    #[serde(rename = "macName")]
    pub mac_name: String,
    pub windows: Vec<WindowInfo>,
    pub active: StreamSource,
    #[serde(rename = "launchID", skip_serializing_if = "Option::is_none", default)]
    pub launch_id: Option<String>,
    #[serde(rename = "hostVersion", skip_serializing_if = "Option::is_none", default)]
    pub host_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub protocol: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub gestures: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct LaunchApp {
    #[serde(rename = "bundleID")]
    pub bundle_id: String,
}

/// `WindowCommand.Action`: "close", "minimize", "fullScreen".
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct WindowCommand {
    pub id: u32,
    pub action: String,
}

impl WindowCommand {
    pub const CLOSE: &'static str = "close";
    pub const MINIMIZE: &'static str = "minimize";
    pub const FULL_SCREEN: &'static str = "fullScreen";
}

// MARK: Input.swift

/// `PointerAction`'s raw values.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PointerAction {
    #[serde(rename = "move")]
    Move,
    #[serde(rename = "leftDown")]
    LeftDown,
    #[serde(rename = "leftUp")]
    LeftUp,
    #[serde(rename = "rightDown")]
    RightDown,
    #[serde(rename = "rightUp")]
    RightUp,
}

/// `ScrollPhase`'s raw values.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ScrollPhase {
    #[serde(rename = "began")]
    Began,
    #[serde(rename = "ended")]
    Ended,
    #[serde(rename = "momentumBegan")]
    MomentumBegan,
    #[serde(rename = "momentumEnded")]
    MomentumEnded,
}

/// Client → host input (`InputEvent`). Positions are fractions of the streamed frame (0…1).
#[derive(Clone, Debug, PartialEq)]
pub enum InputEvent {
    /// `{"pointer":{"_0":"leftDown","x":0.5,"y":0.5}}`
    Pointer { action: PointerAction, x: f64, y: f64 },
    /// `{"scroll":{"x":…,"y":…,"dx":…,"dy":…}}`; dx/dy are fractions of the frame, natural sign.
    Scroll { x: f64, y: f64, dx: f64, dy: f64 },
    /// `{"text":{"_0":"abc"}}`
    Text(String),
    /// `{"scrollGesture":{"_0":"began","x":…,"y":…}}`
    ScrollGesture { phase: ScrollPhase, x: f64, y: f64 },
    /// `{"key":{"hidUsage":4,"down":true,"modifiers":0}}`
    Key { hid_usage: u16, down: bool, modifiers: u64 },
}

fn num(v: f64) -> Value {
    if v.is_finite() && v.fract() == 0.0 && v.abs() < 9.007_199_254_740_992e15 {
        Value::from(v as i64)
    } else {
        serde_json::Number::from_f64(v).map(Value::Number).unwrap_or(Value::Null)
    }
}

impl Serialize for InputEvent {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut inner = Map::new();
        let case = match self {
            InputEvent::Pointer { action, x, y } => {
                inner.insert("_0".into(), serde_json::to_value(action).unwrap_or(Value::Null));
                inner.insert("x".into(), num(*x));
                inner.insert("y".into(), num(*y));
                "pointer"
            }
            InputEvent::Scroll { x, y, dx, dy } => {
                inner.insert("x".into(), num(*x));
                inner.insert("y".into(), num(*y));
                inner.insert("dx".into(), num(*dx));
                inner.insert("dy".into(), num(*dy));
                "scroll"
            }
            InputEvent::Text(t) => {
                inner.insert("_0".into(), Value::from(t.clone()));
                "text"
            }
            InputEvent::ScrollGesture { phase, x, y } => {
                inner.insert("_0".into(), serde_json::to_value(phase).unwrap_or(Value::Null));
                inner.insert("x".into(), num(*x));
                inner.insert("y".into(), num(*y));
                "scrollGesture"
            }
            InputEvent::Key { hid_usage, down, modifiers } => {
                inner.insert("hidUsage".into(), Value::from(*hid_usage));
                inner.insert("down".into(), Value::from(*down));
                inner.insert("modifiers".into(), Value::from(*modifiers));
                "key"
            }
        };
        let mut m = s.serialize_map(Some(1))?;
        m.serialize_entry(case, &inner)?;
        m.end()
    }
}

impl<'de> Deserialize<'de> for InputEvent {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let v = Value::deserialize(d)?;
        let (case, inner) = single_case(&v).map_err(de::Error::custom)?;
        let f = |k: &str| -> Result<f64, D::Error> {
            inner.get(k).and_then(Value::as_f64).ok_or_else(|| de::Error::custom(format!("{case} needs {k}")))
        };
        match case {
            "pointer" => {
                let action: PointerAction = inner
                    .get("_0")
                    .cloned()
                    .and_then(|a| serde_json::from_value(a).ok())
                    .ok_or_else(|| de::Error::custom("pointer needs _0"))?;
                Ok(InputEvent::Pointer { action, x: f("x")?, y: f("y")? })
            }
            "scroll" => Ok(InputEvent::Scroll { x: f("x")?, y: f("y")?, dx: f("dx")?, dy: f("dy")? }),
            "text" => {
                let t = inner.get("_0").and_then(Value::as_str).ok_or_else(|| de::Error::custom("text needs _0"))?;
                Ok(InputEvent::Text(t.to_string()))
            }
            "scrollGesture" => {
                let phase: ScrollPhase = inner
                    .get("_0")
                    .cloned()
                    .and_then(|a| serde_json::from_value(a).ok())
                    .ok_or_else(|| de::Error::custom("scrollGesture needs _0"))?;
                Ok(InputEvent::ScrollGesture { phase, x: f("x")?, y: f("y")? })
            }
            "key" => {
                let hid = inner
                    .get("hidUsage")
                    .and_then(Value::as_u64)
                    .filter(|v| *v <= u16::MAX as u64)
                    .ok_or_else(|| de::Error::custom("key needs hidUsage"))?;
                let down = inner.get("down").and_then(Value::as_bool).ok_or_else(|| de::Error::custom("key needs down"))?;
                let modifiers =
                    inner.get("modifiers").and_then(Value::as_u64).ok_or_else(|| de::Error::custom("key needs modifiers"))?;
                Ok(InputEvent::Key { hid_usage: hid as u16, down, modifiers })
            }
            other => Err(de::Error::custom(format!("unknown InputEvent case {other}"))),
        }
    }
}

/// Modifier bits in `InputEvent::Key.modifiers` (UIKeyModifierFlags = CGEventFlags positions).
pub mod modifiers {
    pub const CAPS_LOCK: u64 = 1 << 16;
    pub const SHIFT: u64 = 1 << 17;
    pub const CONTROL: u64 = 1 << 18;
    pub const OPTION: u64 = 1 << 19;
    pub const COMMAND: u64 = 1 << 20;
    pub const NUMERIC_PAD: u64 = 1 << 21;
}

// MARK: Viewport.swift

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Viewport {
    #[serde(with = "swift_f64")]
    pub width: f64,
    #[serde(with = "swift_f64")]
    pub height: f64,
    #[serde(with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub scale: Option<f64>,
    #[serde(rename = "localCursor", skip_serializing_if = "Option::is_none", default)]
    pub local_cursor: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fps: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ClientStats {
    pub fps: i64,
    #[serde(rename = "frameAgeMs")]
    pub frame_age_ms: i64,
    #[serde(rename = "rttMs")]
    pub rtt_ms: i64,
    pub device: String,
    #[serde(rename = "frameAgeMaxMs", skip_serializing_if = "Option::is_none", default)]
    pub frame_age_max_ms: Option<i64>,
    #[serde(rename = "rttMaxMs", skip_serializing_if = "Option::is_none", default)]
    pub rtt_max_ms: Option<i64>,
}

// MARK: HostSettings.swift

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct StreamSettings {
    #[serde(rename = "maxFPS")]
    pub max_fps: i64,
    pub bitrate: i64,
    #[serde(rename = "captureScale", with = "swift_f64")]
    pub capture_scale: f64,
    #[serde(rename = "prioritizeSpeed")]
    pub prioritize_speed: bool,
    #[serde(rename = "virtualDisplay")]
    pub virtual_display: bool,
    /// Nil: a host without Direct Wireless (the device shows no row and never sends it).
    #[serde(rename = "directWireless", skip_serializing_if = "Option::is_none", default)]
    pub direct_wireless: Option<bool>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunningStream {
    pub width: i64,
    pub height: i64,
    pub fps: i64,
    pub mbps: i64,
    #[serde(rename = "onVirtualDisplay")]
    pub on_virtual_display: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AwayQuality {
    #[serde(rename = "homeBitrate")]
    pub home_bitrate: i64,
    #[serde(rename = "homeCaptureScale", with = "swift_f64")]
    pub home_capture_scale: f64,
    #[serde(rename = "awayBitrate")]
    pub away_bitrate: i64,
    #[serde(rename = "awayCaptureScale", with = "swift_f64")]
    pub away_capture_scale: f64,
    #[serde(rename = "thisConnectionAway")]
    pub this_connection_away: bool,
    #[serde(rename = "awayRunning")]
    pub away_running: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct LinkReport {
    pub state: String,
    #[serde(rename = "withheldPerSecond")]
    pub withheld_per_second: i64,
    pub bitrate: i64,
    #[serde(rename = "carriedKbps", skip_serializing_if = "Option::is_none", default)]
    pub carried_kbps: Option<i64>,
    #[serde(rename = "suggestedBitrate", skip_serializing_if = "Option::is_none", default)]
    pub suggested_bitrate: Option<i64>,
    #[serde(rename = "suggestedCaptureScale", with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub suggested_capture_scale: Option<f64>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct HostSettingsState {
    pub settings: StreamSettings,
    pub persistent: bool,
    #[serde(rename = "virtualDisplayAvailable")]
    pub virtual_display_available: bool,
    #[serde(rename = "virtualDisplayNote", skip_serializing_if = "Option::is_none", default)]
    pub virtual_display_note: Option<String>,
    #[serde(rename = "softwareEncoder")]
    pub software_encoder: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub stream: Option<RunningStream>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub answering: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub away: Option<AwayQuality>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub link: Option<LinkReport>,
}

#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct HostSettingsChange {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub token: Option<i64>,
    #[serde(rename = "maxFPS", skip_serializing_if = "Option::is_none", default)]
    pub max_fps: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub bitrate: Option<i64>,
    #[serde(rename = "captureScale", with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub capture_scale: Option<f64>,
    #[serde(rename = "prioritizeSpeed", skip_serializing_if = "Option::is_none", default)]
    pub prioritize_speed: Option<bool>,
    #[serde(rename = "virtualDisplay", skip_serializing_if = "Option::is_none", default)]
    pub virtual_display: Option<bool>,
    #[serde(rename = "directWireless", skip_serializing_if = "Option::is_none", default)]
    pub direct_wireless: Option<bool>,
}

impl HostSettingsChange {
    /// All setting fields nil (the token does not count).
    pub fn is_empty(&self) -> bool {
        self.max_fps.is_none()
            && self.bitrate.is_none()
            && self.capture_scale.is_none()
            && self.prioritize_speed.is_none()
            && self.virtual_display.is_none()
            && self.direct_wireless.is_none()
    }
}

/// What a device may pick (`SettingsChoices`): exactly the Mac menu's choices.
pub mod settings_choices {
    pub const MAX_FPS: [i64; 2] = [60, 120];
    pub const CAPTURE_SCALE: [f64; 2] = [2.0, 1.0];
    /// `QualityPreset.allCases` in order: Low, Efficient, Balanced, High, Pro, Ultra, Extreme.
    pub const BITRATE: [i64; 7] = [4_000_000, 8_000_000, 15_000_000, 25_000_000, 40_000_000, 80_000_000, 150_000_000];

    /// The preset's name for a bitrate ("Balanced"), or "N Mbps".
    pub fn quality_name(bitrate: i64) -> String {
        let names = ["Low", "Efficient", "Balanced", "High", "Pro", "Ultra", "Extreme"];
        match BITRATE.iter().position(|b| *b == bitrate) {
            Some(i) => names[i].to_string(),
            None => format!("{} Mbps", mbps(bitrate)),
        }
    }

    /// "15", or "8.5" for a bitrate that is not whole megabits.
    pub fn mbps(bits: i64) -> String {
        if bits % 1_000_000 == 0 {
            format!("{}", bits / 1_000_000)
        } else {
            format!("{:.1}", bits as f64 / 1_000_000.0)
        }
    }
}

// MARK: Compatibility.swift

/// Kind 23: the device's first message on every session connection. All fields optional.
#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct Hello {
    #[serde(rename = "appVersion", skip_serializing_if = "Option::is_none", default)]
    pub app_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub build: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub protocol: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub device: Option<String>,
}

// MARK: Remote.swift

/// Kind 22: why the host is about to close this session. Nil fields are left out, so the classic
/// goodbyes are byte for byte `{"reason":"quit"}` and the like.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Goodbye {
    pub reason: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub message: Option<String>,
    #[serde(rename = "minimumVersion", skip_serializing_if = "Option::is_none", default)]
    pub minimum_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub reconnect: Option<bool>,
}

impl Goodbye {
    pub const REMOVED: &'static str = "removed";
    pub const REMOTE_OFF: &'static str = "remoteOff";
    pub const INTERNET_OFF: &'static str = "internetOff";
    pub const QUIT: &'static str = "quit";
    pub const BUSY: &'static str = "busy";
    pub const PAIRING_REQUIRED: &'static str = "pairingRequired";
    pub const UPDATE: &'static str = "update";

    pub fn reason(reason: &str) -> Goodbye {
        Goodbye { reason: reason.to_string(), message: None, minimum_version: None, reconnect: None }
    }
}

/// One way to reach the host from afar (kind 18). `kind`: "vpn", "lan" or "internet".
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MacAddress {
    pub host: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub port: Option<i64>,
    pub kind: String,
    pub via: String,
}

impl MacAddress {
    pub const VPN: &'static str = "vpn";
    pub const LAN: &'static str = "lan";
    pub const INTERNET: &'static str = "internet";
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MacInfo {
    pub v: i64,
    #[serde(rename = "macID")]
    pub mac_id: String,
    pub name: String,
    #[serde(rename = "issuedAt", with = "swift_f64")]
    pub issued_at: f64,
    #[serde(rename = "remoteAccess")]
    pub remote_access: bool,
    #[serde(rename = "remotePort")]
    pub remote_port: i64,
    pub internet: bool,
    pub addresses: Vec<MacAddress>,
}

/// Kind 18: `info` is base64 of MacInfo's exact JSON bytes, `key` base64 of the 65-byte X9.63
/// point, `sig` base64 of a DER ECDSA P-256/SHA-256 signature over those bytes.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignedMacInfo {
    pub info: String,
    pub key: String,
    pub sig: String,
}

/// Kind 19: the device's one message on a pairing connection.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairRequest {
    pub v: i64,
    pub method: String,
    pub proof: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub cable: Option<bool>,
}

impl PairRequest {
    pub const QR: &'static str = "qr";
    pub const CODE: &'static str = "code";
    pub const ASK: &'static str = "ask";
    pub const CANCEL: &'static str = "cancel";
    pub const VERSION: i64 = 1;
}

/// Kind 20: the Mac's answer to kind 19; the Mac closes the connection after it.
#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct PairResult {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub proof: Option<String>,
    #[serde(rename = "macID", skip_serializing_if = "Option::is_none", default)]
    pub mac_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub name: Option<String>,
    #[serde(rename = "recognitionKey", skip_serializing_if = "Option::is_none", default)]
    pub recognition_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub reason: Option<String>,
    #[serde(rename = "triesLeft", skip_serializing_if = "Option::is_none", default)]
    pub tries_left: Option<i64>,
    #[serde(rename = "retryAfter", with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub retry_after: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub message: Option<String>,
}

impl PairResult {
    pub const CODE: &'static str = "code";
    pub const CLOSED: &'static str = "closed";
    pub const EXPIRED: &'static str = "expired";
    pub const STOPPED: &'static str = "stopped";
    pub const BUSY: &'static str = "busy";
    pub const SHOWN: &'static str = "shown";
    pub const OPEN_ON_MAC: &'static str = "openOnMac";
    pub const LOCKED: &'static str = "locked";
    pub const CABLE: &'static str = "cable";

    pub fn refused(reason: &str) -> PairResult {
        PairResult { ok: false, reason: Some(reason.to_string()), ..Default::default() }
    }
}

// MARK: Pointer.swift, Gesture.swift, MacMenu.swift

/// Kind 26: where the host's pointer is in the streamed frame. Every field optional.
#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct MacPointer {
    #[serde(with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub x: Option<f64>,
    #[serde(with = "swift_f64::opt", skip_serializing_if = "Option::is_none", default)]
    pub y: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub inside: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub seen: Option<i64>,
}

impl MacPointer {
    /// A fraction as the wire carries it: 4 decimal places.
    pub fn rounded(v: f64) -> f64 {
        (v * 10_000.0).round() / 10_000.0
    }
}

/// Kind 28 (device → host).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrackpadGesture {
    pub gesture: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub fingers: Option<i64>,
}

#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct MacMenuItem {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub separator: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub mark: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub submenu: Option<bool>,
}

/// Kind 24 (host → device). The Rust hosts send none (no Menus button on the device).
#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct MacMenu {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub version: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub app: Option<String>,
    #[serde(rename = "bundleID", skip_serializing_if = "Option::is_none", default)]
    pub bundle_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub menus: Option<Vec<MacMenuItem>>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub answering: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub menu: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub items: Option<Vec<MacMenuItem>>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub more: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub pressed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub stale: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub note: Option<String>,
}

/// Kinds 27 and 25 (device → host).
#[derive(Clone, Debug, PartialEq, Default, Serialize, Deserialize)]
pub struct FetchMenu {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub version: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub token: Option<i64>,
}

pub type PressMenuItem = FetchMenu;

#[cfg(test)]
mod tests {
    use super::*;

    fn j<T: Serialize>(v: &T) -> String {
        String::from_utf8(to_json(v)).unwrap()
    }

    #[test]
    fn stream_source_matches_swift_and_sillclient() {
        // sillclient.py's `source()`.
        assert_eq!(j(&StreamSource::Desktop), r#"{"desktop":{}}"#);
        assert_eq!(j(&StreamSource::None), r#"{"none":{}}"#);
        assert_eq!(j(&StreamSource::Window(42)), r#"{"window":{"_0":42}}"#);
        for s in [StreamSource::Desktop, StreamSource::None, StreamSource::Window(4_000_000_000)] {
            assert_eq!(from_json::<StreamSource>(&to_json(&s)), Some(s));
        }
        // Swift refuses two keys and unknown cases.
        assert_eq!(from_json::<StreamSource>(br#"{"desktop":{},"none":{}}"#), None);
        assert_eq!(from_json::<StreamSource>(br#"{"display":{}}"#), None);
        assert_eq!(from_json::<StreamSource>(br#"{"window":{}}"#), None);
    }

    #[test]
    fn input_events_match_sillclient() {
        // sillclient.py's pointer_input and key_input, and the --input sample in its header.
        let p: InputEvent = from_json(br#"{"pointer": {"_0": "leftDown", "x": 0.5, "y": 0.25}}"#).unwrap();
        assert_eq!(p, InputEvent::Pointer { action: PointerAction::LeftDown, x: 0.5, y: 0.25 });
        let k: InputEvent = from_json(br#"{"key": {"down": true, "hidUsage": 44, "modifiers": 1048576}}"#).unwrap();
        assert_eq!(k, InputEvent::Key { hid_usage: 44, down: true, modifiers: modifiers::COMMAND });
        let g: InputEvent = from_json(br#"{"scrollGesture":{"_0":"began","x":0.5,"y":0.5}}"#).unwrap();
        assert_eq!(g, InputEvent::ScrollGesture { phase: ScrollPhase::Began, x: 0.5, y: 0.5 });
        let s: InputEvent = from_json(br#"{"scroll":{"x":0.1,"y":0.2,"dx":0,"dy":-0.05}}"#).unwrap();
        assert_eq!(s, InputEvent::Scroll { x: 0.1, y: 0.2, dx: 0.0, dy: -0.05 });
        let t: InputEvent = from_json(r#"{"text":{"_0":"hé\n"}}"#.as_bytes()).unwrap();
        assert_eq!(t, InputEvent::Text("hé\n".into()));
        // Round trips, and Swift's whole-number doubles.
        assert_eq!(j(&InputEvent::Pointer { action: PointerAction::Move, x: 1.0, y: 0.5 }), r#"{"pointer":{"_0":"move","x":1,"y":0.5}}"#);
        for e in [p, k, g, s, t] {
            assert_eq!(from_json::<InputEvent>(&to_json(&e)), Some(e));
        }
        assert_eq!(from_json::<InputEvent>(br#"{"pointer":{"_0":"middleDown","x":0,"y":0}}"#), None);
        assert_eq!(from_json::<InputEvent>(br#"{"key":{"hidUsage":70000,"down":true,"modifiers":0}}"#), None);
    }

    #[test]
    fn host_settings_state_matches_swift_capture() {
        // Captured from SillHost --synthetic (kind 16), keys in Swift's (hash) order.
        let swift = br#"{"persistent":false,"virtualDisplayAvailable":false,"softwareEncoder":true,"answering":1,"virtualDisplayNote":"Start SillHost with --virtual-display to use it.","settings":{"virtualDisplay":false,"directWireless":false,"bitrate":8000000,"captureScale":2,"maxFPS":120,"prioritizeSpeed":false}}"#;
        let s: HostSettingsState = from_json(swift).unwrap();
        assert_eq!(s.answering, Some(1));
        assert_eq!(s.settings.capture_scale, 2.0);
        assert_eq!(s.settings.direct_wireless, Some(false));
        let back: serde_json::Value = serde_json::from_slice(&to_json(&s)).unwrap();
        let orig: serde_json::Value = serde_json::from_slice(swift).unwrap();
        assert_eq!(back, orig);
        // A whole capture scale is written as Swift writes it.
        assert!(String::from_utf8(to_json(&s)).unwrap().contains(r#""captureScale":2,"#));
        // Without directWireless, the key is absent.
        let mut t = s.clone();
        t.settings.direct_wireless = None;
        t.answering = None;
        let text = j(&t);
        assert!(!text.contains("directWireless") && !text.contains("answering"));
    }

    #[test]
    fn change_settings_from_sillclient() {
        let c: HostSettingsChange = from_json(br#"{"token": 1, "bitrate": 25000000}"#).unwrap();
        assert_eq!(c.token, Some(1));
        assert_eq!(c.bitrate, Some(25_000_000));
        assert!(!c.is_empty());
        let c: HostSettingsChange = from_json(br#"{"token": 2, "captureScale": 1}"#).unwrap();
        assert_eq!(c.capture_scale, Some(1.0));
        let c: HostSettingsChange = from_json(br#"{"token": 3}"#).unwrap();
        assert!(c.is_empty());
    }

    #[test]
    fn window_list_matches_swift_capture_keys() {
        let swift = br#"{"macName":"Mac Studio","active":{"desktop":{}},"protocol":1,"windows":[{"appName":"Notes","width":1440,"id":4902,"height":868,"title":"All iCloud","bundleID":"com.apple.Notes"}],"launchID":"180732A2-5ABA-401D-85BD-953200C5AFD8","gestures":1}"#;
        let l: WindowList = from_json(swift).unwrap();
        assert_eq!(l.active, StreamSource::Desktop);
        assert_eq!(l.windows[0].bundle_id, "com.apple.Notes");
        assert_eq!(l.host_version, None);
        let back: serde_json::Value = serde_json::from_slice(&to_json(&l)).unwrap();
        assert_eq!(back, serde_json::from_slice::<serde_json::Value>(swift).unwrap());
    }

    #[test]
    fn viewport_and_stats_from_sillclient() {
        let v: Viewport = from_json(br#"{"width": 1117, "height": 642, "scale": null, "fps": 120}"#).unwrap();
        assert_eq!(v.scale, None);
        assert_eq!(v.fps, Some(120));
        let s: ClientStats = from_json(br#"{"fps": 0, "frameAgeMs": 0, "rttMs": 0, "device": "sillclient"}"#).unwrap();
        assert_eq!(s.device, "sillclient");
        assert_eq!(s.rtt_max_ms, None);
    }

    #[test]
    fn goodbye_quit_is_byte_exact() {
        assert_eq!(j(&Goodbye::reason(Goodbye::QUIT)), r#"{"reason":"quit"}"#);
    }

    #[test]
    fn hello_and_pair_request_from_sillclient() {
        let h: Hello = from_json(br#"{"appVersion": "1.0", "protocol": 1, "device": "sillclient"}"#).unwrap();
        assert_eq!(h.protocol, Some(1));
        let h: Hello = from_json(b"{}").unwrap();
        assert_eq!(h, Hello::default());
        let r: PairRequest =
            from_json(br#"{"v": 1, "method": "ask", "proof": "", "name": "sillclient", "model": "sillclient", "cable": true}"#).unwrap();
        assert_eq!(r.method, "ask");
        assert_eq!(r.cable, Some(true));
        assert_eq!(j(&PairResult::refused(PairResult::SHOWN)), r#"{"ok":false,"reason":"shown"}"#);
    }
}
