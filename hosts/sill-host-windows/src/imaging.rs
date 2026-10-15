//! Pixels as the files the protocol carries: window thumbnails as JPEG (about 400 px on the long
//! side), app icons and the cursor as PNG. GDI hands out 32-bit BGRA rows; cursors come as
//! colour-plus-mask or two-mask (monochrome) bitmaps. Pure: tested anywhere.

use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::PngEncoder;
use image::{ExtendedColorType, ImageEncoder, RgbImage, RgbaImage};

/// The long side of a thumbnail (platform.rs: about 400 px).
pub const THUMBNAIL_LONG_SIDE: u32 = 400;
/// JPEG quality for thumbnails (the Mac's 0.6).
pub const THUMBNAIL_QUALITY: u8 = 60;

/// A 32-bit BGRA bitmap, top-down, `stride` bytes per row.
#[derive(Clone, Copy, Debug)]
pub struct Bgra<'a> {
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub data: &'a [u8],
}

impl Bgra<'_> {
    fn valid(&self) -> bool {
        self.width > 0
            && self.height > 0
            && self.stride >= self.width as usize * 4
            && self.data.len() >= self.stride * (self.height as usize - 1) + self.width as usize * 4
    }

    fn pixel(&self, x: u32, y: u32) -> [u8; 4] {
        let i = y as usize * self.stride + x as usize * 4;
        [self.data[i], self.data[i + 1], self.data[i + 2], self.data[i + 3]]
    }
}

/// The size that fits `width`×`height` into `long_side` on its longer edge, never larger than it
/// was, at least 1×1.
pub fn fit(width: u32, height: u32, long_side: u32) -> (u32, u32) {
    let long = width.max(height).max(1);
    if long <= long_side {
        return (width.max(1), height.max(1));
    }
    let scale = long_side as f64 / long as f64;
    (
        ((width as f64 * scale).round() as u32).max(1),
        ((height as f64 * scale).round() as u32).max(1),
    )
}

/// A JPEG thumbnail of a BGRA bitmap (alpha ignored: a window is opaque), fitted into
/// `THUMBNAIL_LONG_SIDE`.
pub fn thumbnail_jpeg(src: Bgra) -> Option<Vec<u8>> {
    if !src.valid() {
        return None;
    }
    let mut rgb = RgbImage::new(src.width, src.height);
    for (x, y, px) in rgb.enumerate_pixels_mut() {
        let [b, g, r, _] = src.pixel(x, y);
        *px = image::Rgb([r, g, b]);
    }
    let (w, h) = fit(src.width, src.height, THUMBNAIL_LONG_SIDE);
    let scaled = if (w, h) == (src.width, src.height) {
        rgb
    } else {
        image::imageops::resize(&rgb, w, h, image::imageops::FilterType::Triangle)
    };
    let mut out = Vec::new();
    JpegEncoder::new_with_quality(&mut out, THUMBNAIL_QUALITY)
        .write_image(scaled.as_raw(), w, h, ExtendedColorType::Rgb8)
        .ok()?;
    Some(out)
}

/// A PNG of straight-alpha RGBA pixels.
pub fn png_rgba(width: u32, height: u32, rgba: &[u8]) -> Option<Vec<u8>> {
    if width == 0 || height == 0 || rgba.len() < (width * height * 4) as usize {
        return None;
    }
    let mut out = Vec::new();
    PngEncoder::new(&mut out)
        .write_image(&rgba[..(width * height * 4) as usize], width, height, ExtendedColorType::Rgba8)
        .ok()?;
    Some(out)
}

/// An icon: BGRA, its alpha premultiplied as the shell's bitmaps have it, as a PNG scaled to
/// `size`×`size` (kept square; an icon that is not is fitted and centred).
pub fn icon_png(src: Bgra, premultiplied: bool, size: u32) -> Option<Vec<u8>> {
    if !src.valid() {
        return None;
    }
    let mut rgba = RgbaImage::new(src.width, src.height);
    for (x, y, px) in rgba.enumerate_pixels_mut() {
        let [b, g, r, a] = src.pixel(x, y);
        let (r, g, b) = if premultiplied { unpremultiply(r, g, b, a) } else { (r, g, b) };
        *px = image::Rgba([r, g, b, a]);
    }
    let (w, h) = fit(src.width, src.height, size);
    let scaled = if (w, h) == (src.width, src.height) {
        rgba
    } else {
        image::imageops::resize(&rgba, w, h, image::imageops::FilterType::Triangle)
    };
    let side = w.max(h);
    let mut canvas = RgbaImage::new(side, side);
    image::imageops::overlay(&mut canvas, &scaled, ((side - w) / 2) as i64, ((side - h) / 2) as i64);
    png_rgba(side, side, canvas.as_raw())
}

