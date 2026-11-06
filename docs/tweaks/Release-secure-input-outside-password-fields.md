# Release Secure Input outside password fields

macOS Secure Input hides what you type from other apps, and Dia turns it on while a password field has focus. Dia then
leaves it on after the field is gone: after you submit a login form, click out of the field or the page removes it, and
after you switch to another app. Other apps' keyboard shortcuts stop working everywhere until you leave Dia and come back.
Window managers, launchers and text expanders are the usual victims.

This tweak keeps Secure Input on only while a password field in Dia has keyboard focus. It comes back before you can type
in the field again, so what you type stays protected.

With the cursor in a password field in Dia, other apps' shortcuts are still blocked. That's the protection working.

To check who holds Secure Input, run `ioreg -l -w 0 | grep kCGSSessionSecureInputPID`. It prints nothing when no app does.

Turn it off in **Settings → Patches**, or with `diatweaks disable releaseSecureInput`.
