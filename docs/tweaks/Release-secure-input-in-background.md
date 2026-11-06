# Release Secure Input in background

macOS Secure Input hides what you type from other apps, and Dia turns it on while a password field has focus. Dia keeps
it on after you switch to another app, so other apps' keyboard shortcuts can stop working everywhere until you go back
and leave the field. Window managers, launchers and text expanders are the usual victims.

This tweak turns Secure Input off while Dia doesn't have keyboard focus, and back on before Dia takes focus again, so
what you type into a password field stays protected.

It changes nothing while you're in Dia: with the cursor in a password field, other apps' shortcuts stay blocked.

To check who holds Secure Input, run `ioreg -l -w 0 | grep kCGSSessionSecureInputPID`. It prints nothing when no app does.

Turn it off in **Settings → Patches**, or with `diatweaks disable releaseSecureInput`.
