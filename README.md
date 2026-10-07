# MC Mic Fix

MC Mic Fix is a free macOS menu-bar and launcher app. It fixes the Minecraft proximity-chat mic issue on Mac.

This is not a Fabric mod. You do not install it in a mods folder. It lives in the menu bar, asks macOS for the microphone, and starts your Minecraft launcher so voice chat can hear you.

## Why it exists

macOS TCC attributes microphone access to the **responsible process**. When you open a Minecraft launcher from the Dock, that launcher (or nothing useful) becomes responsible, and the official Minecraft launcher never declares microphone usage. Voice-chat mods (Simple Voice Chat, Plasmo Voice) then get silence.

MC Mic Fix requests the microphone itself, then starts **every** chosen launcher with `Foundation.Process` so **MC Mic Fix** stays the responsible process. Child processes (launcher, then Java, then OpenAL) inherit that grant.

It does **not** rely on `_JAVA_OPTIONS` / `java.sound.mixer` (those are unrelated to TCC). Optional legacy Java flags exist under Advanced and default to off.

## Supported launchers

Official Minecraft, Prism Launcher, Modrinth App, CurseForge, MultiMC, ATLauncher, GDLauncher, plus Other… (any `.app`). All are launched the same way through MC Mic Fix.

If the selected launcher is already running, the app offers **Quit and relaunch through MC Mic Fix**.

## Requirements

- macOS 27.0+
- A Minecraft launcher installed under `/Applications` or `~/Applications`

## Build

```bash
xcodegen generate
# Build DerivedData on the boot volume (Extreme Pro AppleDouble files break codesign)
xcodebuild -scheme 'MC Mic Fix' -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/MCMicFix-Local" build
```

## License

The source is public on GitHub. This repo is the app source, not a notarized download.
