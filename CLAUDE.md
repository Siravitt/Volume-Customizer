# Volume Customizer

Free, open-source (MIT) macOS menu bar app for per-app volume control — a SoundSource alternative.

Formerly "Sound Space". GitHub repo: `Siravitt/Volume-Customizer`. Homebrew tap: `siravitt/volume-customizer` (repo `Siravitt/homebrew-volume-customizer`). The signing identity "Sound Space Self-Signed" and its backup folder `~/.config/sound-space/` keep the old name on purpose — don't rename them without asking the user.

## Working agreement

- Claude writes all the code. The user is new to Swift; they run the app, listen, grant permissions, and report back.
- At the end of each milestone: build, run unit tests, then give the user a short manual test checklist.
- Talk to the user in Thai.

## Decisions (v1)

- macOS 14.2+ only. Uses Core Audio **Process Taps** (`CATapDescription`, `muteBehavior = .mutedWhenTapped`) + a private aggregate device whose main sub-device is the system default output. No HAL driver.
- Only tap apps whose volume ≠ 100% or are muted; untouched apps play normally.
- Volume 0–100% per app (boost above 100% was dropped by the user). Mute per app.
- Group helper processes (Chrome/Electron helpers) under their parent app.
- List = apps currently playing + apps with saved settings that are running; rows linger 30 s after playback stops.
- Persist volume/mute per bundle ID and re-apply automatically.
- Follow the system default output; on device change rebuild taps (a short dropout is acceptable).
- Per-app tap failure → ⚠️ on the row, slider disabled, app plays normally. Permission denied → banner with button to System Settings.
- Onboarding screen explains the audio-capture permission before the system prompt.
- Master (system volume) slider at top of popover. Launch at login via `SMAppService`, off by default.
- Update check against GitHub Releases (notify only). No Sparkle in v1.
- Out of scope for v1: boost above 100%, per-app output device, EQ, level meters, keyboard shortcuts.
- Distribution: no paid Apple Developer account. Releases signed with one long-lived **self-signed certificate** so TCC keeps the permission across updates. GitHub Releases + own Homebrew tap. Universal binary.

## Milestones

- **M0 Spike** — done; removed after M1 (see git history).
- **M1** — done. Menu bar app listing playing apps (grouped) with slider + mute, no persistence.
- **M2** — done. Persistence, linger, follow output device, per-app errors.
- **M3** — done. Master slider, onboarding, launch at login, update check.
- **M4** — Release pipeline: self-signed cert, universal build, GitHub Release, Homebrew tap, README.

## Build

The Xcode project is generated; never edit `VolumeCustomizer.xcodeproj` by hand — edit `project.yml`.

```sh
make app   # xcodegen + xcodebuild
make open  # build, quit the running copy, launch
make test  # unit tests (Swift Testing, hosted in the app)
make release  # universal Release zip + Homebrew cask in dist/ (needs clean git tree)
```

Signing: the self-signed identity "Sound Space Self-Signed" is in the login keychain; backup p12 + password in `~/.config/sound-space/signing/`. Losing it means every user re-grants the audio permission once.

`xcode-select` on this machine points at CommandLineTools, so the Makefile sets `DEVELOPER_DIR` to `/Applications/Xcode.app`.

## Real-time audio thread rules

Code inside an IOProc (anything called from `AudioDeviceCreateIOProcIDWithBlock`) runs on the real-time thread. In that code:

- No allocation: no creating arrays, strings, or class instances, no closures that capture context freshly, no string interpolation.
- No locks, no `DispatchQueue`, no `await`, no `print`/`os_log`.
- Don't touch Swift class instances or ObjC objects (retain/release). Capture raw `UnsafeMutablePointer`s or plain values only.
- Share parameters with the UI via preallocated pointers (single aligned `Float` writes) or atomics.
- Keep render functions as free functions over `UnsafePointer`s so they are easy to review and unit-test.
