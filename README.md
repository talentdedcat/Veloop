<div align="center">
  <img src="Docs/Assets/VeloopLogo.png" alt="Veloop icon" width="104"><br>
  <strong>Veloop</strong><br>
  <sub>Local clipboard history, exactly where you type.</sub>
  <p>
    <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Universal arm64 and x86_64" src="https://img.shields.io/badge/Universal-arm64_%2B_x86__64-30343f?style=flat&logo=apple&logoColor=white">
    <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-f05237?style=flat&logo=swift&logoColor=white">
    <img alt="release v0.2.0" src="https://img.shields.io/badge/release-v0.2.0-1683c7?style=flat">
    <img alt="MIT license" src="https://img.shields.io/badge/license-MIT-5b9d2f?style=flat">
  </p>
  <p>English · <a href="Docs/README.zh-CN.md">简体中文</a></p>
  <img src="Docs/Assets/README/focus-stack-depth-push.gif" alt="Veloop cycling through clipboard history beside the active caret" width="720">
  <p><code>⌘V</code> open · <code>⌘↑</code> older · <code>⌘↓</code> newer · release <code>⌘</code> to paste</p>
</div>

Veloop is a native clipboard history app for macOS. It preserves complete, materializable pasteboard snapshots, presents them beside the active text caret, and keeps capture, storage, preview, and restoration on your Mac.

## Highlights

- **Works where you type:** the nonactivating Focus Stack appears beside a real text insertion caret without taking focus from the current app.
- **Preserves the actual clipboard:** item order, parallel representations, custom UTTypes, rich text, images, media bytes, files, and folders remain available when their data can be materialized.
- **Local by design:** Veloop has no cloud sync, analytics, crash upload, network listener, or automatic remote downloads.
- **Quiet in the background:** the Agent has no Dock icon, menu bar item, notification, or persistent overlay.
- **Bounded and predictable:** history defaults to 100 snapshots and 100 MB, with persistent LRU eviction for the least recently used unprotected snapshot.
- **Native on modern Macs:** the App, plain uninstall watcher, Palette, and CLI ship as Universal `arm64 + x86_64` binaries with no third-party runtime dependency.

## Install

### Homebrew

```bash
brew tap talentdedcat/Veloop https://github.com/talentdedcat/Veloop.git
brew trust --tap talentdedcat/Veloop
brew install --cask Veloop
```

> [!IMPORTANT]
> **First installation:** v0.2.0 is ad-hoc signed and not notarized. Only remove quarantine from Veloop installed through this repository. Before the first launch, run:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Veloop.app
> open /Applications/Veloop.app
> ```

### DMG

[Download `Veloop-0.2.0-universal.dmg`](https://github.com/talentdedcat/Veloop/releases/download/v0.2.0/Veloop-0.2.0-universal.dmg), open it, and drag `Veloop.app` to `Applications`.

> [!IMPORTANT]
> **First installation:** v0.2.0 is ad-hoc signed and not notarized. Only remove quarantine from the DMG downloaded from this repository. After copying Veloop to Applications and before the first launch, run:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Veloop.app
> open /Applications/Veloop.app
> ```

After launching Veloop, enable **Start at login** in the control app if you want the Agent to run automatically. The DMG contains `Veloop.app` and an Applications shortcut. On macOS 26, a newly registered Character Palette may require one sign-out and sign-in before the current login session discovers it.

## Quick start

1. Press `Command-V` to open clipboard history beside the active caret.
2. Keep Command held and press Up for older snapshots or Down for newer snapshots.
3. Release Command to restore and paste the selected snapshot.
4. Press Escape to cancel without changing the clipboard.

History stops at both ends instead of wrapping. If the current text surface does not provide a valid native caret position, Veloop leaves the original paste shortcut untouched.

## Permissions

Approve Veloop in **System Settings > Privacy & Security**:

<table align="center">
  <thead>
    <tr>
      <th>Permission</th>
      <th>Why Veloop needs it</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Input Monitoring</strong></td>
      <td>Observe the global Command-V sequence while cycling is enabled.</td>
    </tr>
    <tr>
      <td><strong>Accessibility</strong></td>
      <td>Send the final synthetic paste event after a history item is selected.</td>
    </tr>
  </tbody>
</table>

Caret positioning does not use Accessibility permission. Clipboard capture continues without either permission. When Veloop is disabled or Input Monitoring is unavailable, the global Event Tap stops, the hidden Palette is deselected, and standard paste behavior remains unchanged.

### Permission status and troubleshooting

Permission status is checked live by the background Agent. “Checking” and “Agent unavailable” are distinct from “Missing.” An ordinary launch does not prompt for permissions. Use the permission buttons only when the corresponding permission is missing.

Veloop.app is the only permission-bearing Veloop application. No separate Veloop Agent.app is installed. In each privacy pane, add or enable `/Applications/Veloop.app`. For background operation, Veloop copies the exact signed bundle contents to the non-`.app` runtime directory `~/Library/Application Support/Veloop/AgentRuntime/Veloop` and runs its `Contents/MacOS/Veloop` in `--agent` mode. The executable bytes, code hash, application identity, and display name remain the same, while `/Applications/Veloop.app` is no longer held open and can be moved directly to Trash after the control window is closed.

