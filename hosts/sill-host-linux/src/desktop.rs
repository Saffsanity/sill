//! Installed apps: the freedesktop.org desktop entries (`.desktop` files) in
//! $XDG_DATA_HOME/applications and each $XDG_DATA_DIRS/applications, as the device's "All apps"
//! (`apps`), what launches one (`exec_argv`), and which entry a window belongs to (`Index::for_window`,
//! by its WM_CLASS), so a window's app id is its desktop entry's when there is one and its icon and
//! name come from there.
//!
//! An app's id is its desktop file ID (the path below `applications/` with '/' as '-', without
//! ".desktop": "org.gnome.TextEditor", "xterm"), the spec's own name for it. Pure filesystem and text;
//! compiled and tested on every platform.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// One desktop entry of Type=Application.
#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub id: String,
    pub path: PathBuf,
    pub name: String,
    pub exec: Option<String>,
    pub icon: Option<String>,
    pub startup_wm_class: Option<String>,
    pub terminal: bool,
    /// NoDisplay, Hidden, OnlyShowIn/NotShowIn against the desktop, or a TryExec that is missing:
    /// not listed, still used to name and draw a window that belongs to it.
    pub hidden: bool,
}

/// The directories with `applications/` in them, most important first.
pub fn data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    match std::env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()) {
        Some(home) => dirs.push(PathBuf::from(home)),
        None => {
            if let Some(home) = std::env::var_os("HOME") {
                dirs.push(PathBuf::from(home).join(".local/share"));
            }
        }
    }
    let system = std::env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".to_string());
    for d in system.split(':').filter(|d| !d.is_empty()) {
        let p = PathBuf::from(d);
        if !dirs.contains(&p) {
            dirs.push(p);
        }
    }
    dirs
}

/// Every desktop entry, the first directory's winning for an id (the spec's precedence), sorted by
/// name. Hidden ones included (see `Entry::hidden`).
pub fn scan(dirs: &[PathBuf]) -> Vec<Entry> {
    let desktops: Vec<String> = std::env::var("XDG_CURRENT_DESKTOP")
        .unwrap_or_default()
        .split(':')
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    let mut by_id: HashMap<String, Entry> = HashMap::new();
    for dir in dirs {
        let apps = dir.join("applications");
        let mut files = Vec::new();
        walk(&apps, &apps, 0, &mut files);
        for (id, path) in files {
            if by_id.contains_key(&id) {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(&path) else { continue };
            // A file that is not an application still hides the same id further down the list.
            let entry = parse(&id, &path, &text, &desktops);
            by_id.insert(id.clone(), entry.unwrap_or(Entry {
                id,
                path,
                name: String::new(),
                exec: None,
                icon: None,
                startup_wm_class: None,
                terminal: false,
                hidden: true,
            }));
        }
    }
    let mut out: Vec<Entry> = by_id.into_values().filter(|e| !e.name.is_empty()).collect();
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()).then(a.id.cmp(&b.id)));
    out
}

fn walk(root: &Path, dir: &Path, depth: usize, out: &mut Vec<(String, PathBuf)>) {
    if depth > 4 {
        return;
    }
    let Ok(read) = std::fs::read_dir(dir) else { return };
    let mut items: Vec<_> = read.flatten().collect();
    items.sort_by_key(|e| e.file_name());
    for item in items {
        let path = item.path();
        if path.is_dir() {
            walk(root, &path, depth + 1, out);
        } else if path.extension().is_some_and(|e| e == "desktop") {
            if let Ok(rel) = path.strip_prefix(root) {
                let rel = rel.to_string_lossy();
                let id = rel.trim_end_matches(".desktop").replace('/', "-");
                out.push((id, path));
            }
        }
    }
}

/// Parses one file's [Desktop Entry] group. None unless it is Type=Application with a Name.
pub fn parse(id: &str, path: &Path, text: &str, current_desktops: &[String]) -> Option<Entry> {
    let mut in_group = false;
    let mut keys: HashMap<String, String> = HashMap::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') {
            in_group = line == "[Desktop Entry]";
            continue;
        }
        if !in_group {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            keys.entry(k.trim().to_string()).or_insert_with(|| unescape(v.trim()));
        }
    }
    if keys.get("Type").map(String::as_str) != Some("Application") {
        return None;
    }
    let name = localized(&keys, "Name")?;
    let truthy = |k: &str| keys.get(k).is_some_and(|v| v == "true");
    let list = |k: &str| -> Option<Vec<String>> {
        keys.get(k).map(|v| v.split(';').filter(|s| !s.is_empty()).map(|s| s.to_string()).collect())
    };
    let mut hidden = truthy("NoDisplay") || truthy("Hidden");
    if !current_desktops.is_empty() {
        if let Some(only) = list("OnlyShowIn") {
            hidden |= !only.iter().any(|d| current_desktops.contains(d));
        }
        if let Some(not) = list("NotShowIn") {
            hidden |= not.iter().any(|d| current_desktops.contains(d));
        }
    }
    if let Some(try_exec) = keys.get("TryExec") {
        hidden |= find_program(try_exec).is_none();
    }
    let exec = keys.get("Exec").cloned().filter(|e| !e.is_empty());
    if exec.is_none() && !truthy("DBusActivatable") {
        hidden = true;
    }
    Some(Entry {
        id: id.to_string(),
        path: path.to_path_buf(),
        name,
        exec,
        icon: keys.get("Icon").cloned().filter(|i| !i.is_empty()),
        startup_wm_class: keys.get("StartupWMClass").cloned().filter(|c| !c.is_empty()),
        terminal: truthy("Terminal"),
        hidden,
    })
}