pub fn unpremultiply(r: u8, g: u8, b: u8, a: u8) -> (u8, u8, u8) {
    if a == 0 || a == 255 {
        return (r, g, b);
    }
    let f = |c: u8| ((c as u32 * 255 + a as u32 / 2) / a as u32).min(255) as u8;
    (f(r), f(g), f(b))
}

/// Whether a 1-bit-per-pixel mask row (MSB first) has bit `x` set.
fn bit(row: &[u8], x: u32) -> bool {
    row.get((x / 8) as usize).is_some_and(|byte| byte & (0x80 >> (x % 8)) != 0)
}

/// The bytes per row of a 1-bit DIB (rows are padded to 32 bits).
pub fn mask_stride(width: u32) -> usize {
    (width as usize).div_ceil(32) * 4
}

/// A colour cursor (GetIconInfo's hbmColor as top-down BGRA, and its AND mask) as straight RGBA.
/// A colour bitmap with any alpha carries its own transparency; one without takes it from the
/// mask (bit set: transparent, unless the colour is not black there, which inverts the screen:
/// drawn as half-transparent black, as nothing else can show it).
pub fn cursor_from_color(color: Bgra, and_mask: Option<&[u8]>) -> Option<Vec<u8>> {
    if !color.valid() {
        return None;
    }
    let (w, h) = (color.width, color.height);
    let stride = mask_stride(w);
    let has_alpha = (0..h).any(|y| (0..w).any(|x| color.pixel(x, y)[3] != 0));
    let mut out = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        let mask_row = and_mask.and_then(|m| m.get(y as usize * stride..(y as usize + 1) * stride));
        for x in 0..w {
            let [b, g, r, a] = color.pixel(x, y);
            if has_alpha {
                out.extend_from_slice(&[r, g, b, a]);
                continue;
            }
            let transparent = mask_row.is_some_and(|row| bit(row, x));
            if !transparent {
                out.extend_from_slice(&[r, g, b, 255]);
            } else if r | g | b != 0 {
                out.extend_from_slice(&[0, 0, 0, 128]);
            } else {
                out.extend_from_slice(&[0, 0, 0, 0]);
            }
        }
    }
    Some(out)
}

