# Rename shortcuts

Adds keyboard shortcuts for renaming: **⌘/** renames the current tab and **⇧⌘/** renames the group it's in.

Each shortcut starts Dia's own rename, the same as choosing **Rename…** from the tab's or group's context menu, so the title turns editable in place. Press Return to keep the new name or Escape to cancel. It works with tabs in the sidebar and at the top.

The **Tabs** menu lists both shortcuts. **Rename Group…** only appears there while the current tab is in a group. Outside a group, **⇧⌘/** is left alone.

While it's on, Dia takes **⌘/** before web pages see it, so pages that use it, like web code editors toggling comments or Google Docs' list of shortcuts, won't get it.

Turn it on in **Settings → Patches**, or with `diatweaks enable renameShortcuts`.
