//! Pixel scrolling as wheel clicks. X has no pixel scroll for a faked pointer (XTest fakes buttons), so
//! the protocol's deltas (pixels the content should move, natural sign) add up until a click's worth
//! has gathered: button 4 scrolls up (the content moves down, positive dy), 5 down, 6 left (the
//! content moves right, positive dx) and 7 right. A gesture's end drops what is left over, so the next
//! gesture starts from zero and a trackpad's last pixels never turn into a stray click.
//!
//! Pure; compiled and tested on every platform.

/// Pixels of content per wheel click: GTK and Qt scroll about three lines (~50 px) per click, so a
/// device's stroke moves the content by about as much as it asked.
pub const PIXELS_PER_CLICK: f64 = 48.0;
/// At most this many clicks for one event (a malformed or huge delta from the wire).
pub const MAX_CLICKS: i64 = 40;

#[derive(Default, Debug)]
pub struct ScrollAccumulator {
    x: f64,
    y: f64,
}

impl ScrollAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a delta; returns the wheel buttons to click, in order (each one press and release).
    pub fn add(&mut self, dx: f64, dy: f64) -> Vec<u8> {
        if !dx.is_finite() || !dy.is_finite() {
            return Vec::new();
        }
        self.x += dx;
        self.y += dy;
        let mut out = Vec::new();
        let cy = (self.y / PIXELS_PER_CLICK).trunc() as i64;
        let cx = (self.x / PIXELS_PER_CLICK).trunc() as i64;
        self.y -= cy as f64 * PIXELS_PER_CLICK;
        self.x -= cx as f64 * PIXELS_PER_CLICK;
        let button_y = if cy > 0 { 4 } else { 5 };
        let button_x = if cx > 0 { 6 } else { 7 };
        out.extend(std::iter::repeat_n(button_y, cy.unsigned_abs().min(MAX_CLICKS as u64) as usize));
        out.extend(std::iter::repeat_n(button_x, cx.unsigned_abs().min(MAX_CLICKS as u64) as usize));
        out
    }

    /// A gesture began or ended: what was left over is dropped.
    pub fn reset(&mut self) {
        self.x = 0.0;
        self.y = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn small_deltas_add_up_to_clicks() {
        let mut s = ScrollAccumulator::new();
        let mut clicks = Vec::new();
        for _ in 0..10 {
            clicks.extend(s.add(0.0, 10.0)); // content down: scroll up
        }
        assert_eq!(clicks, vec![4, 4]); // 100 px = two clicks, 4 px left over
        s.reset();
        assert_eq!(s.add(0.0, -47.0), Vec::<u8>::new());
        assert_eq!(s.add(-60.0, -2.0), vec![5, 7]);
        assert_eq!(s.add(100.0, 0.0), vec![6]); // -12 left over, +100: 88 px, one click
    }

    #[test]
    fn junk_is_dropped_and_huge_is_capped() {
        let mut s = ScrollAccumulator::new();
        assert!(s.add(f64::NAN, 1.0).is_empty());
        assert!(s.add(f64::INFINITY, 1.0).is_empty());
        assert_eq!(s.add(0.0, 1e9).len(), MAX_CLICKS as usize);
    }
}
