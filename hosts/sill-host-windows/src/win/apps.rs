//! Installed apps (the device's "All apps"), launching one, and app icons.
//!
//! The list is what the Start menu lists: the shortcuts (.lnk) under the Start Menu's Programs
//! folders, the machine's (ProgramData) and this user's (AppData), plus packaged apps (Store and
//! inbox apps such as Calculator) from the shell's Applications folder. An app's ID is the
//! executable a shortcut points at (so it matches its windows' app ID and icon), the shortcut
//! itself when it points at no executable, or a packaged app's AppUserModelID.
//!
//! A device may only launch an app this list or a listed window names: the ID is never taken as
//! a path to run as it is.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use windows::core::{Interface, PCWSTR, PWSTR};
use windows::Win32::Foundation::SIZE;
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, IPersistFile, CLSCTX_INPROC_SERVER, STGM_READ};
use windows::Win32::UI::Shell::{
    IEnumShellItems, IShellItem, IShellItemImageFactory, IShellLinkW, SHCreateItemFromParsingName,
    SHCreateItemInKnownFolder, SHGetKnownFolderItem, SHGetKnownFolderPath, ShellExecuteW, ShellLink,
    BHID_EnumItems, FOLDERID_AppsFolder, FOLDERID_CommonPrograms, FOLDERID_Programs, KF_FLAG_DEFAULT,
    SIGDN_NORMALDISPLAY, SIGDN_PARENTRELATIVEPARSING, SIIGBF_BIGGERSIZEOK, SIIGBF_ICONONLY,
};
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

use super::gdi;
use super::util::{com_init, from_wide, log, pcwstr, wide};
use crate::imaging;

/// The icon's size on the wire (platform.rs: about 128 px).
pub const ICON_SIZE: u32 = 128;

/// One installed app and how to start it.
#[derive(Clone, Debug)]
pub struct Installed {
    pub name: String,
    pub app_id: String,
    /// What ShellExecute opens: the shortcut (keeps its arguments and working folder), or
    /// `shell:AppsFolder\<AUMID>` for a packaged app.
    pub launch: String,
}

/// Every installed app, sorted by name, each app ID once (the first shortcut found wins; the
/// machine's folder is read first).
pub fn scan() -> Vec<Installed> {
    com_init();
    let mut found = Vec::new();
    for folder in [&FOLDERID_CommonPrograms, &FOLDERID_Programs] {
        if let Some(dir) = known_folder_path(folder) {
            let mut lnks = Vec::new();
            walk(&dir, 0, &mut lnks);
            lnks.sort();
            for lnk in lnks {
                if let Some(app) = shortcut(&lnk) {
                    found.push(app);
                }
            }
        }
    }
    found.extend(packaged_apps());
    let mut ids = HashSet::new();
    let mut names = HashSet::new();
    let mut apps: Vec<Installed> = found
        .into_iter()
        .filter(|a| ids.insert(a.app_id.to_lowercase()) && names.insert(a.name.to_lowercase()))
        .collect();
    apps.sort_by_key(|a| a.name.to_lowercase());
    apps
}

fn walk(dir: &Path, depth: usize, out: &mut Vec<PathBuf>) {
    if depth > 6 {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk(&path, depth + 1, out);
        } else if path.extension().is_some_and(|e| e.eq_ignore_ascii_case("lnk")) {
            out.push(path);
        }
    }
}

/// Shortcuts that are not apps: uninstallers, read-mes, help, links to web pages.
fn is_noise(name: &str) -> bool {
    let n = name.to_lowercase();
    ["uninstall", "readme", "read me", "release notes", "documentation", "license", "website", "help"]
        .iter()
        .any(|w| n.contains(w))
}

fn shortcut(lnk: &Path) -> Option<Installed> {
    let name = lnk.file_stem()?.to_string_lossy().into_owned();
    if is_noise(&name) {
        return None;
    }
    let lnk_str = lnk.to_string_lossy().into_owned();
    let target = shortcut_target(&lnk_str);
    let app_id = match target {
        Some(t) if t.to_lowercase().ends_with(".exe") => {
            let lower = t.to_lowercase();
            // An uninstaller or a setup program behind a friendly name.
            if lower.contains("unins") || lower.ends_with("setup.exe") {
                return None;
            }
            t
        }
        _ => lnk_str.clone(),
    };
    Some(Installed { name, app_id, launch: lnk_str })
}

/// The path a shortcut points at, if it points at a file (advertised installer shortcuts point
/// at none).
fn shortcut_target(lnk: &str) -> Option<String> {
    unsafe {
        let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER).ok()?;
        let file: IPersistFile = link.cast().ok()?;
        let wlnk = wide(lnk);
        file.Load(pcwstr(&wlnk), STGM_READ).ok()?;
        let mut buf = [0u16; 1024];
        link.GetPath(&mut buf, std::ptr::null_mut(), 0).ok()?;
        let target = from_wide(&buf);
        (!target.is_empty()).then_some(target)
    }
}

fn known_folder_path(id: &windows::core::GUID) -> Option<PathBuf> {
    unsafe {
        let p = SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, None).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as *const _));
        s.map(PathBuf::from)
    }
}