Because a changed ad-hoc binary has a new code hash, macOS cannot safely transfer the old grant to that binary. When Veloop detects a changed installed executable, it clears stale Veloop permission records before starting the new Agent. Re-enable both permissions once after an ad-hoc binary update; this removes the misleading case where an old Veloop row appears enabled but the current binary is denied.

On every activation, Veloop queries the healthy Agent first without restarting it. Socket operations have a 200 ms per-phase deadline, and recovery runs only after that query fails. If the returned state is still missing either permission, Veloop restarts only the Agent once, waits for its new socket, and reads the fresh permission state immediately. This also detects changes made directly in System Settings because macOS applies a newly added Input Monitoring grant to a new process; a fully authorized Agent is never restarted, and the Veloop control app stays open.

## Uninstall behavior

The **When moved to Trash** setting has two choices. **Preserve History and Settings** is the default: after the control window is closed, moving `/Applications/Veloop.app` to Trash removes permissions, LaunchAgents, the external Agent runtime copy, the Palette, other runtime files, and the uninstall watcher while retaining clipboard history and settings. **Remove Everything** also deletes all Veloop history, settings, preferences, caches, saved state, and WebKit data.

`brew uninstall --cask veloop` always performs a complete purge, regardless of the Trash setting. `brew uninstall --zap --cask veloop` has the same empty final state. The equivalent direct command is `veloopctl uninstall --purge`.

## Control app

<div align="center">
  <img src="Docs/Assets/README/control-window-en.png" alt="Veloop control app in English" width="760">
</div>

The control app manages the background Agent, launch at login, content previews, history and storage limits, permissions, language, and local data. Closing the window exits the control app while the persistent Agent can continue clipboard capture and keyboard handling.

## How Focus Stack works

Veloop installs an invisible, additive `TISCategoryPaletteInputSource`. It is selected alongside the user's keyboard input source, so System Pinyin and other input methods remain active. The Palette implements no key, composition, candidate, or insertion handlers; it only retains the `IMKTextInput` session supplied by macOS.

When a Command-V cycle begins, the Agent sends one bounded local `CFMessagePort` request to the current frontmost application. The helper requires a collapsed selection, prefers `attributesForCharacterIndex:lineHeightRectangle:`, and falls back to the same client's zero-length `firstRectForCharacterRange` only when the line rectangle is invalid. Veloop accepts only a finite, line-sized rectangle on a real display.

This path does not scan the Accessibility tree or use mouse position, click history, screenshots, OCR, background retries, stale position caches, or per-application rules. If the text client returns no valid coordinate, Veloop shows no overlay and does not intercept the original paste.

### Compatibility and fallback

System Pinyin coexistence and Chinese composition have been verified in TextEdit. The production caret-query path has been verified in TextEdit, WeChat chat input, Notes, Xcode, Visual Studio Code, and editable web fields in Safari and Microsoft Edge. Browser chrome and other surfaces that do not establish a native text-input session intentionally receive no overlay.

Measured warm local requests were approximately 1.6-7.2 ms on the test Mac; this is a local measurement, not a platform guarantee. The selected card is `348 × 104 pt`. Moving through history uses a 180 ms vertical Depth Push, while Reduce Motion uses a 100 ms crossfade.

## Preserved data

One copy becomes a `PasteboardSnapshot` that retains pasteboard item order and every representation whose data can be materialized at capture time, including:

- Plain text, rich text, HTML, URLs, file URLs, and custom UTType values.
- PNG, JPEG, TIFF, HEIC, PDF, SVG, and GIF representations.
- Audio or video bytes directly present on the pasteboard.
- Finder files and folders, multiple items, and parallel representations on one item.

"Every representation" does not include data never placed on the pasteboard, expired delayed data, unavailable promised data, or remote content behind an HTTP URL. Veloop never downloads remote URLs automatically.

For local file URLs, Veloop stores the original representation and copies the referenced object into its snapshot store. Large files are copied and hashed in 1 MiB chunks; media is not transcoded or compressed.

## Privacy and storage

- History stays under `~/Library/Application Support/Veloop/`.
- Logs exclude clipboard text, URLs, filenames, and raw bytes.
- Concealed, transient, auto-generated, and common password-manager representations are skipped by default.
- Text previews are limited to 240 Unicode scalars.
- Image previews are downsampled to 320 pixels and held only in a 6 MiB transient cache.
- Identical blobs are stored once, and successful pastes refresh persistent LRU order.
- Quotas evict the least recently used unprotected snapshots first; turning off content previews displays metadata only.

## Command line

```bash
veloopctl status
veloopctl pause
veloopctl resume
veloopctl clear
veloopctl count
veloopctl storage
veloopctl doctor
veloopctl config get
veloopctl open-data-directory
veloopctl restart
veloopctl uninstall --purge
veloopctl version
```

The Agent and CLI communicate through a mode-`0600` Unix-domain socket and never listen on TCP.

## Project layout

```text
Sources/App/             control app and localization
Sources/Core/            capture, history, input, overlay, storage, and IPC
Sources/UninstallWatcher/ plain event-driven uninstall watcher entry point
Sources/Veloopctl/       embedded veloopctl entry point
Sources/Palette/         additive InputMethodKit caret bridge
Tests/                   behavioral and packaging contracts
Docs/                    localized README and product media
```

See the [source guide](Sources/README.md) for module ownership, runtime flow, and architectural invariants.

## License

Veloop is available under the [MIT License](LICENSE). Copyright (c) 2026 Veloop contributors.
