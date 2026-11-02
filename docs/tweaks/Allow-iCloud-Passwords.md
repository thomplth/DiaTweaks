# Allow iCloud Passwords

Lets Apple's **iCloud Passwords** extension fill and save passwords, verification codes and passkeys from Apple Passwords in the patched Dia.

## Why it's needed

macOS only lets browsers signed by their own developers start the helper the extension talks to. The patched Dia is signed on your Mac, so macOS stops the helper, and the extension says it "couldn't connect to a helper application".

## How it works

DiaTweaks registers itself as the extension's helper. When the patched Dia connects, DiaTweaks starts the original Dia it keeps, headless and without windows, and hands the connection to the first process that copy starts, which becomes Apple's helper. macOS only checks who starts the helper, so the copy quits within a second and the helper talks to the extension directly from then on. A second Dia icon may flash in the Dock as it starts.

The window with the verification code you type into the extension the first time says "Enable Password AutoFill for “(null)”" rather than naming Dia: Apple's helper names the browser after the app that started it, and that copy has quit by then.

The extension connects once per profile when Dia opens, and again whenever its connection drops. Only `diapatch`, started by the patched Dia, starts the helper this way. Other browsers, like Chrome, still reach Apple's helper directly.

## Turning it off

Switch off **Allow iCloud Passwords** in **Settings → Patches**. Restoring the original Dia removes the helper registration too.
