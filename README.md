# MC Mic Fix

A free macOS menu-bar app that fixes Minecraft microphone access for proximity-chat mods (Simple Voice Chat, Plasmo Voice) on Mac.

## Why it exists

macOS TCC attributes microphone access to the **responsible process**. When you open a Minecraft launcher from the Dock, that launcher (or nothing useful) becomes responsible — and the official Minecraft launcher never declares microphone usage. Voice-chat mods then get silence.

MC Mic Fix requests the microphone itself, then starts **every** chosen launcher with `Foundation.Process` so **MC Mic Fix** stays the responsible process. Child processes (launcher → Java → OpenAL) inherit that grant.

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

Private / unpublished until Joshua notarizes and releases it.
