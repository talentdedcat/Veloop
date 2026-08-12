# Veloop source guide

This guide maps Veloop's runtime ownership and the boundaries that keep clipboard capture, global input, presentation, restoration, and control independent. Product installation and usage are documented in the project [README](../README.md).

## Module map

| Module | Responsibility |
| --- | --- |
| `Sources/App/` | Control UI plus the `--agent` entry mode, AppKit settings, localization, permission presentation, and Palette/watcher installation. |
| `Sources/Core/` | Shared static Swift module for clipboard capture, history, configuration, global input, Focus Stack presentation, storage, local IPC, and system wrappers. |
| `Sources/Palette/` | Minimal InputMethodKit bridge that retains the active `IMKTextInput` session and answers bounded local caret queries. |
| `Sources/UninstallWatcher/` | Plain event-driven process that detects removal of the canonical installed app and invokes exact cleanup. |
| `Sources/Veloopctl/` | Thin executable entry point for the local `veloopctl` command surface. |

`Veloopctl` is the thin `veloopctl` entry point. Argument parsing, bounded Unix-socket IPC, and privacy-safe output remain in Core so they can be exercised independently.

### Core ownership

| Directory | Responsibility |
| --- | --- |
| `Core/Agent/` | Background runtime startup, request handling, and Agent registration. |
| `Core/Clipboard/` | Pasteboard capture policy, materialization, snapshots, and restoration. |
| `Core/CommandLine/` | Public CLI parser, Agent protocol, bounded socket client, and server. |
| `Core/Configuration/` | Validated persisted runtime configuration. |
| `Core/Control/` | Control-window state, updates, and permission-refresh coordination. |
| `Core/History/` | History indexing, retention, leases, and snapshot repository. |
| `Core/Input/` | Event Tap lifecycle, keyboard normalization, cycling, and paste injection. |
| `Core/Overlay/` | Palette and Accessibility caret location plus Focus Stack presentation. |
| `Core/Permissions/` | Listening, posting, and Accessibility capability preflight. |
| `Core/Storage/` | Atomic manifests, content-addressed blobs, and file snapshots. |
| `Core/Support/` | Constants, launch modes, logging, hashing, locking, and system wrappers. |
| `Core/Uninstall/` | Trash policy, uninstall watcher support, TCC reset, and exact cleanup. |

Repository-level release support lives in `Configuration/` for bundle metadata, `Packaging/` for release and DMG scripts, `Casks/` for Homebrew installation, `Tests/` for contracts, and `Docs/` for localized product documentation and media.

### Command-line surface

Homebrew links the bundled `Veloop.app/Contents/Resources/veloopctl` executable onto `PATH`; DMG users can invoke that full path directly. Agent-backed public commands are `status`, `pause`, `resume`, `clear`, `count`, `storage`, `doctor`, `config get`, and `config set <key> <value>`. Local commands are `open-data-directory`, `uninstall --purge`, and `version`. `restart` is not a supported public command. The accepted configuration keys are defined by `VeloopAgentRuntime.applyConfigurationValue`; capture-policy and polling changes apply when the Agent next starts, while limits, enabled state, and content-preview changes synchronize immediately.

The Core module is shared by the shipped executables and the XCTest contracts. System API ownership stays in focused wrappers so capture, retention, presentation, and control logic remain independently testable.

The same signed `Veloop` executable runs in `--agent` mode under the single `com.veloop.app` permission identity. Accessibility is the only user-configured permission. The Agent retains listening and posting preflights for `doctor` diagnostics, but only Accessibility gates the UI and runtime because macOS can report the legacy preflights inconsistently even while an Event Tap works. Registration copies the signed application bundle to `Application Support/Veloop/AgentRuntime/Veloop.app` before launching its `Contents/MacOS/Veloop`; the `.app` suffix preserves the Veloop icon in macOS privacy lists, while running outside the canonical bundle lets Finder move the installed app to Trash. Cleanup removes both this runtime bundle and the legacy extensionless `AgentRuntime/Veloop` path. The control app performs one bounded state request before recovery on every ordinary activation. While System Settings is active, it refreshes permission state every 100 milliseconds and stops immediately when another application becomes active, without restarting the Agent. If macOS disables the Event Tap, the Agent interrupts the cycle, passes standard keyboard input through, and checks only until Accessibility recovery recreates the listener. A changed ad-hoc executable hash triggers targeted stale-permission cleanup before the new Agent starts.

