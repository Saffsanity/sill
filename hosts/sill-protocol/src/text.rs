//! `SafeText.label` and `SillVersion` (SafeText.swift, Compatibility.swift).

/// The longest label kept, in characters.
pub const LABEL_LIMIT: usize = 64;

fn is_format_or_private(c: char) -> bool {
    let u = c as u32;
    matches!(u,
        0x00AD | 0x0600..=0x0605 | 0x061C | 0x06DD | 0x070F | 0x08E2 | 0x180E | 0x200B..=0x200F
        | 0x202A..=0x202E | 0x2060..=0x2064 | 0x2066..=0x206F | 0xFEFF | 0xFFF9..=0xFFFB
        | 0x110BD | 0x110CD | 0x13430..=0x1343F | 0x1BCA0..=0x1BCA3 | 0x1D173..=0x1D17A
        | 0xE0001 | 0xE0020..=0xE007F
        // Private use.
        | 0xE000..=0xF8FF | 0xF0000..=0xFFFFD | 0x100000..=0x10FFFD
        // Noncharacters, which Swift reports as unassigned.
        | 0xFDD0..=0xFDEF)
        || (u & 0xFFFE) == 0xFFFE
}

/// Text a device supplies about itself as a one-line label: whitespace of every kind becomes one
/// space, control and format characters (bidi overrides, zero-width characters) and private-use
/// characters are removed, runs of spaces collapse, the ends are trimmed, at most `limit`
/// characters are kept. Swift counts grapheme clusters; this counts scalars, which keeps at most
/// as much.
pub fn safe_label(text: &str, limit: usize) -> String {
    let mut out = String::new();
    let mut pending_space = false;
    for c in text.chars() {
        if c.is_whitespace() {
            pending_space = !out.is_empty();
            continue;
        }
        if c.is_control() || is_format_or_private(c) {
            continue;
        }
        if pending_space {
            out.push(' ');
            pending_space = false;
        }
        out.push(c);
    }
    if out.chars().count() > limit {
        out = out.chars().take(limit).collect();
        while out.ends_with(' ') {
            out.pop();
        }
    }
    out
}

/// `safe_label` at the default limit (64).
pub fn label(text: &str) -> String {
    safe_label(text, LABEL_LIMIT)
}

/// A version as tags, bundles and the wire write it ("v0.4.0", "0.4", "1.2.3-beta.1"), compared
/// part by part with missing parts as 0. `SillVersion`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct SillVersion {
    pub components: Vec<u64>,
}

impl SillVersion {
    pub fn parse(text: &str) -> Option<SillVersion> {
        let t = text.trim();
        let t = t.strip_prefix('v').or_else(|| t.strip_prefix('V')).unwrap_or(t);
        let mut prefix: String = t.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
        while prefix.ends_with('.') {
            prefix.pop();
        }
        if !prefix.starts_with(|c: char| c.is_ascii_digit()) {
            return None;
        }
        let parts: Vec<&str> = prefix.split('.').collect();
        if parts.len() > 8 {
            return None;
        }
        let mut n = Vec::new();
        for p in parts {
            if p.is_empty() || p.len() > 9 {
                return None;
            }
            n.push(p.parse().ok()?);
        }
        Some(SillVersion::from_components(n))
    }

    pub fn from_components(mut c: Vec<u64>) -> SillVersion {
        while c.last() == Some(&0) {
            c.pop();
        }
        SillVersion { components: c }
    }

    pub fn zero() -> SillVersion {
        SillVersion { components: vec![] }
    }
}

impl std::fmt::Display for SillVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut c = self.components.clone();
        while c.len() < 2 {
            c.push(0);
        }
        let s: Vec<String> = c.iter().map(|v| v.to_string()).collect();
        write!(f, "{}", s.join("."))
    }
}

impl PartialOrd for SillVersion {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SillVersion {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        let n = self.components.len().max(other.components.len());
        for i in 0..n {
            let a = self.components.get(i).copied().unwrap_or(0);
            let b = other.components.get(i).copied().unwrap_or(0);
            if a != b {
                return a.cmp(&b);
            }
        }
        std::cmp::Ordering::Equal
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels() {
        assert_eq!(label("  iPad\n(iPad14,1)\t "), "iPad (iPad14,1)");
        assert_eq!(label("a\u{202E}b\u{200B}c"), "abc");
        assert_eq!(label("\u{0007}\u{2028}x"), "x");
        assert_eq!(label(&"x".repeat(100)).len(), 64);
        assert_eq!(safe_label("ab cd", 3), "ab");
        assert_eq!(label(""), "");
    }

    #[test]
    fn versions() {
        let v = |s| SillVersion::parse(s).unwrap();
        assert_eq!(v("v0.4.0"), v("0.4"));
        assert!(v("0.10") > v("0.9"));
        assert!(v("1.0.1") > v("1.0"));
        assert_eq!(v("1.2.3-beta.1").to_string(), "1.2.3");
        assert_eq!(v("0.3.0 (85)").to_string(), "0.3");
        assert_eq!(v("1").to_string(), "1.0");
        assert_eq!(SillVersion::parse("beta"), None);
        assert_eq!(SillVersion::parse("1..2"), None);
        assert_eq!(SillVersion::parse("1.2.3.4.5.6.7.8.9"), None);
        assert!(v("0.1") > SillVersion::zero());
    }
}
