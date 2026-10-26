//! The host's knobs (HostConfig.swift, DeviceSettings.swift): what a device sees as kind 16 and
//! may change with kind 17, and how they become a `StreamConfig`.

use sill_protocol::messages::{settings_choices, AwayQuality, HostSettingsChange, StreamSettings};

#[derive(Clone, Debug, PartialEq)]
pub struct HostConfig {
    /// Ceiling for the stream rate; each device asks for its own panel's rate (60 until it does).
    pub max_fps: i64,
    /// 2 = "Retina" (the source's full pixel size), 1 = "Standard" (half each way).
    pub capture_scale: f64,
    /// Bits per second per 60 fps; a faster stream gets proportionally more.
    pub bitrate: i64,
    /// The away pair (kind 16's `away`, sent only by a host with an identity).
    pub away_bitrate: i64,
    pub away_capture_scale: f64,
    pub prioritize_speed: bool,
}

impl HostConfig {
    /// `HostConfig.standard`'s streaming knobs: 120 fps ceiling, Retina, Balanced (15 Mbps).
    pub fn standard() -> HostConfig {
        HostConfig {
            max_fps: 120,
            capture_scale: 2.0,
            bitrate: 15_000_000,
            away_bitrate: 4_000_000,
            away_capture_scale: 1.0,
            prioritize_speed: false,
        }
    }

    /// Within what the pipeline supports (`validated()`): 24…120 fps, 2 or 1, 1–200 Mbps.
    pub fn validated(mut self) -> HostConfig {
        self.max_fps = self.max_fps.clamp(24, 120);
        self.capture_scale = if self.capture_scale >= 1.5 { 2.0 } else { 1.0 };
        self.away_capture_scale = if self.away_capture_scale >= 1.5 { 2.0 } else { 1.0 };
        self.bitrate = self.bitrate.clamp(1_000_000, 200_000_000);
        self.away_bitrate = self.away_bitrate.clamp(1_000_000, 200_000_000);
        self
    }

    /// As a device sees them (kind 16's `settings`). The Rust hosts have no virtual display and no
    /// Direct Wireless: `virtualDisplay` is false and `directWireless` absent (no row on the device).
    pub fn stream_settings(&self) -> StreamSettings {
        StreamSettings {
            max_fps: self.max_fps,
            bitrate: self.bitrate,
            capture_scale: self.capture_scale,
            prioritize_speed: self.prioritize_speed,
            virtual_display: false,
            direct_wireless: None,
        }
    }

    /// As a device whose connection is away (or not) sees them: its Quality and Resolution are the
    /// away pair's for a connection the host counts as away.
    pub fn stream_settings_for(&self, away: bool) -> StreamSettings {
        let mut s = self.stream_settings();
        if away {
            s.bitrate = self.away_bitrate;
            s.capture_scale = self.away_capture_scale;
        }
        s
    }

    /// The quality the pipeline runs: the away pair while every connected device is away.
    pub fn effective(&self, away: bool) -> (i64, f64) {
        if away {
            (self.away_bitrate, self.away_capture_scale)
        } else {
            (self.bitrate, self.capture_scale)
        }
    }

    pub fn away_quality(&self, this_connection_away: bool, away_running: bool) -> AwayQuality {
        AwayQuality {
            home_bitrate: self.bitrate,
            home_capture_scale: self.capture_scale,
            away_bitrate: self.away_bitrate,
            away_capture_scale: self.away_capture_scale,
            this_connection_away,
            away_running,
        }
    }

    /// A change from a device away from home: its Quality and Resolution land on the away pair.
    pub fn applying_away(&self, c: &HostSettingsChange) -> HostConfig {
        let mut n = self.clone();
        if let Some(v) = c.bitrate {
            n.away_bitrate = v;
        }
        if let Some(v) = c.capture_scale {
            n.away_capture_scale = v;
        }
        let rest = HostSettingsChange { bitrate: None, capture_scale: None, ..c.clone() };
        n.applying(&rest)
    }

    /// This config with a device's (already accepted) change laid over it.
    pub fn applying(&self, c: &HostSettingsChange) -> HostConfig {
        let mut n = self.clone();
        if let Some(v) = c.max_fps {
            n.max_fps = v;
        }
        if let Some(v) = c.bitrate {
            n.bitrate = v;
        }
        if let Some(v) = c.capture_scale {
            n.capture_scale = v;
        }
        if let Some(v) = c.prioritize_speed {
            n.prioritize_speed = v;
        }
        n
    }

