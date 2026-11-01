# Allow iCloud Passwords

Lets Apple's **iCloud Passwords** extension fill and save passwords, verification codes and passkeys from Apple Passwords in the patched Dia.

## Why it's needed

macOS only lets browsers signed by their own developers start the helper the extension talks to. The patched Dia is signed on your Mac, so macOS stops the helper, and the extension says it "couldn't connect to a helper application".

## How it works

DiaTweaks registers itself as the extension's helper. When the patched Dia connects, DiaTweaks starts the original Dia it keeps, in the background with no windows, and that copy starts Apple's helper and passes every message along. The copy quits about 20 seconds after the last connection closes. You may see a second Dia in the Dock while it runs.

Only `diapatch`, started by the patched Dia, can use the relay. Other browsers, like Chrome, still reach Apple's helper directly.

## Turning it off

Switch off **Allow iCloud Passwords** in **Settings → Patches**. Restoring the original Dia removes the relay too.
