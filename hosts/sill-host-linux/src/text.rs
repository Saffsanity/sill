//! Text from a device's software keyboard as X keysyms, and how to type each one: by a key the keymap
//! has (at level 1, or level 2 with Shift), else by a spare keycode remapped to it for a moment, as
//! xdotool does. Pure; the X side (input.rs) reads the keymap and fakes the presses.

/// What a character is typed as.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Typed {
    /// A key of its own (Return, Tab, BackSpace), whatever the layout.
    Key(u32),
    /// A keysym to find on the keymap.
    Sym(u32),
}

/// The keysym for one character ("\n", "\t" and "\u{8}" are Return, Tab and BackSpace). Latin-1's
/// printable characters are their own keysyms; any other Unicode character is 0x0100_0000 + its code
/// point (the X11 keysym convention for Unicode), which an X server types once a key carries it.
pub fn keysym(c: char) -> Option<Typed> {
    let cp = c as u32;
    Some(match c {
        '\n' | '\r' => Typed::Key(0xff0d),
        '\t' => Typed::Key(0xff09),
        '\u{8}' => Typed::Key(0xff08),
        '\u{7f}' => Typed::Key(0xffff),
        _ if cp < 0x20 => return None,
        _ if (0x20..=0x7e).contains(&cp) || (0xa0..=0xff).contains(&cp) => Typed::Sym(cp),
        _ => Typed::Sym(0x0100_0000 + cp),
    })
}

/// Where a keysym sits on a keymap read with GetKeyboardMapping: the keycode and whether Shift is
/// needed (level 2). `syms` holds `per` keysyms for each keycode from `first`. Levels 3 and 4 (AltGr)
/// are left alone: which modifier reaches them depends on the layout, so such a character is typed
/// through a remapped spare key instead.
pub fn find(syms: &[u32], per: usize, first: u8, sym: u32) -> Option<(u8, bool)> {
    if per == 0 {
        return None;
    }
    let mut shifted = None;
    for (i, chunk) in syms.chunks(per).enumerate() {
        let keycode = first as usize + i;
        if keycode > 255 {
            break;
        }
        if chunk.first() == Some(&sym) {
            return Some((keycode as u8, false));
        }
        // A letter's uppercase keysym is often left implicit: the keymap lists only "a" at level 1
        // and X derives "A" (level 2 NoSymbol). Uppercase Latin letters are found by their lowercase.
        let level2 = match chunk.get(1) {
            Some(&0) | None => implicit_upper(chunk[0]),
            Some(&s) => Some(s),
        };
        if shifted.is_none() && level2 == Some(sym) {
            shifted = Some((keycode as u8, true));
        }
    }
    shifted
}

/// X's rule for a level-2 NoSymbol: the uppercase of a lowercase Latin letter.
fn implicit_upper(sym: u32) -> Option<u32> {
    match sym {
        0x61..=0x7a => Some(sym - 0x20),
        0xe0..=0xfe if sym != 0xf7 => Some(sym - 0x20),
        _ => None,
    }
}

/// Keycodes no key uses (every keysym NoSymbol), to remap for characters the keymap lacks, highest
/// first (xdotool takes the highest), at most `max`.
pub fn spare_keycodes(syms: &[u32], per: usize, first: u8, max: usize) -> Vec<u8> {
    if per == 0 {
        return Vec::new();
    }
    let mut spares: Vec<u8> = syms
        .chunks(per)
        .enumerate()
        .filter(|(_, chunk)| chunk.iter().all(|s| *s == 0))
        .map(|(i, _)| first as usize + i)
        .filter(|k| (8..=255).contains(k))
        .map(|k| k as u8)
        .collect();
    spares.reverse();
    spares.truncate(max);
    spares
}

/// How a run of keysyms is typed with spare keycodes: each step is either a keysym the keymap has,
/// typed as it is, or a keysym given to a spare (`Assign`) then typed by that spare, or every spare
/// given back (`Restore`) because all are taken. `on_keymap` says whether the keymap has a keysym.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Step {
    Type(u32),
    Assign(u8, u32),
    TypeSpare(u8),
    Restore,
}

pub fn plan(syms: &[u32], spares: &[u8], on_keymap: impl Fn(u32) -> bool) -> Vec<Step> {
    let mut steps = Vec::new();
    let mut assigned: Vec<(u8, u32)> = Vec::new();
    for &sym in syms {
        if on_keymap(sym) {
            steps.push(Step::Type(sym));
            continue;
        }
        if spares.is_empty() {
            continue; // nowhere to put it: dropped
        }
        if let Some((k, _)) = assigned.iter().find(|(_, s)| *s == sym) {
            steps.push(Step::TypeSpare(*k));
            continue;
        }
        if assigned.len() == spares.len() {
            steps.push(Step::Restore);
            assigned.clear();
        }
        let k = spares[assigned.len()];
        assigned.push((k, sym));
        steps.push(Step::Assign(k, sym));
        steps.push(Step::TypeSpare(k));
    }
    if !assigned.is_empty() {
        steps.push(Step::Restore);
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn characters_to_keysyms() {
        assert_eq!(keysym('a'), Some(Typed::Sym(0x61)));
        assert_eq!(keysym('A'), Some(Typed::Sym(0x41)));
        assert_eq!(keysym('é'), Some(Typed::Sym(0xe9)));
        assert_eq!(keysym('€'), Some(Typed::Sym(0x0100_20ac)));
        assert_eq!(keysym('😀'), Some(Typed::Sym(0x0101_f600)));
        assert_eq!(keysym('\n'), Some(Typed::Key(0xff0d)));
        assert_eq!(keysym('\u{8}'), Some(Typed::Key(0xff08)));
        assert_eq!(keysym('\u{1}'), None);
    }

    #[test]
    fn finding_keys_on_a_keymap() {
        // keycodes 38 ("a"), 39 ("s" "S"), 10 ("1" "exclam"), from first 8, two per keycode.
        let first = 8u8;
        let per = 2;
        let mut syms = vec![0u32; (255 - 8 + 1) * per];
        let mut put = |kc: usize, a: u32, b: u32| {
            syms[(kc - 8) * per] = a;
            syms[(kc - 8) * per + 1] = b;
        };
        put(38, 0x61, 0);
        put(39, 0x73, 0x53);
        put(10, 0x31, 0x21);
        assert_eq!(find(&syms, per, first, 0x61), Some((38, false)));
        assert_eq!(find(&syms, per, first, 0x41), Some((38, true))); // implicit uppercase
        assert_eq!(find(&syms, per, first, 0x53), Some((39, true)));
        assert_eq!(find(&syms, per, first, 0x21), Some((10, true)));
        assert_eq!(find(&syms, per, first, 0x20ac), None);
        assert_eq!(spare_keycodes(&syms, per, first, 2), vec![255, 254]);
    }

    #[test]
    fn spares_are_assigned_reused_and_given_back() {
        use Step::*;
        let on = |s: u32| s < 0x100; // Latin-1 is on the keymap
        let euro = 0x0100_20ac;
        let zhe = 0x0100_0436;
        let yo = 0x0100_0451;
        assert_eq!(plan(&[0x48, 0x69], &[250, 251], on), vec![Type(0x48), Type(0x69)]);
        assert_eq!(
            plan(&[euro, 0x61, euro, zhe, yo], &[250, 251], on),
            vec![Assign(250, euro), TypeSpare(250), Type(0x61), TypeSpare(250), Assign(251, zhe), TypeSpare(251), Restore, Assign(250, yo), TypeSpare(250), Restore]
        );
        assert_eq!(plan(&[euro], &[], on), vec![]);
    }
}