/// A monochrome cursor (hbmColor absent: hbmMask is twice as tall, the AND mask over the XOR
/// mask) as straight RGBA of `width`×`height`: AND 0 XOR 0 black, AND 0 XOR 1 white, AND 1 XOR 0
/// transparent, AND 1 XOR 1 inverted (the I-beam's body: drawn black with a white edge would need
/// the screen, so black, mostly opaque).
pub fn cursor_from_monochrome(width: u32, height: u32, mask: &[u8]) -> Option<Vec<u8>> {
    let stride = mask_stride(width);
    if width == 0 || height == 0 || mask.len() < stride * height as usize * 2 {
        return None;
    }
    let mut out = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height as usize {
        let and_row = &mask[y * stride..(y + 1) * stride];
        let xor_row = &mask[(y + height as usize) * stride..(y + height as usize + 1) * stride];
        for x in 0..width {
            let px = match (bit(and_row, x), bit(xor_row, x)) {
                (false, false) => [0, 0, 0, 255],
                (false, true) => [255, 255, 255, 255],
                (true, false) => [0, 0, 0, 0],
                (true, true) => [0, 0, 0, 220],
            };
            out.extend_from_slice(&px);
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fit_keeps_aspect_and_never_grows() {
        assert_eq!(fit(1920, 1080, 400), (400, 225));
        assert_eq!(fit(1080, 1920, 400), (225, 400));
        assert_eq!(fit(300, 200, 400), (300, 200));
        assert_eq!(fit(10000, 1, 400), (400, 1));
        assert_eq!(fit(0, 0, 400), (1, 1));
    }

    #[test]
    fn thumbnail_is_a_jpeg_of_the_fitted_size() {
        let (w, h) = (800u32, 600u32);
        let stride = w as usize * 4 + 16; // padded rows
        let mut data = vec![0u8; stride * h as usize];
        for y in 0..h as usize {
            for x in 0..w as usize {
                let i = y * stride + x * 4;
                data[i..i + 4].copy_from_slice(&[255, 0, 0, 0]); // blue in BGRA
            }
        }
        let jpeg = thumbnail_jpeg(Bgra { width: w, height: h, stride, data: &data }).unwrap();
        assert_eq!(&jpeg[..2], &[0xFF, 0xD8]);
        let img = image::load_from_memory(&jpeg).unwrap().to_rgb8();
        assert_eq!(img.dimensions(), (400, 300));
        let p = img.get_pixel(200, 150);
        assert!(p[2] > 200 && p[0] < 40, "blue stays blue: {p:?}");
    }

    #[test]
    fn bad_bitmaps_give_nothing() {
        assert!(thumbnail_jpeg(Bgra { width: 10, height: 10, stride: 40, data: &[0; 39] }).is_none());
        assert!(thumbnail_jpeg(Bgra { width: 0, height: 10, stride: 0, data: &[] }).is_none());
        assert!(png_rgba(2, 2, &[0; 15]).is_none());
    }

    #[test]
    fn icon_png_unpremultiplies_and_is_square() {
        let data = [64u8, 64, 64, 128, 0, 0, 255, 255]; // half-transparent grey, opaque red (BGRA)
        let png = icon_png(Bgra { width: 2, height: 1, stride: 8, data: &data }, true, 128).unwrap();
        let img = image::load_from_memory(&png).unwrap().to_rgba8();
        assert_eq!(img.dimensions(), (2, 2));
        assert_eq!(img.get_pixel(0, 0).0, [128, 128, 128, 128]);
        assert_eq!(img.get_pixel(1, 0).0, [255, 0, 0, 255]);
        assert_eq!(img.get_pixel(0, 1).0[3], 0);
    }

    #[test]
    fn unpremultiply_edges() {
        assert_eq!(unpremultiply(10, 20, 30, 0), (10, 20, 30));
        assert_eq!(unpremultiply(10, 20, 30, 255), (10, 20, 30));
        assert_eq!(unpremultiply(50, 100, 128, 128), (100, 199, 255));
        assert_eq!(unpremultiply(200, 0, 0, 100), (255, 0, 0)); // not premultiplied after all: clamped
    }

    #[test]
    fn monochrome_cursor_truth_table() {
        // 2×1: AND row then XOR row, each padded to 4 bytes.
        // pixel 0: AND 0 XOR 1 (white); pixel 1: AND 1 XOR 0 (transparent).
        let mut mask = vec![0u8; 8];
        mask[0] = 0b0100_0000; // AND: pixel 1 set
        mask[4] = 0b1000_0000; // XOR: pixel 0 set
        let rgba = cursor_from_monochrome(2, 1, &mask).unwrap();
        assert_eq!(&rgba[0..4], &[255, 255, 255, 255]);
        assert_eq!(&rgba[4..8], &[0, 0, 0, 0]);
        // AND 0 XOR 0 is black, AND 1 XOR 1 inverts.
        let mask = vec![0b0100_0000, 0, 0, 0, 0b0100_0000, 0, 0, 0];
        let rgba = cursor_from_monochrome(2, 1, &mask).unwrap();
        assert_eq!(&rgba[0..4], &[0, 0, 0, 255]);
        assert_eq!(rgba[7], 220);
        assert!(cursor_from_monochrome(2, 1, &[0; 7]).is_none());
    }

    #[test]
    fn colour_cursor_with_and_without_alpha() {
        // With alpha: taken as it is.
        let data = [10u8, 20, 30, 40, 0, 0, 0, 0];
        let rgba = cursor_from_color(Bgra { width: 2, height: 1, stride: 8, data: &data }, None).unwrap();
        assert_eq!(rgba, vec![30, 20, 10, 40, 0, 0, 0, 0]);
        // Without: the mask decides.
        let data = [10u8, 20, 30, 0, 0, 0, 0, 0];
        let mask = [0b0100_0000u8, 0, 0, 0];
        let rgba = cursor_from_color(Bgra { width: 2, height: 1, stride: 8, data: &data }, Some(&mask)).unwrap();
        assert_eq!(rgba, vec![30, 20, 10, 255, 0, 0, 0, 0]);
        // A set mask bit over a coloured pixel inverts: half-transparent black.
        let data = [0u8, 0, 0, 0, 255, 255, 255, 0];
        let rgba = cursor_from_color(Bgra { width: 2, height: 1, stride: 8, data: &data }, Some(&mask)).unwrap();
        assert_eq!(&rgba[4..8], &[0, 0, 0, 128]);
    }

    #[test]
    fn mask_rows_pad_to_32_bits() {
        assert_eq!(mask_stride(1), 4);
        assert_eq!(mask_stride(32), 4);
        assert_eq!(mask_stride(33), 8);
        assert_eq!(mask_stride(48), 8);
    }
}