## Runtime flow

1. `PasteboardMonitor` observes pasteboard change counts with a leeway-enabled utility-queue timer.
2. `PasteboardCapturer` materializes ordered items and type representations on a serial utility queue.
3. `HistoryStore` atomically commits manifests, retains referenced blobs or file snapshots, and applies configured quotas.
4. `EventTapManager` normalizes global keyboard events into `PasteCycleController` while keeping storage and preview work outside the Event Tap callback.
5. At cycle start, the Agent queries the Palette first for one current caret rectangle when macOS already reports that input source as enabled. Veloop never calls `TISEnableInputSource`. Empty insertion points use the zero-length text-input range even when no character exists at index zero. If the Palette is disabled, unavailable, mismatched, or invalid, Veloop queries the focused Accessibility element's Text Marker bounds before its legacy collapsed-selection range. The fallback uses existing authorization and does not request permission. If every source fails validation, standard paste behavior remains untouched.
6. `CyclePresentationRelay` coalesces rapid selections before preview work reaches the main queue and the nonactivating Focus Stack panel.
7. Command release hides the panel, restores the selected snapshot, and dispatches one marked synthetic paste event. Escape cancels without changing the pasteboard.
8. The Agent persists successful-use order so retention can evict the least recently used unprotected snapshot first.

## Architectural boundaries

- **Event Tap:** normalize only the keyboard sequence needed for cycling. Do not perform capture, disk I/O, preview generation, or blocking IPC in the callback.
- **AppKit:** create and update windows, views, images, and user-visible state on the main thread. The Agent must not create normal or key windows.
- **Palette:** retain the system-provided text-input session and answer caret queries. Do not implement key handling, composition, candidates, or text insertion.
- **Accessibility caret fallback:** inspect only the system-focused element, verify its process, and request Text Marker or collapsed-selection bounds. Never traverse the accessibility tree, read text, or trigger a permission prompt.
- **Capture and storage:** materialize data before committing a manifest, use atomic writes, and keep large-file copying and hashing off latency-sensitive paths.
- **Local IPC:** the control app and CLI communicate with the Agent through bounded requests over a mode-`0600` Unix-domain socket. Runtime components do not listen on TCP.
- **System integration:** keep permission checks, input-source activation, process locking, logging, and other system APIs behind their existing wrappers.

## Privacy and reliability invariants

- Never log pasteboard text, URLs, filenames, representation bytes, or preview content.
- Never fetch remote content referenced by a URL on the pasteboard.
- Skip concealed, transient, auto-generated, and common password-manager representations according to capture policy.
- Preserve pasteboard item order and parallel type representations; do not reduce rich snapshots to plain text.
- Bound text previews, decoded image dimensions, transient preview memory, history count, and persistent storage.
- Keep the original paste path available whenever Veloop is disabled, permission is unavailable, or native caret validation fails.
- Keep the Agent quiet: no Dock icon, menu bar item, notification, SwiftUI scene, or persistent overlay.

## Test contracts

| Contract area | Tests |
| --- | --- |
| Blob identity, deduplication, and persistence | `Tests/BlobStoreTests.swift` |
| File and folder snapshot storage | `Tests/FileSnapshotStoreTests.swift` |
| History ordering, retention, and recovery | `Tests/HistoryStoreTests.swift` |
| Local Agent protocol and command behavior | `Tests/AgentProtocolTests.swift` |
| Input lifecycle and permission coordination | `Tests/InputSubsystemCoordinatorTests.swift` |
| Caret geometry and validation | `Tests/CaretLocatorTests.swift` |
| Native Palette source contract | `Tests/CaretSourceContractTests.swift` and `Tests/PaletteInputSourceActivatorTests.swift` |
| App, Agent, CLI, Universal binary, and release packaging contracts | `Tests/PackagingContractTests.swift` |

Changes should preserve these contracts and keep system-facing behavior inside the module that already owns it.
