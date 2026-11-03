# Reopen windows on their Spaces

When Dia restarts, after an update for example, it opens every window on the Space you're looking at. This tweak puts each window back on the desktop Space it was on before Dia quit, about a second after it opens.

DiaTweaks remembers which Space each window is on while Dia runs, so it only knows a window's Space from the first time Dia runs with the tweak on. Turn it on, arrange your windows, and restarts from then on keep them where they were.

- Windows in full screen are left to Dia, which puts them back in their own Space itself.
- If a window's Space no longer exists, the window stays on the current one.
- New windows open on the current Space as usual.

Turn it on in **Settings → Patches**, or with `diatweaks enable restoreSpaces`.
