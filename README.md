# DiaTweaks

Small tweaks for [Dia](https://www.diabrowser.com) that stay in place when Dia updates.

Unofficial and not affiliated with The Browser Company. Apple Silicon, macOS 14 or later.

## Tweaks

Each tweak changes one part of how Dia looks, like the padding around pages or a button in the toolbar. There's also a command, **Group Tabs by Domain**, that groups tabs by site.

Turn tweaks on and off in **Dia → Settings → Patches**, or with the `diatweaks` command.

[See all tweaks →](https://github.com/JaceThings/DiaTweaks/wiki)

This fork adds [Allow iCloud Passwords](docs/tweaks/Allow-iCloud-Passwords.md), [Don't pop up downloads](docs/tweaks/Dont-pop-up-downloads.md), [Don't open a new tab at launch](docs/tweaks/Dont-open-a-new-tab-at-launch.md), [Rename shortcuts](docs/tweaks/Rename-shortcuts.md) and [Reopen windows on their Spaces](docs/tweaks/Reopen-windows-on-their-Spaces.md).

## Install

1. Put Dia in your Applications folder.
2. Install Apple's developer tools: `xcode-select --install`
3. Paste this into Terminal:

   ```sh
   git clone https://github.com/thomplth/DiaTweaks.git ~/DiaTweaks && ~/DiaTweaks/install.sh
   ```

Dia quits and reopens. If macOS asks about "Dia Safe Storage", enter your password and click **Always Allow**.

## The `diatweaks` command

Run `diatweaks` on its own for a menu, or:

| Command | Does |
|---|---|
| `diatweaks list` | Shows every tweak and whether it's on |
| `diatweaks enable hideToolbar` | Turns a tweak on; Dia changes straight away |
| `diatweaks disable hideToolbar` | Turns a tweak off |
| `diatweaks status` | Shows Dia's version, safe mode and which tweaks are on |
| `diatweaks update` | Installs the latest DiaTweaks release and patches Dia again |
| `diatweaks update-dia` | Downloads a newer Dia and patches it |
| `diatweaks restore` | Puts the original Dia back |

Tweak names work as keys or titles, like `hideToolbar` or `"Hide toolbar"`. Add `-y` to skip the questions.

## Updating

Dia's own updater is switched off, so DiaTweaks stands in for it. A background job checks for a new Dia and a new DiaTweaks release every hour, whether or not Dia is open, verifies them and patches Dia ahead of time. When Dia isn't running it installs straight away; when Dia is open, the update goes in when you quit, and Dia reminds you to relaunch until you do, because browser updates usually fix security problems.

**Settings → Patches → Software Update** checks right now. Under **Automatic Updates**, pick for each of Dia and DiaTweaks: off, just show updates, download them, or download and install them when you quit (the default, and the one to keep for Dia).

- **Dia now:** `diatweaks update-dia`
- **DiaTweaks now:** `diatweaks update`

Dia downloads must carry The Browser Company's Apple-notarized signature. DiaTweaks downloads must be signed with a key in [`release-signers`](release-signers) and be newer than what you have.

<details>
<summary>Installed before <code>diatweaks</code> existed?</summary>

Update once by hand, then use `diatweaks update` from then on:

```sh
rm -rf /tmp/DiaTweaks && git clone --depth 1 https://github.com/thomplth/DiaTweaks.git /tmp/DiaTweaks && /tmp/DiaTweaks/install.sh
```

</details>

## FAQ

<details>
<summary><strong>Is it safe?</strong></summary>

It keeps Dia close to how safe it is unpatched:

- The patched Dia keeps Apple's hardened runtime, so other apps can't inject code into it through environment variables or attach a debugger.
- macOS refuses to load any library into it except Apple's, The Browser Company's and the exact DiaTweaks build it was patched with. A swapped file is simply never loaded.
- Dia only runs the `diapatch` that came with its DiaTweaks build.
- Updates are checked as above, so Dia stays as current as it would on its own.

The tweaks only change how Dia looks. **Allow iCloud passkeys** adds a small extension to every secure page so passkey requests reach Apple Passwords; it only passes them on for the site in the address bar, and it never sees your other pages, history or passwords.

</details>

<details>
<summary><strong>How does it work?</strong></summary>

It keeps an untouched copy of Dia and makes a second copy that loads a small add-on. The add-on moves and hides parts of Dia while it runs.

</details>

<details>
<summary><strong>Why does my Mac ask about "Dia Safe Storage"?</strong></summary>

The tweaked Dia is signed by you instead of The Browser Company, so macOS checks once for each new Dia or DiaTweaks version. Click **Always Allow**.

</details>

<details>
<summary><strong>Does it run in the background?</strong></summary>

Only to keep Dia updated: a launchd job runs `diapatch scheduled` every 15 minutes, checks for updates at most once an hour, and installs ones it has already downloaded while Dia is closed. Restoring the original Dia removes it.

</details>

<details>
<summary><strong>Does anything stop working?</strong></summary>

Dia's own passkey support needs an Apple entitlement only The Browser Company's signature can carry, so the patched Dia can't reach Apple Passwords by itself. **Allow iCloud Passkeys** (on by default) works around it: for each passkey, the original Dia that DiaTweaks keeps opens behind the Touch ID prompt, then quits. Sign in to Dia in that copy once when it asks.

The **iCloud Passwords** extension has the same problem: macOS only lets browsers signed by their own developers start the helper it talks to. **Allow iCloud Passwords** (on by default) has the original Dia start that helper: each time the extension connects, it opens for under a second without windows, then quits. See [how it works](docs/tweaks/Allow-iCloud-Passwords.md).

Passkeys in 1Password, Bitwarden and other managers work through their own extensions and don't need any of this. If 1Password calls Dia an unknown browser, add it under **1Password → Settings → Browser**, or turn on **Allow 1Password** (off by default), which keeps the original Dia running in the background while the extension is connected. Hardware security keys work either way.

</details>

<details>
<summary><strong>What if Dia keeps crashing?</strong></summary>

If Dia crashes twice in a row right after opening, it opens next time with the tweaks off. **Settings → Patches** has a button to turn them back on.

</details>

## Uninstall

In Dia, open **Settings → Patches** and click **Restore…**. Dia reopens as the original app with its own updates, and the background job and passkey host are removed.

To also delete DiaTweaks' files and the `diatweaks` command, run `diatweaks restore --purge` instead.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
