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

The Core module is shared by the shipped executables and the XCTest contracts. System API ownership stays in focused wrappers so capture, retention, presentation, and control logic remain independently testable.

The same `Veloop` executable runs in `--agent` mode, so `/Applications/Veloop.app` is the only permission-bearing application identity. The control app performs one bounded state request before recovery on ordinary activation. Returning from a permission-button trip to System Settings force-restarts only the Agent once before querying, because macOS activates a newly added Input Monitoring grant for a new process. A changed ad-hoc executable hash triggers targeted stale-permission cleanup before the new Agent starts.

## Runtime flow

1. `PasteboardMonitor` observes pasteboard change counts with a leeway-enabled utility-queue timer.
2. `PasteboardCapturer` materializes ordered items and type representations on a serial utility queue.
3. `HistoryStore` atomically commits manifests, retains referenced blobs or file snapshots, and applies configured quotas.
4. `EventTapManager` normalizes global keyboard events into `PasteCycleController` while keeping storage and preview work outside the Event Tap callback.
5. At cycle start, the Agent requests one current caret rectangle through the local Palette bridge. An invalid or unavailable rectangle leaves standard paste behavior untouched.
6. `CyclePresentationRelay` coalesces rapid selections before preview work reaches the main queue and the nonactivating Focus Stack panel.
7. Command release hides the panel, restores the selected snapshot, and dispatches one marked synthetic paste event. Escape cancels without changing the pasteboard.
8. The Agent persists successful-use order so retention can evict the least recently used unprotected snapshot first.

## Architectural boundaries

- **Event Tap:** normalize only the keyboard sequence needed for cycling. Do not perform capture, disk I/O, preview generation, or blocking IPC in the callback.
- **AppKit:** create and update windows, views, images, and user-visible state on the main thread. The Agent must not create normal or key windows.
- **Palette:** retain the system-provided text-input session and answer caret queries. Do not implement key handling, composition, candidates, or text insertion.
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
