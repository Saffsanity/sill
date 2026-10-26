//! The pointer's arithmetic for SendInput: desktop pixels as the 0…65535 coordinates of
//! MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, and a device's scroll in pixels as wheel units.
//! Pure: tested anywhere.

/// The virtual screen (every monitor), in physical pixels: GetSystemMetrics' SM_XVIRTUALSCREEN,
/// SM_YVIRTUALSCREEN, SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN in a per-monitor-aware process.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VirtualScreen {
    pub left: i32,
    pub top: i32,
    pub width: i32,
    pub height: i32,
}

impl VirtualScreen {
    /// A desktop position as SendInput's absolute coordinates on the virtual desktop. Windows
    /// takes a normalized n to pixel (n × size) >> 16, so this aims at the middle of the pixel
    /// the position falls in, and every pixel is reached exactly. Positions off the screen are
    /// clamped to its edge.
    pub fn normalize(&self, x: f64, y: f64) -> (i32, i32) {
        (axis(x, self.left, self.width), axis(y, self.top, self.height))
    }

    /// The pixel Windows puts the pointer on for normalized coordinates (its own arithmetic: for
    /// the tests).
    #[cfg(test)]
    pub fn denormalize(&self, nx: i32, ny: i32) -> (i32, i32) {
        (
            self.left + ((nx as i64 * self.width as i64) >> 16) as i32,
            self.top + ((ny as i64 * self.height as i64) >> 16) as i32,
        )
    }
}

fn axis(v: f64, origin: i32, size: i32) -> i32 {
    if size <= 0 {
        return 0;
    }
    let pixel = if v.is_finite() { (v - origin as f64).floor() } else { 0.0 };
    let pixel = pixel.clamp(0.0, (size - 1) as f64);
    let n = ((pixel + 0.5) * 65536.0 / size as f64).floor();
    n.clamp(0.0, 65535.0) as i32
}

/// One wheel notch (WHEEL_DELTA).
pub const WHEEL_DELTA: f64 = 120.0;

/// How far one notch moves content, in pixels. Windows scrolls three lines a notch by default, and
/// a line is about 16 to 20 px in most apps at 100 %: about 50 px. Apps that scroll smoothly take
/// fractions of a notch, so a device's slow drag scrolls slowly.
pub const PIXELS_PER_NOTCH: f64 = 50.0;

/// The most wheel units one event carries (a fling's first delta can be large).
pub const MAX_WHEEL_PER_EVENT: i32 = 120 * 20;

/// A device's scroll as wheel units, carrying what rounding leaves into the next event so a slow
/// drag made of sub-unit steps still scrolls (the Mac's scrollRemainder).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct WheelAccumulator {
    rem_x: f64,
    rem_y: f64,
}

impl WheelAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Forget the remainder (a gesture's end).
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// `dx`, `dy` are pixels the content should move, natural sign (platform.rs: positive dy moves
    /// content down). Returns (vertical, horizontal) wheel units: MOUSEEVENTF_WHEEL's positive is
    /// the wheel rotated away from the user (content moves down), MOUSEEVENTF_HWHEEL's positive
    /// tilts right (content moves left), so the horizontal is negated.
    pub fn take(&mut self, dx: f64, dy: f64) -> (i32, i32) {
        let per_pixel = WHEEL_DELTA / PIXELS_PER_NOTCH;
        let (dx, dy) = (finite(dx), finite(dy));
        let exact_y = dy * per_pixel + self.rem_y;
        let exact_x = -dx * per_pixel + self.rem_x;
        let max = MAX_WHEEL_PER_EVENT as f64;
        let wy = exact_y.round().clamp(-max, max);
        let wx = exact_x.round().clamp(-max, max);
        self.rem_y = exact_y - wy;
        self.rem_x = exact_x - wx;
        // After a clamp the remainder is the clamped excess: drop it rather than scroll on later.
        if self.rem_y.abs() >= 1.0 {
            self.rem_y = 0.0;
        }
        if self.rem_x.abs() >= 1.0 {
            self.rem_x = 0.0;
        }
        (wy as i32, wx as i32)
    }
}

fn finite(v: f64) -> f64 {
    if v.is_finite() {
        v
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_pixel_round_trips() {
        for (left, top, width, height) in [
            (0, 0, 1920, 1080),
            (0, 0, 3840, 2160),
            (-1920, 0, 3840, 1080),
            (-2560, -400, 6400, 1840),
            (0, 0, 1366, 768),
            (0, 0, 7, 3),
        ] {
            let s = VirtualScreen { left, top, width, height };
            for px in left..left + width {
                let (nx, _) = s.normalize(px as f64 + 0.3, top as f64);
                assert!((0..=65535).contains(&nx));
                assert_eq!(s.denormalize(nx, 0).0, px, "screen {s:?} pixel {px}");
            }
            for py in top..top + height {
                let (_, ny) = s.normalize(left as f64, py as f64);
                assert_eq!(s.denormalize(0, ny).1, py);
            }
        }
    }

    #[test]
    fn off_screen_clamps_to_the_edge() {
        let s = VirtualScreen { left: -1920, top: 0, width: 3840, height: 1080 };
        let (nx, ny) = s.normalize(-5000.0, 99999.0);
        assert_eq!(s.denormalize(nx, ny), (-1920, 1079));
        let (nx, ny) = s.normalize(f64::NAN, f64::INFINITY);
        assert!((0..=65535).contains(&nx) && (0..=65535).contains(&ny));
        let (nx, _) = s.normalize(1919.9, 0.0);
        assert_eq!(s.denormalize(nx, 0).0, 1919);
    }

    #[test]
    fn wheel_signs() {
        let mut w = WheelAccumulator::new();
        // Content down (positive dy) is the wheel forward (positive).
        assert_eq!(w.take(0.0, 50.0), (120, 0));
        // Content right (positive dx) is a tilt left (negative HWHEEL).
        assert_eq!(w.take(50.0, 0.0), (0, -120));
        assert_eq!(w.take(-25.0, -25.0), (-60, 60));
    }

    #[test]
    fn slow_drags_add_up() {
        let mut w = WheelAccumulator::new();
        let mut total = 0;
        for _ in 0..100 {
            total += w.take(0.0, 0.1).0; // 0.24 units each
        }
        assert_eq!(total, 24);
    }

    #[test]
    fn huge_deltas_clamp_and_drop_the_excess() {
        let mut w = WheelAccumulator::new();
        assert_eq!(w.take(0.0, 1e6), (MAX_WHEEL_PER_EVENT, 0));
        assert_eq!(w.take(0.0, 0.0), (0, 0));
        assert_eq!(w.take(f64::NAN, f64::INFINITY), (0, 0));
    }

    #[test]
    fn reset_forgets_the_remainder() {
        let mut w = WheelAccumulator::new();
        w.take(0.0, 0.2);
        w.reset();
        assert_eq!(w, WheelAccumulator::new());
    }
}