/// Packaged apps from the shell's Applications folder (shell:AppsFolder): the items whose parsing
/// name is an AppUserModelID ("Microsoft.WindowsCalculator_8wekyb3d8bbwe!App").
fn packaged_apps() -> Vec<Installed> {
    let mut out = Vec::new();
    unsafe {
        let Ok(folder) = SHGetKnownFolderItem::<IShellItem>(&FOLDERID_AppsFolder, KF_FLAG_DEFAULT, None) else {
            return out;
        };
        let Ok(items) = folder.BindToHandler::<_, IEnumShellItems>(None, &BHID_EnumItems) else {
            return out;
        };
        loop {
            let mut batch: [Option<IShellItem>; 1] = [None];
            let mut fetched = 0u32;
            if items.Next(&mut batch, Some(&mut fetched)).is_err() || fetched == 0 {
                break;
            }
            let Some(item) = batch[0].take() else { break };
            let Some(parsing) = display_name(&item, SIGDN_PARENTRELATIVEPARSING) else { continue };
            if !is_aumid(&parsing) {
                continue;
            }
            let Some(name) = display_name(&item, SIGDN_NORMALDISPLAY) else { continue };
            if is_noise(&name) {
                continue;
            }
            out.push(Installed { name, launch: format!("shell:AppsFolder\\{parsing}"), app_id: parsing });
        }
    }
    out
}

fn display_name(item: &IShellItem, kind: windows::Win32::UI::Shell::SIGDN) -> Option<String> {
    unsafe {
        let p: PWSTR = item.GetDisplayName(kind).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as *const _));
        s
    }
}

/// An AppUserModelID of a packaged app ("Family_publisher!AppId"), not a path.
pub fn is_aumid(id: &str) -> bool {
    id.contains('!') && !id.contains('\\') && !id.contains('/')
}

/// A packaged app's display name, from the Applications folder (cached: the window list asks for
/// it on every refresh).
pub fn packaged_display_name(aumid: &str) -> Option<String> {
    use std::sync::{Mutex, OnceLock};
    static CACHE: OnceLock<Mutex<HashMap<String, Option<String>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(hit) = cache.lock().ok().and_then(|c| c.get(aumid).cloned()) {
        return hit;
    }
    let name = packaged_display_name_uncached(aumid);
    if let Ok(mut c) = cache.lock() {
        c.insert(aumid.to_string(), name.clone());
    }
    name
}

fn packaged_display_name_uncached(aumid: &str) -> Option<String> {
    com_init();
    let w = wide(aumid);
    unsafe {
        let item: IShellItem = SHCreateItemInKnownFolder(&FOLDERID_AppsFolder, KF_FLAG_DEFAULT, pcwstr(&w)).ok()?;
        display_name(&item, SIGDN_NORMALDISPLAY)
    }
}

/// Opens what an `Installed` says to open.
pub fn launch(app: &Installed) -> Result<(), String> {
    com_init();
    let file = wide(&app.launch);
    let verb = wide("open");
    let result = unsafe { ShellExecuteW(None, pcwstr(&verb), pcwstr(&file), PCWSTR::null(), PCWSTR::null(), SW_SHOWNORMAL) };
    // ShellExecute's documented success: a value above 32.
    if result.0 as usize > 32 {
        log(&format!("Launched {} ({})", app.name, app.app_id));
        Ok(())
    } else {
        Err(format!("could not open {} (ShellExecute {})", app.name, result.0 as usize))
    }
}

/// An app's icon as a PNG of ICON_SIZE: the executable's or shortcut's own icon, or a packaged
/// app's from the Applications folder.
pub fn icon_png(app_id: &str) -> Option<Vec<u8>> {
    com_init();
    let factory: IShellItemImageFactory = unsafe {
        let w = wide(app_id);
        if is_aumid(app_id) {
            SHCreateItemInKnownFolder(&FOLDERID_AppsFolder, KF_FLAG_DEFAULT, pcwstr(&w)).ok()?
        } else if Path::new(app_id).is_absolute() {
            SHCreateItemFromParsingName(pcwstr(&w), None).ok()?
        } else {
            return None;
        }
    };
    let size = SIZE { cx: ICON_SIZE as i32, cy: ICON_SIZE as i32 };
    let hbm = unsafe { factory.GetImage(size, SIIGBF_ICONONLY | SIIGBF_BIGGERSIZEOK).ok()? };
    let bits = gdi::read_bitmap(hbm, 32);
    gdi::delete_bitmap(hbm);
    let bits = bits?;
    // The shell's bitmaps carry premultiplied alpha.
    imaging::icon_png(bits.bgra(), true, ICON_SIZE)
}

/// The installed apps by ID, kept from the last scan, so a launch and an icon need no rescan.
#[derive(Default)]
pub struct AppIndex {
    by_id: HashMap<String, Installed>,
}

impl AppIndex {
    pub fn replace(&mut self, apps: &[Installed]) {
        self.by_id = apps.iter().map(|a| (a.app_id.to_lowercase(), a.clone())).collect();
    }

    pub fn get(&self, app_id: &str) -> Option<Installed> {
        self.by_id.get(&app_id.to_lowercase()).cloned()
    }
}
