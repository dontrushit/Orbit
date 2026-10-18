# Orbit

A small native macOS utility that adds the features macOS is missing. Turn modules on and off in one window.
Works locally: no servers, accounts or telemetry.

## Modules

- **New File** — create text, Markdown, JSON and HTML files right from the Finder context menu,
  either in a "New File" submenu or as separate menu items.

## Requirements

macOS 14 Sonoma or later, Apple silicon or Intel.

## Installation

1. Download `Orbit-<version>.dmg` from [Releases](https://github.com/dontrushit/Orbit/releases), open it and drag **Orbit** to **Applications**.
2. Open Orbit. macOS says it can't verify the developer and doesn't open the app — click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to the message about Orbit and click
   **Open Anyway**, then confirm with your password. This is needed only once.
4. In Orbit, click **Turn On…** to enable the Finder extension
   (**System Settings → General → Login Items & Extensions → Finder**).

Orbit isn't notarized by Apple, which is why macOS asks for confirmation on the first launch.

## Uninstall

Quit Orbit and move it from Applications to the Trash — the Finder extension is removed with it.
Settings are kept in `~/Library/Group Containers/` in a folder ending with `dev.orbit.mac.shared`;
delete it too if you want to remove everything.

## Building from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set DEVELOPMENT_TEAM
make run     # build and launch a Debug build
make test    # unit tests
make dmg     # signed Release build in build/Orbit-<version>.dmg
```

After rebuilding, run `make reload` to restart Finder so it picks up the new extension.
