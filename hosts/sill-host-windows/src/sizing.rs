//! The encoded picture's size for a captured size: StreamConfig.scale applied, rounded down to
//! even numbers (HEVC's 4:2:0), kept within what hardware HEVC encoders take. Pure: tested anywhere.

/// The longest side the encoder is given. NVENC and Quick Sync take 8192, but many AMD and older
/// GPUs stop at 4096; a larger source is scaled down to this, keeping its shape.
pub const MAX_SIDE: u32 = 4096;
/// The smallest side: encoders refuse tiny pictures (a 100 px window is scaled up to this).
pub const MIN_SIDE: u32 = 64;

pub fn output_size(width: u32, height: u32, scale: f64) -> (u32, u32) {
    let scale = if scale.is_finite() && scale > 0.0 { scale.min(1.0) } else { 1.0 };
    let mut w = (width.max(1) as f64 * scale).max(1.0);
    let mut h = (height.max(1) as f64 * scale).max(1.0);
    let long = w.max(h);
    if long > MAX_SIDE as f64 {
        let f = MAX_SIDE as f64 / long;
        w *= f;
        h *= f;
    }
    let even = |v: f64| ((v.floor() as u32) & !1).clamp(MIN_SIDE, MAX_SIDE);
    (even(w), even(h))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scale_and_even() {
        assert_eq!(output_size(1920, 1080, 1.0), (1920, 1080));
        assert_eq!(output_size(1921, 1081, 1.0), (1920, 1080));
        assert_eq!(output_size(3840, 2160, 0.5), (1920, 1080));
        assert_eq!(output_size(2559, 1439, 0.5), (1278, 718));
    }

    #[test]
    fn bounds() {
        assert_eq!(output_size(7680, 4320, 1.0), (4096, 2304));
        assert_eq!(output_size(3440, 1440, 1.0), (3440, 1440));
        assert_eq!(output_size(10000, 100, 1.0), (4096, 64));
        assert_eq!(output_size(30, 20, 1.0), (64, 64));
        assert_eq!(output_size(0, 0, 1.0), (64, 64));
    }

    #[test]
    fn odd_scales_fall_back() {
        assert_eq!(output_size(1920, 1080, f64::NAN), (1920, 1080));
        assert_eq!(output_size(1920, 1080, 0.0), (1920, 1080));
        assert_eq!(output_size(1920, 1080, 2.0), (1920, 1080));
    }
}
