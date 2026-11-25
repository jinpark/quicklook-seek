# QuickLook Seek

A tiny menu bar app that lets you seek Quick Look videos with the arrow keys.

Website: <https://jinpark.github.io/quicklook-seek/> (a static page in `docs/`,
served by GitHub Pages from the `main` branch's `/docs` folder).

| Keys      | Action                         |
|-----------|--------------------------------|
| ← / →     | Seek back / forward (default 5s)  |
| ⇧← / ⇧→   | Seek back / forward (default 30s) |

Arrow keys are only intercepted while a Quick Look panel with a video or audio
timeline is open; otherwise they behave normally (e.g. arrowing between files
in Finder). ⌘/⌥/⌃ combinations are never touched.

## Build & install

```bash
./build.sh install
```

Builds a universal app, copies it to `/Applications`, and launches it. On first
launch, enable **QuickLook Seek** in System Settings → Privacy & Security →
Accessibility. Step sizes and Launch at Login are in the menu bar icon.

Local builds are signed with your Apple Development certificate if you have
one, otherwise ad-hoc. macOS ties the Accessibility permission to the signing
certificate, so a build signed one way and the official release (Developer ID)
don't share it: switching between them silently drops it. If you have a
Developer ID certificate and switch between your own builds and releases,
sign your builds the same way:

```bash
USE_DEVELOPER_ID=1 ./build.sh install
```

If seeking stops working after switching, reset the permission and grant it
again:

```bash
tccutil reset Accessibility net.jinpark.quicklookseek
```

## Release (Developer ID, outside the App Store)

One-time setup (needs a paid Apple Developer Program membership):

1. Create a **Developer ID Application** certificate: Xcode → Settings →
   Accounts → Manage Certificates → + → Developer ID Application.
2. Save notarization credentials (use an app-specific password from
   account.apple.com):

   ```bash
   xcrun notarytool store-credentials quicklook-seek --apple-id <apple-id> --team-id <team-id>
   ```

Then, for each release (bump `CFBundleShortVersionString` / `CFBundleVersion`
in `Info.plist` first):

```bash
./build.sh release
```

This builds, signs with your Developer ID and a secure timestamp, submits to
Apple's notary service and waits, staples the ticket, checks it with
Gatekeeper, and writes `dist/QuickLookSeek-<version>.zip`. If notarization is
rejected it prints Apple's log. It then signs the zip with the Sparkle key and
adds an entry to `appcast.xml`, and prints the two commands that publish it:

```bash
gh release create v<version> dist/QuickLookSeek-<version>.zip --repo jinpark/quicklook-seek --title <version>
git commit -am "Release <version>" && git push
```

Upload the zip first: the appcast entry points at the GitHub release asset.

## Updates (Sparkle)

The app checks for updates with [Sparkle](https://sparkle-project.org) 2.
`build.sh` downloads a pinned, checksum-verified copy into `vendor/` on first
build (`scripts/fetch-sparkle.sh`) and embeds it in the app.

- Feed: `appcast.xml` in this repo, served from
  `https://raw.githubusercontent.com/jinpark/quicklook-seek/main/appcast.xml`
  (`SUFeedURL` in `Info.plist`). The repo must be public for this to work.
- Downloads: GitHub release assets.
- Signing: updates are signed with an EdDSA key stored in your login keychain
  under the app's bundle ID as the account (`net.jinpark.quicklookseek`). Its public half is
  `SUPublicEDKey` in `Info.plist`. **Back up the private key**: if it's lost,
  existing installs can never accept another update.

  ```bash
  vendor/Sparkle/bin/generate_keys --account net.jinpark.quicklookseek -x sparkle-private-key.txt
  ```

  Store that file somewhere safe (a password manager), not in this repo.
  Restore it on another Mac with `generate_keys --account net.jinpark.quicklookseek -f sparkle-private-key.txt`.

"Check for Updates…" in the menu will report an error until the repo and its
first release exist.

## Forking

Building from source for yourself needs no changes: your build is the same
app and takes the official updates.

To publish your own builds, give the fork its own identity. Everything the
code and `build.sh` use comes from `Info.plist`:

| Key | What it's for |
|-----|---------------|
| `CFBundleIdentifier` | Bundle ID; also the log subsystem and the keychain account of the Sparkle key |
| `SUFeedURL` | Your `appcast.xml`, e.g. `https://raw.githubusercontent.com/<owner>/<repo>/main/appcast.xml` |
| `SUPublicEDKey` | Your Sparkle public key: run `vendor/Sparkle/bin/generate_keys --account <your bundle ID>` (it prints it) |
| `QLSSourceURL` | `https://github.com/<owner>/<repo>`: the About window links to it and releases are uploaded there |
| `QLSWebsiteURL` | The About window's website link (remove the key to drop the link) |
| `NSHumanReadableCopyright` | Copyright line in the About window |

Then delete the `<item>`s in `appcast.xml` (they're the original project's
releases) and point its `<link>` at your feed, and edit or delete `docs/`, the
project website.

## How it works

Quick Look's panel shows up in its host app's accessibility tree as a window
with subrole `Quick Look`. For media it contains an `AXSlider` described as
`timeline` whose value is the playback position in seconds. A keyboard event
tap catches ←/→, finds that slider in the frontmost app, and writes a new value.

Those two strings are English and may be localized, so there are fallbacks
that don't depend on language: the panel is also recognized by its controls'
`QLControl…` accessibility identifiers, and the timeline is the slider with the
largest range (its maximum is the duration in seconds; volume's is 1).

### Probe

To see what the app sees, open a video in Quick Look, leave that app in front,
and run:

```bash
open -g -n -W --stdout /dev/stdout "/Applications/QuickLook Seek.app" --args --probe --seek 10
```

It prints the panel's accessibility tree, the slider it picked, and the result
of seeking 10s. `--ignore-names` skips the English-name matches to test the
fallbacks. Launching through `open` makes the app's own Accessibility
permission apply rather than your terminal's.

`quicklook-seek.lua` is the original Hammerspoon prototype of the same idea.

## Icon

`Resources/AppIcon.icns` (and a 1024px PNG preview) are generated by
`swift tools/make-icon.swift`; edit and re-run it to change the icon.

## Mac App Store / App Sandbox

Not possible with this approach. `SANDBOX=1 ./build.sh` builds a sandboxed
copy: its event tap still starts, but every Accessibility call into Finder is
blocked (`deny mach-lookup com.apple.axserver (per-pid)` in the system log),
so it can't read or move the timeline. A
`temporary-exception.mach-lookup.global-name` entitlement for
`com.apple.axserver` doesn't help either. Distribute it outside the store
(Developer ID + notarization) instead.

## Debugging

Bundle ID: `net.jinpark.quicklookseek`.

Debug logging: `log stream --level debug --predicate 'subsystem == "net.jinpark.quicklookseek"'`
