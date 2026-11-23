# QuickLook Seek

A tiny menu bar app that lets you seek Quick Look videos with the arrow keys.

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

## How it works

Quick Look's panel shows up in its host app's accessibility tree as a window
with subrole `Quick Look`. For media it contains an `AXSlider` described as
`timeline` whose value is the playback position in seconds. A keyboard event
tap catches ←/→, finds that slider in the frontmost app, and writes a new value.

`quicklook-seek.lua` is the original Hammerspoon prototype of the same idea.

## Mac App Store / App Sandbox

Not possible with this approach. `SANDBOX=1 ./build.sh` builds a sandboxed
copy: its event tap still starts, but every Accessibility call into Finder is
blocked (`deny mach-lookup com.apple.axserver (per-pid)` in the system log),
so it can't read or move the timeline. A
`temporary-exception.mach-lookup.global-name` entitlement for
`com.apple.axserver` doesn't help either. Distribute it outside the store
(Developer ID + notarization) instead.

Debug logging: `log stream --level debug --predicate 'subsystem == "com.quicklookseek.QuickLookSeek"'`
