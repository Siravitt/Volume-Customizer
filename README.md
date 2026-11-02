# Volume Customizer

A free, open-source menu bar app for macOS that sets the volume of each app separately.

Turn Discord down while music plays, mute a noisy browser tab's app, or keep Zoom loud while Spotify stays quiet. Volume Customizer remembers each app's volume and applies it every time the app runs.

- Per-app volume (0–100%) and mute
- Helper processes are grouped under their app (Chrome, Brave, Electron apps, Safari's WebKit)
- Settings are remembered per app and applied before its first sound
- Follows your output device when you switch to headphones or AirPods
- System volume slider in the same popover
- Apps left at 100% aren't touched at all

Requires **macOS 14.2 or later**. Universal (Apple silicon and Intel).

## Install

### Homebrew

```sh
brew install --cask siravitt/volume-customizer/volume-customizer
```

### Manual

1. Download `VolumeCustomizer-x.y.z.zip` from [Releases](https://github.com/Siravitt/Volume-Customizer/releases) and move `VolumeCustomizer.app` to Applications.
2. Open it. macOS will say it can't verify the developer, because Volume Customizer isn't signed with a paid Apple Developer ID.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Volume Customizer.

## Use

1. Open Volume Customizer. The welcome window explains the audio permission; click **Continue** and allow it when macOS asks.
2. Click the slider icon in the menu bar. The top slider is your system volume, and every app that's playing sound has its own slider and mute button below it.
3. Drag an app's slider or click its speaker icon. The setting is saved, and it's applied again whenever that app plays.

An app stays in the list for 30 seconds after it goes quiet, and apps with saved settings stay as long as they're running. Turn on **Launch at login** at the bottom of the menu to start Volume Customizer with your Mac.

## Update

When a new version is out, the menu shows a **Download** link. If you installed with Homebrew, run:

```sh
brew upgrade --cask volume-customizer
```

## Uninstall

Quit Volume Customizer from its menu, then delete it from Applications, or run `brew uninstall --cask --zap volume-customizer`. Every app plays normally as soon as it quits.

## Troubleshooting

- **The menu says Volume Customizer needs audio access.** Click **Open System Settings** and turn on Volume Customizer under **Screen & System Audio Recording → System Audio Recording Only**.
- **An app shows ⚠️ and its slider is greyed out.** Volume Customizer couldn't attach to that app, so it plays at normal volume. Hover over the ⚠️ to see why. Quitting and reopening the app usually fixes it.
- **Sound cuts out for a moment when I switch to headphones.** Expected: Volume Customizer reconnects every adjusted app to the new output device.

## The audio permission

Volume Customizer changes an app's volume by passing its audio through Volume Customizer on its way to your speakers, using Apple's [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). macOS calls this **system audio recording**, so it asks for permission the first time.

Audio is processed on your Mac in real time. Nothing is recorded, saved, or sent anywhere. The only network request Volume Customizer makes is a daily check of this repository's latest release, to tell you when an update is available.

If you deny the permission, Volume Customizer leaves every app alone. You can turn it on later in **System Settings → Privacy & Security → Screen & System Audio Recording**.

## How it works

For each app you set below 100% or mute, Volume Customizer:

1. Creates a Core Audio process tap on all of the app's processes, with `mutedWhenTapped` so the app's normal output is silenced.
2. Creates a private aggregate device containing that tap and your current output device.
3. Copies the tapped audio to the output at the volume you chose, on the real-time audio thread.

Apps at 100% have no tap and no added latency. When you quit Volume Customizer, macOS removes its taps and every app plays normally again.

## Build from source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make open   # generate the Xcode project, build, and launch
make test   # run unit tests
```

Builds are ad-hoc signed unless the maintainer's certificate is in your keychain, so macOS asks for the audio permission again after each rebuild.

## License

[MIT](LICENSE)
