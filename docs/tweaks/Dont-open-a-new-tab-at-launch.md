# Don't open a new tab at launch

When Dia starts, it can add a **New Tab** to a window and select it, even though the window already has tabs. This tweak closes that New Tab, so each window opens on the tab it was showing when Dia quit.

It only closes a New Tab when:

- it's the selected tab, it shows a blank New Tab page, and the window has other tabs or tab groups in the sidebar or tab bar
- the window opened in the last few seconds while Dia started, and you haven't clicked or typed in a window yet

A window with only a New Tab keeps it, and New Tabs you open yourself are never closed.

Turn it on in **Settings → Patches**, or with `diatweaks enable noLaunchNewTab`.
