//! BGRA pictures made smaller for the encoder (StreamConfig.scale: 0.5 is the Mac's "Standard"
//! resolution of a HiDPI source). Each output pixel is the average of the source pixels its area
//! covers (a box filter: exact 2:1 is a plain 2×2 mean, the case that matters), which keeps text
//! legible where nearest-neighbour would drop strokes. Integer arithmetic, one pass per row.
//!
//! Pure; compiled and tested on every platform.

/// `src` is sw×sh BGRA (tightly packed); returns dw×dh BGRA. dw ≤ sw and dh ≤ sh.
pub fn downscale_bgra(src: &[u8], sw: u32, sh: u32, dw: u32, dh: u32) -> Vec<u8> {
    let (sw, sh, dw, dh) = (sw as usize, sh as usize, dw.max(1) as usize, dh.max(1) as usize);
    assert!(src.len() >= sw * sh * 4 && dw <= sw && dh <= sh);
    let mut out = vec![0u8; dw * dh * 4];
    if (dw, dh) == (sw, sh) {
        out.copy_from_slice(&src[..sw * sh * 4]);
        return out;
    }
    if sw == dw * 2 && sh == dh * 2 {
        for y in 0..dh {
            let r0 = &src[(2 * y) * sw * 4..(2 * y + 1) * sw * 4];
            let r1 = &src[(2 * y + 1) * sw * 4..(2 * y + 2) * sw * 4];
            let o = &mut out[y * dw * 4..(y + 1) * dw * 4];
            for x in 0..dw {
                for c in 0..4 {
                    let s = r0[8 * x + c] as u32 + r0[8 * x + 4 + c] as u32 + r1[8 * x + c] as u32 + r1[8 * x + 4 + c] as u32;
                    o[4 * x + c] = ((s + 2) / 4) as u8;
                }
            }
        }
        return out;
    }
    // General ratio: each output pixel averages the source rectangle [x0, x1) × [y0, y1).
    let xs: Vec<(usize, usize)> = (0..dw).map(|x| span(x, dw, sw)).collect();
    let mut acc = vec![0u32; dw * 4];
    for y in 0..dh {
        let (y0, y1) = span(y, dh, sh);
        acc.iter_mut().for_each(|a| *a = 0);
        for sy in y0..y1 {
            let row = &src[sy * sw * 4..(sy + 1) * sw * 4];
            for (x, &(x0, x1)) in xs.iter().enumerate() {
                for sx in x0..x1 {
                    for c in 0..4 {
                        acc[4 * x + c] += row[4 * sx + c] as u32;
                    }
                }
            }
        }
        let o = &mut out[y * dw * 4..(y + 1) * dw * 4];
        for (x, &(x0, x1)) in xs.iter().enumerate() {
            let n = ((x1 - x0) * (y1 - y0)) as u32;
            for c in 0..4 {
                o[4 * x + c] = ((acc[4 * x + c] + n / 2) / n) as u8;
            }
        }
    }
    out
}

/// The source range output index `i` of `d` covers in `s` (never empty).
fn span(i: usize, d: usize, s: usize) -> (usize, usize) {
    let a = i * s / d;
    let b = ((i + 1) * s / d).max(a + 1).min(s);
    (a, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(w: u32, h: u32, px: [u8; 4]) -> Vec<u8> {
        px.iter().copied().cycle().take((w * h * 4) as usize).collect()
    }

    #[test]
    fn identity_half_and_odd_ratios() {
        let src = solid(8, 6, [10, 20, 30, 255]);
        assert_eq!(downscale_bgra(&src, 8, 6, 8, 6), src);
        assert_eq!(downscale_bgra(&src, 8, 6, 4, 3), solid(4, 3, [10, 20, 30, 255]));
        assert_eq!(downscale_bgra(&src, 8, 6, 5, 4), solid(5, 4, [10, 20, 30, 255]));
        assert_eq!(downscale_bgra(&src, 8, 6, 1, 1), solid(1, 1, [10, 20, 30, 255]));
    }

    #[test]
    fn half_averages_two_by_two() {
        // A 2×2 checker of black and white becomes mid grey.
        let mut src = Vec::new();
        for y in 0..4 {
            for x in 0..4 {
                let v = if (x + y) % 2 == 0 { 0 } else { 255 };
                src.extend_from_slice(&[v, v, v, 255]);
            }
        }
        let out = downscale_bgra(&src, 4, 4, 2, 2);
        assert!(out.chunks(4).all(|p| p[0] == 128 && p[3] == 255), "{out:?}");
    }

    #[test]
    fn a_left_right_split_stays_split() {
        // Left half blue, right half red, 1920×1080 → 1280×720 (2:3, not a power of two).
        let (w, h) = (1920u32, 1080u32);
        let mut src = Vec::with_capacity((w * h * 4) as usize);
        for _ in 0..h {
            for x in 0..w {
                src.extend_from_slice(if x < w / 2 { &[255, 0, 0, 255] } else { &[0, 0, 255, 255] });
            }
        }
        let out = downscale_bgra(&src, w, h, 1280, 720);
        assert_eq!(out.len(), 1280 * 720 * 4);
        assert_eq!(&out[0..4], &[255, 0, 0, 255]);
        assert_eq!(&out[(1279 * 4)..(1280 * 4)], &[0, 0, 255, 255]);
    }
}
