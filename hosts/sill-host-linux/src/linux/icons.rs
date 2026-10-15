//! App icons as ~128 px PNGs, best effort: the desktop entry's Icon (a path, or a name looked up in the
//! icon themes: hicolor first, then any other theme installed, then /usr/share/pixmaps), else the
//! window's own _NET_WM_ICON. PNG files only: SVG icons would need an SVG renderer, and the permissive
//! ones are heavy; a theme almost always ships PNG sizes beside its SVG.

use std::collections::HashMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};

pub const SIZE: u32 = 128;

/// Every PNG icon found, by name, with its size when the path says it.
#[derive(Default)]
pub struct ThemeIndex {
    by_name: HashMap<String, Vec<(PathBuf, u32, u8)>>, // (path, size, rank: 0 hicolor, 1 other theme, 2 pixmaps)
}

impl ThemeIndex {
    pub fn build(data_dirs: &[PathBuf]) -> ThemeIndex {
        let mut index = ThemeIndex::default();
        let mut bases: Vec<PathBuf> = Vec::new();
        if let Some(home) = std::env::var_os("HOME") {
            bases.push(PathBuf::from(home).join(".icons"));
        }
        bases.extend(data_dirs.iter().map(|d| d.join("icons")));
        for base in &bases {
            let Ok(themes) = std::fs::read_dir(base) else { continue };
            for theme in themes.flatten() {
                let rank = if theme.file_name() == "hicolor" { 0 } else { 1 };
                index.walk(&theme.path(), 0, rank);
            }
        }
        for d in data_dirs.iter().map(|d| d.join("pixmaps")).chain([PathBuf::from("/usr/share/pixmaps")]) {
            index.walk(&d, 3, 2);
        }
        index
    }

    fn walk(&mut self, dir: &Path, depth: usize, rank: u8) {
        if depth > 4 {
            return;
        }
        let Ok(items) = std::fs::read_dir(dir) else { return };
        for item in items.flatten() {
            let path = item.path();
            let Ok(ft) = item.file_type() else { continue };
            if ft.is_dir() || (ft.is_symlink() && path.is_dir()) {
                self.walk(&path, depth + 1, rank);
            } else if path.extension().is_some_and(|e| e == "png") {
                let Some(name) = path.file_stem().map(|s| s.to_string_lossy().into_owned()) else { continue };
                let size = size_from_path(&path);
                self.by_name.entry(name).or_default().push((path, size, rank));
            }
        }
    }

    /// The file for `name`: the best rank, then the smallest size at least SIZE, else the largest.
    pub fn find(&self, name: &str) -> Option<&Path> {
        let list = self.by_name.get(name)?;
        let best_rank = list.iter().map(|e| e.2).min()?;
        let candidates = list.iter().filter(|e| e.2 == best_rank);
        let at_least = candidates.clone().filter(|e| e.1 >= SIZE).min_by_key(|e| e.1);
        let pick = at_least.or_else(|| candidates.max_by_key(|e| e.1))?;
        Some(&pick.0)
    }
}

/// "48x48", "48x48@2" or "48" among the path's folders (0 when none says).
fn size_from_path(path: &Path) -> u32 {
    for part in path.components().rev().skip(1) {
        let s = part.as_os_str().to_string_lossy();
        let (main, scale) = match s.split_once('@') {
            Some((m, sc)) => (m.to_string(), sc.trim_end_matches('x').parse::<u32>().unwrap_or(1)),
            None => (s.to_string(), 1),
        };
        let n = main.split_once('x').map(|(a, _)| a.to_string()).unwrap_or(main);
        if let Ok(v) = n.parse::<u32>() {
            if (8..=1024).contains(&v) {
                return v * scale;
            }
        }
    }
    0
}

/// A PNG file as a SIZE-px PNG (the longer side SIZE, aspect kept), or None.
pub fn load_png(path: &Path) -> Option<Vec<u8>> {
    let img = image::open(path).ok()?;
    let img = if img.width().max(img.height()) != SIZE {
        img.resize(SIZE, SIZE, image::imageops::FilterType::Lanczos3)
    } else {
        img
    };
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(out.into_inner())
}

/// ARGB pixels (a window's _NET_WM_ICON) as a SIZE-px PNG.
pub fn png_from_argb_scaled(w: u32, h: u32, argb: &[u32]) -> Option<Vec<u8>> {
    let mut rgba = Vec::with_capacity((w * h * 4) as usize);
    for &p in &argb[..(w * h) as usize] {
        rgba.extend_from_slice(&[(p >> 16) as u8, (p >> 8) as u8, p as u8, (p >> 24) as u8]);
    }
    let img = image::DynamicImage::ImageRgba8(image::RgbaImage::from_raw(w, h, rgba)?);
    let img = if w.max(h) != SIZE { img.resize(SIZE, SIZE, image::imageops::FilterType::Lanczos3) } else { img };
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(out.into_inner())
}

/// A BGRA picture as a JPEG fitted in box_w×box_h (aspect kept, never enlarged) at `quality`.
pub fn jpeg_thumbnail(width: u32, height: u32, bgra: &[u8], box_w: u32, box_h: u32, quality: u8) -> Option<Vec<u8>> {
    let mut rgb = Vec::with_capacity((width * height * 3) as usize);
    for px in bgra.chunks_exact(4).take((width * height) as usize) {
        rgb.extend_from_slice(&[px[2], px[1], px[0]]);
    }
    let img = image::DynamicImage::ImageRgb8(image::RgbImage::from_raw(width, height, rgb)?);
    let img = if width > box_w || height > box_h { img.thumbnail(box_w, box_h) } else { img };
    let mut out = Cursor::new(Vec::new());
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, quality);
    img.to_rgb8().write_with_encoder(encoder).ok()?;
    Some(out.into_inner())
}