/// Name[ll_CC], Name[ll], then Name, by $LC_ALL / $LC_MESSAGES / $LANG.
fn localized(keys: &HashMap<String, String>, key: &str) -> Option<String> {
    let lang = ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .find_map(|v| std::env::var(v).ok().filter(|s| !s.is_empty() && s != "C" && s != "POSIX"))
        .unwrap_or_default();
    let base = lang.split(['.', '@']).next().unwrap_or("");
    let short = base.split('_').next().unwrap_or("");
    for candidate in [base, short] {
        if !candidate.is_empty() {
            if let Some(v) = keys.get(&format!("{key}[{candidate}]")).filter(|v| !v.is_empty()) {
                return Some(v.clone());
            }
        }
    }
    keys.get(key).filter(|v| !v.is_empty()).cloned()
}

/// The spec's escapes in string values (\s \n \t \r \\); Exec's quoting is `exec_argv`'s.
fn unescape(v: &str) -> String {
    let mut out = String::with_capacity(v.len());
    let mut chars = v.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('s') => out.push(' '),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some('r') => out.push('\r'),
            Some('\\') => out.push('\\'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// The command line an Exec key launches with no files: its words (double quotes group, a backslash
/// inside quotes escapes ` " $ \`), the field codes dropped (%f %F %u %U and the deprecated ones),
/// %i as "--icon ICON", %c as the name, %k as the file's path, %% as %. None for an Exec that does
/// not parse.
pub fn exec_argv(entry: &Entry) -> Option<Vec<String>> {
    let exec = entry.exec.as_deref()?;
    let mut words: Vec<(String, bool)> = Vec::new(); // (word, was quoted)
    let mut cur = String::new();
    let mut quoted = false;
    let mut in_quotes = false;
    let mut has_word = false;
    let mut chars = exec.chars().peekable();
    while let Some(c) = chars.next() {
        if in_quotes {
            match c {
                '"' => in_quotes = false,
                '\\' => match chars.next() {
                    Some(n @ ('"' | '`' | '$' | '\\')) => cur.push(n),
                    Some(n) => {
                        cur.push('\\');
                        cur.push(n);
                    }
                    None => return None,
                },
                _ => cur.push(c),
            }
            continue;
        }
        match c {
            '"' => {
                in_quotes = true;
                quoted = true;
                has_word = true;
            }
            ' ' | '\t' => {
                if has_word {
                    words.push((std::mem::take(&mut cur), quoted));
                }
                quoted = false;
                has_word = false;
            }
            _ => {
                cur.push(c);
                has_word = true;
            }
        }
    }
    if in_quotes {
        return None;
    }
    if has_word {
        words.push((cur, quoted));
    }
    let mut argv = Vec::new();
    for (word, quoted) in words {
        if quoted {
            argv.push(word);
            continue;
        }
        match word.as_str() {
            "%f" | "%F" | "%u" | "%U" | "%d" | "%D" | "%n" | "%N" | "%v" | "%m" => continue,
            "%i" => {
                if let Some(icon) = &entry.icon {
                    argv.push("--icon".into());
                    argv.push(icon.clone());
                }
                continue;
            }
            _ => {}
        }
        let mut out = String::new();
        let mut it = word.chars();
        while let Some(c) = it.next() {
            if c != '%' {
                out.push(c);
                continue;
            }
            match it.next() {
                Some('%') => out.push('%'),
                Some('c') => out.push_str(&entry.name),
                Some('k') => out.push_str(&entry.path.to_string_lossy()),
                Some(_) | None => {} // a field code inside a word: dropped
            }
        }
        if !out.is_empty() {
            argv.push(out);
        }
    }
    if argv.is_empty() {
        None
    } else {
        Some(argv)
    }
}

/// A program by name on $PATH, or the path itself when it has a slash.
pub fn find_program(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let p = PathBuf::from(name);
        return p.is_file().then_some(p);
    }
    let path = std::env::var_os("PATH").unwrap_or_else(|| "/usr/local/bin:/usr/bin:/bin".into());
    std::env::split_paths(&path).map(|d| d.join(name)).find(|p| p.is_file())
}

/// The entries, with lookups for windows.
#[derive(Default, Debug)]
pub struct Index {
    pub entries: Vec<Entry>,
    by_id: HashMap<String, usize>,
    by_wm_class: HashMap<String, usize>,
    by_program: HashMap<String, usize>,
}

impl Index {
    pub fn new(entries: Vec<Entry>) -> Self {
        let mut index = Index { entries, ..Default::default() };
        for (i, e) in index.entries.iter().enumerate() {
            index.by_id.insert(e.id.to_lowercase(), i);
            if let Some(class) = &e.startup_wm_class {
                index.by_wm_class.entry(class.to_lowercase()).or_insert(i);
            }
            // The id's last dotted part ("org.gnome.TextEditor" → "texteditor") and the program.
            if let Some(last) = e.id.rsplit('.').next() {
                index.by_program.entry(last.to_lowercase()).or_insert(i);
            }
            if let Some(prog) = exec_argv(e).and_then(|a| a.first().cloned()) {
                let base = prog.rsplit('/').next().unwrap_or(&prog).to_lowercase();
                index.by_program.entry(base).or_insert(i);
            }
        }
        index
    }

    pub fn by_id(&self, id: &str) -> Option<&Entry> {
        self.by_id.get(&id.to_lowercase()).map(|i| &self.entries[*i])
    }

    /// The entry a window belongs to, from its WM_CLASS (instance, class): StartupWMClass first,
    /// then a desktop file named after the class or instance, then one whose program is.
    pub fn for_window(&self, instance: &str, class: &str) -> Option<&Entry> {
        let (i, c) = (instance.to_lowercase(), class.to_lowercase());
        let found = [&c, &i]
            .iter()
            .filter(|k| !k.is_empty())
            .find_map(|k| self.by_wm_class.get(*k))
            .or_else(|| [&c, &i].iter().filter(|k| !k.is_empty()).find_map(|k| self.by_id.get(*k)))
            .or_else(|| [&i, &c].iter().filter(|k| !k.is_empty()).find_map(|k| self.by_program.get(*k)));
        found.map(|i| &self.entries[*i])
    }

    /// The apps a device lists: every entry not hidden.
    pub fn listed(&self) -> impl Iterator<Item = &Entry> {
        self.entries.iter().filter(|e| !e.hidden)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(text: &str) -> Option<Entry> {
        parse("test", Path::new("/x/test.desktop"), text, &[])
    }

    #[test]
    fn parses_an_application() {
        let e = entry(
            "# c\n[Desktop Entry]\nType=Application\nName=Text Editor\nExec=gnome-text-editor %U\nIcon=org.gnome.TextEditor\nStartupWMClass=gnome-text-editor\n[Desktop Action new]\nName=New\nExec=x\n",
        )
        .unwrap();
        assert_eq!(e.name, "Text Editor");
        assert_eq!(e.icon.as_deref(), Some("org.gnome.TextEditor"));
        assert!(!e.hidden);
        assert_eq!(exec_argv(&e).unwrap(), vec!["gnome-text-editor"]);
        assert!(entry("[Desktop Entry]\nType=Link\nName=x\n").is_none());
        assert!(entry("[Desktop Entry]\nType=Application\nName=x\nExec=x\nNoDisplay=true\n").unwrap().hidden);
        assert!(entry("[Desktop Entry]\nType=Application\nName=x\nExec=x\nTryExec=/nonexistent/sill\n").unwrap().hidden);
    }

    #[test]
    fn exec_quoting_and_field_codes() {
        let mut e = entry("[Desktop Entry]\nType=Application\nName=My App\nExec=x\nIcon=myicon\n").unwrap();
        e.exec = Some(r#""/opt/My App/bin/app" --name=%c %i -o "a \"q\" \$HOME" 100%% %F"#.to_string());
        assert_eq!(
            exec_argv(&e).unwrap(),
            vec!["/opt/My App/bin/app", "--name=My App", "--icon", "myicon", "-o", "a \"q\" $HOME", "100%"]
        );
        e.exec = Some("\"unterminated".into());
        assert!(exec_argv(&e).is_none());
        e.exec = Some("%U".into());
        assert!(exec_argv(&e).is_none());
    }

    #[test]
    fn windows_find_their_entry() {
        let mk = |id: &str, exec: &str, class: Option<&str>| Entry {
            id: id.into(),
            path: PathBuf::from(format!("/x/{id}.desktop")),
            name: id.into(),
            exec: Some(exec.into()),
            icon: None,
            startup_wm_class: class.map(|c| c.into()),
            terminal: false,
            hidden: false,
        };
        let index = Index::new(vec![
            mk("org.gnome.TextEditor", "gnome-text-editor %U", Some("gnome-text-editor")),
            mk("xterm", "xterm", None),
            mk("org.xfce.mousepad", "mousepad %U", None),
        ]);
        assert_eq!(index.for_window("gnome-text-editor", "Gnome-text-editor").unwrap().id, "org.gnome.TextEditor");
        assert_eq!(index.for_window("xterm", "XTerm").unwrap().id, "xterm");
        assert_eq!(index.for_window("mousepad", "Mousepad").unwrap().id, "org.xfce.mousepad");
        assert!(index.for_window("xeyes", "XEyes").is_none());
        assert_eq!(index.by_id("XTERM").unwrap().id, "xterm");
    }
}