    /// "frame rate limit 120 → 60 fps, bitrate 15 → 8 Mbps per 60 fps, Retina → points".
    pub fn changes(&self, new: &HostConfig) -> String {
        let scale = |s: f64| if s >= 1.5 { "Retina" } else { "points" };
        let on_off = |b: bool| if b { "on" } else { "off" };
        let mut parts = Vec::new();
        if self.max_fps != new.max_fps {
            parts.push(format!("frame rate limit {} → {} fps", self.max_fps, new.max_fps));
        }
        if self.bitrate != new.bitrate {
            parts.push(format!(
                "bitrate {} → {} Mbps per 60 fps",
                settings_choices::mbps(self.bitrate),
                settings_choices::mbps(new.bitrate)
            ));
        }
        if self.capture_scale != new.capture_scale {
            parts.push(format!("{} → {}", scale(self.capture_scale), scale(new.capture_scale)));
        }
        if self.away_bitrate != new.away_bitrate {
            parts.push(format!(
                "away bitrate {} → {} Mbps per 60 fps",
                settings_choices::mbps(self.away_bitrate),
                settings_choices::mbps(new.away_bitrate)
            ));
        }
        if self.away_capture_scale != new.away_capture_scale {
            parts.push(format!("away {} → {}", scale(self.away_capture_scale), scale(new.away_capture_scale)));
        }
        if self.prioritize_speed != new.prioritize_speed {
            parts.push(format!("speed {} → {}", on_off(self.prioritize_speed), on_off(new.prioritize_speed)));
        }
        if parts.is_empty() {
            "no change".into()
        } else {
            parts.join(", ")
        }
    }
}

/// What a device may change (`DeviceSettings.accepted`): exactly the Mac menu's values, per field;
/// the rest of a change still applies. The virtual display can only be turned off (it never runs
/// here), and Direct Wireless is not a setting of these hosts.
pub fn accepted(c: &HostSettingsChange) -> (HostSettingsChange, Vec<String>) {
    let mut ok = HostSettingsChange { prioritize_speed: c.prioritize_speed, ..Default::default() };
    let mut refused = Vec::new();
    if c.direct_wireless.is_some() {
        refused.push("direct wireless (not available on this host)".to_string());
    }
    if let Some(v) = c.max_fps {
        if settings_choices::MAX_FPS.contains(&v) {
            ok.max_fps = Some(v)
        } else {
            refused.push(format!("frame rate limit {v}"))
        }
    }
    if let Some(v) = c.bitrate {
        if settings_choices::BITRATE.contains(&v) {
            ok.bitrate = Some(v)
        } else {
            refused.push(format!("bitrate {v}"))
        }
    }
    if let Some(v) = c.capture_scale {
        if settings_choices::CAPTURE_SCALE.contains(&v) {
            ok.capture_scale = Some(v)
        } else {
            refused.push(format!("capture scale {v}"))
        }
    }
    if let Some(v) = c.virtual_display {
        if !v {
            ok.virtual_display = Some(false)
        } else {
            refused.push("virtual display (not available on this host)".to_string())
        }
    }
    (ok, refused)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepted_is_per_field() {
        let c = HostSettingsChange {
            token: Some(3),
            bitrate: Some(25_000_000),
            max_fps: Some(90),
            capture_scale: Some(1.0),
            virtual_display: Some(true),
            ..Default::default()
        };
        let (ok, refused) = accepted(&c);
        assert_eq!(ok.bitrate, Some(25_000_000));
        assert_eq!(ok.max_fps, None);
        assert_eq!(ok.capture_scale, Some(1.0));
        assert_eq!(ok.virtual_display, None);
        assert_eq!(refused, vec!["frame rate limit 90", "virtual display (not available on this host)"]);
        let n = HostConfig::standard().applying(&ok);
        assert_eq!(HostConfig::standard().changes(&n), "bitrate 15 → 25 Mbps per 60 fps, Retina → points");
    }

    #[test]
    fn extreme_and_refusals_match_swift() {
        let (ok, refused) = accepted(&HostSettingsChange { bitrate: Some(150_000_000), ..Default::default() });
        assert_eq!(ok.bitrate, Some(150_000_000));
        assert!(refused.is_empty());
        let (ok, refused) = accepted(&HostSettingsChange { bitrate: Some(200_000_000), ..Default::default() });
        assert_eq!(ok.bitrate, None);
        assert_eq!(refused, vec!["bitrate 200000000"]);
    }
}
