//! Sill host for Linux (owned by the Linux agent; see ../README.md and ../NOTES-linux.md).
//!
//! The pure parts (the HID key table, the key state, text to keysyms, scrolling, desktop entries)
//! compile everywhere and are tested with `cargo test -p sill-host-linux` on any machine. The X11
//! backend (`linux`) builds only on Linux: X11 through x11rb (Xorg, and XWayland apps on a Wayland
//! session), HEVC through an FFmpeg subprocess, Avahi over D-Bus.

pub mod desktop;
pub mod keymap;
pub mod keys;
pub mod scale;
pub mod scroll;
pub mod text;

#[cfg(target_os = "linux")]
pub mod linux;
