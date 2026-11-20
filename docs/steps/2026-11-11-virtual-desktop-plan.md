**The Virtual Desktop, a plan (2026-11-11, branch `virtual-desktop-plan` from main at dd6ea6a, a draft pull request,
docs only; the plan, its rules, the four phases with their gates, the open questions with their defaults and Noah's
list are in `docs/virtual-desktop-plan.md`).** Noah: a display of Sill's own (the working name "Virtual Desktop", a
placeholder: "We can workshop the name"), off by default, at the main display's resolution and refresh rate; and the
Desktop button stepping through the Mac's monitors, the main one first, then the Virtual Desktop. His change the same
day: "instead of measuring, choose one of the default display resolution and refresh rate of the primary display or
4K 60Hz, whatever is less", so nothing is measured at run time: the main display's mode, its pixels held inside 3840 ×
2160 (its shape and pixel scale kept) and its rate to 60 Hz; custom sizes and rates are the person's choice from a
fixed list (phase 3); Match this device is phase 4. One manager for every display Sill makes; the Desktop's display
(#200's identity, 0x5111/0x0002/2) is one display in every role, the window stage's stays its own; the Virtual Desktop
exists only while a device shows it, plus 30 s, its windows moved to the main display at its end and back at its
return. Wire additive: `WindowList.desktopDisplays`, `desktopDisplay`, `desktopVirtual`, `desktopDisplayNames`, kind 47.
Phase 1 builds on #173 (#345's fix with it); #200 merges first as it is; #312, #156 and #225 credited. Nothing built,
nothing measured: no virtual display made, no display changed, the encoder not used. **Decided by Noah (2026-11-12;
the plan's "Decided" and §3a):** the size and the rate capped separately ("should choose 3024×1964 at 60 Hz but of
course everything should be user customizable"); phase 1 on #173, the rest credited, as proposed; Sill moves the
windows off and back, with 30 s, as proposed; and changed from the proposal, a paired device turns the Virtual Desktop
on and off (phase 2, shown at once when it does) and sets its resolution and refresh rate (phase 3) from its Settings
panel, through kinds 16 and 17 (`StreamSettings` and `HostSettingsChange`: `virtualDesktop`, `virtualDesktopSize`,
`virtualDesktopHz`), from away as well (open question 25); the Mac does all of it too, the default off. The name is
still a placeholder (§14).
