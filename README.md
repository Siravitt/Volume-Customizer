# Sound Space

A free, open-source menu bar app for macOS that sets the volume of each app separately.

Turn Discord down while music plays, mute a noisy browser tab's app, or keep Zoom loud while Spotify stays quiet. Sound Space remembers each app's volume and applies it every time the app runs.

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
brew install --cask siravitt/sound-space/sound-space
```

### Manual

1. Download `SoundSpace-x.y.z.zip` from [Releases](https://github.com/Siravitt/sound-space/releases) and move `SoundSpace.app` to Applications.
2. Open it. macOS will say it can't verify the developer, because Sound Space isn't signed with a paid Apple Developer ID.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Sound Space.

## The audio permission

Sound Space changes an app's volume by passing its audio through Sound Space on its way to your speakers, using Apple's [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). macOS calls this **system audio recording**, so it asks for permission the first time.

Audio is processed on your Mac in real time. Nothing is recorded, saved, or sent anywhere. The only network request Sound Space makes is a daily check of this repository's latest release, to tell you when an update is available.

If you deny the permission, Sound Space leaves every app alone. You can turn it on later in **System Settings → Privacy & Security → Screen & System Audio Recording**.

## How it works

For each app you set below 100% or mute, Sound Space:

1. Creates a Core Audio process tap on all of the app's processes, with `mutedWhenTapped` so the app's normal output is silenced.
2. Creates a private aggregate device containing that tap and your current output device.
3. Copies the tapped audio to the output at the volume you chose, on the real-time audio thread.

Apps at 100% have no tap and no added latency. When you quit Sound Space, macOS removes its taps and every app plays normally again.

## Build from source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make open   # generate the Xcode project, build, and launch
make test   # run unit tests
```

Builds are ad-hoc signed unless the maintainer's certificate is in your keychain, so macOS asks for the audio permission again after each rebuild.

## License

[MIT](LICENSE)
