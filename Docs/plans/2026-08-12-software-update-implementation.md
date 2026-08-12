# Software Update Implementation Plan

> **For agentic workers:** Execute this plan task-by-task in the current session. Do not delegate: the user explicitly requested no subagents. Every production change follows a red-green test cycle.

**Goal:** Add a localized, non-blocking GitHub Release update checker with a settings row and a three-action update window.

**Architecture:** Foundation-only update models, validation, persistence, and asynchronous checking live in `VeloopCore`. AppKit presentation stays in `Sources/App`; `AppDelegate` starts the automatic check only after the control window is visible. A release `update.json` asset supplies both supported translations while GitHub Release prose remains English.

**Tech Stack:** Swift 5.9, Foundation, AppKit, XCTest, URLSession, UserDefaults.

---

## File Map

- Create `Sources/Core/Update/NumericVersion.swift`: strict numeric dotted-version parsing and comparison.
- Create `Sources/Core/Update/UpdateManifest.swift`: bounded JSON model, localization selection, and trusted Release URL validation.
- Create `Sources/Core/Update/UpdatePreferenceStore.swift`: shared-default persistence for throttling, skip, and deferral state.
- Create `Sources/Core/Update/UpdateChecker.swift`: asynchronous fetch coalescing and automatic/manual policy.
- Create `Sources/App/UpdateCoordinator.swift`: main-actor status, automatic/manual orchestration, and presentation ownership.
- Create `Sources/App/UpdateWindowController.swift`: native localized update window and three user actions.
- Modify `Sources/App/AppDelegate.swift`: construct update dependencies and begin checking after window presentation.
- Modify `Sources/App/ControlWindowController.swift`: inject the coordinator and resize the fixed settings window.
- Modify `Sources/App/ControlViewController.swift`: add the independent Software Update row and manual action.
- Modify both `Localizable.strings` files: complete update UI localization.
- Create focused tests in `Tests/` and update release/source contracts.
- Modify ignored local `Packaging` scripts only if needed to emit and validate `update.json`; never stage them.

## Task 1: Numeric Version Ordering

**Files:**
- Create: `Tests/NumericVersionTests.swift`
- Create: `Sources/Core/Update/NumericVersion.swift`

- [ ] Write tests proving `0.2.4 > 0.2.3`, `0.2.3 == 0.2.3.0`, numeric ordering for `0.2.10`, and rejection of empty, negative, signed, alphabetic, and empty-component forms.
- [ ] Run `swift test --filter NumericVersionTests` and verify failure because `NumericVersion` does not exist.
- [ ] Implement an immutable `Comparable`, `Equatable`, and `Sendable` numeric-component value. Trim only surrounding whitespace, require ASCII digits in every component, normalize trailing zeroes, and compare zero-filled components.
- [ ] Re-run the focused test and verify it passes.

## Task 2: Manifest Validation and Localization

**Files:**
- Create: `Tests/UpdateManifestTests.swift`
- Create: `Sources/Core/Update/UpdateManifest.swift`

- [ ] Write tests for the approved schema, required English and Simplified Chinese notes, selected language, Follow System resolution, maximum response bytes, note count/length bounds, schema rejection, malformed JSON, and exact trusted GitHub Release URL rules.
- [ ] Run `swift test --filter UpdateManifestTests` and verify the tests fail for the missing model.
- [ ] Implement `UpdateManifestDecoder` with explicit limits: 64 KiB body, 32 entries per language, 500 Unicode scalars per entry. Reject empty/whitespace-only entries, unsupported schema, invalid versions, fragments, credentials, non-HTTPS URLs, non-`github.com` hosts, and paths outside `/talentdedcat/Veloop/releases/`.
- [ ] Implement `notes(for:preferredLocalizations:)` so explicit English/Chinese choices win and Follow System selects Chinese only when macOS resolves `zh-Hans`, otherwise English.
- [ ] Re-run the focused tests and verify they pass.

## Task 3: Persistent Update Policy

**Files:**
- Create: `Tests/UpdatePreferenceStoreTests.swift`
- Create: `Sources/Core/Update/UpdatePreferenceStore.swift`

- [ ] Write isolated-suite tests for last automatic attempt, 24-hour eligibility, skip matching only one version, deferral matching only one version, expiry at exactly 24 hours, and newer versions bypassing older decisions.
- [ ] Run `swift test --filter UpdatePreferenceStoreTests` and verify failure for the missing store.
- [ ] Implement a lock-protected, `@unchecked Sendable` store using `com.veloop.shared` by default and injected `UserDefaults` in tests. Prefix keys with `veloop.update.` and expose focused methods instead of raw defaults.
- [ ] Re-run the focused tests and verify they pass.
- [ ] Extend cleanup tests to prove the shared preferences plist already included by purge removes update decisions while preserve mode keeps it.

## Task 4: Asynchronous Checker

**Files:**
- Create: `Tests/UpdateCheckerTests.swift`
- Create: `Sources/Core/Update/UpdateChecker.swift`

- [ ] Write async tests for automatic throttling, silent fetch failure classification, successful automatic attempt timestamping, manual bypass of interval/skip/deferral, up-to-date results, available results, and coalescing simultaneous calls into one fetch.
- [ ] Run `swift test --filter UpdateCheckerTests` and verify failure for the missing checker.
- [ ] Define `UpdateCheckMode`, `UpdateCheckResult`, and an injectable `UpdateManifestFetching` boundary. Implement a production ephemeral `URLSession` fetcher for `https://github.com/talentdedcat/Veloop/releases/latest/download/update.json` with request/resource timeouts and disabled persistent cache.
- [ ] Implement `UpdateChecker` as an actor. Apply local automatic suppression before fetching, share one in-flight fetch task, record completed automatic attempts on success or failure, validate and compare versions, then apply version-specific suppression only for automatic calls.
- [ ] Re-run focused tests and verify they pass.

## Task 5: App Coordinator and Three Actions

**Files:**
- Create: `Tests/UpdatePresentationPolicyTests.swift`
- Create: `Sources/App/UpdateCoordinator.swift`
- Create: `Sources/App/UpdateWindowController.swift`

- [ ] Write Core-level action tests proving Skip stores only the shown version, Remind stores the shown version until now plus 24 hours, and Download does not alter skip/defer state.
- [ ] Add source-contract tests proving the AppKit window has exactly three localized actions and maps them to `skip`, `remindLater`, and `download` callbacks.
- [ ] Run the focused tests and verify failure because the action API and AppKit files are absent.
- [ ] Implement a main-actor coordinator with observable manual status, cached valid manifest, a set of automatically presented versions, and one owned update-window controller. Automatic failures stay silent; manual checks publish checking, up-to-date, available, or failed.
- [ ] Implement the native update window with version heading, scrollable bullet notes, an inline download error, and buttons ordered Skip This Version, Remind Me Later, Go to Download. Close only after skip/remind succeeds or `NSWorkspace.open` accepts the URL.
- [ ] Re-run focused tests and verify they pass.

## Task 6: Settings and Launch Integration

**Files:**
- Modify: `Sources/App/AppDelegate.swift`
- Modify: `Sources/App/ControlWindowController.swift`
- Modify: `Sources/App/ControlViewController.swift`
- Modify: `Sources/App/en.lproj/Localizable.strings`
- Modify: `Sources/App/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/AppLifecycleSourceContractTests.swift`
- Modify: `Tests/PermissionUISourceContractTests.swift`
- Create: `Tests/SoftwareUpdateUISourceContractTests.swift`

- [ ] Add failing source-contract tests for the independent Software Update section, installed version, status label, Check for Updates button, complete bilingual keys, and automatic-check ordering after `controller.showWindow(nil)`.
- [ ] Run the focused source-contract tests and verify expected failures.
- [ ] Inject `UpdateCoordinator` through the existing window/controller constructors. Add a 20-point section title and 42-point row between Permissions and Language; grow the fixed window by exactly 63 points while preserving current margins and row rhythm.
- [ ] Bind the manual status to localized idle/checking/up-to-date/available/failed text. Disable only the check button while a manual request is active.
- [ ] Construct the checker in `AppDelegate`, retain the coordinator, show the settings window first, and then start the automatic check in an unstructured main-actor task without awaiting it in the launch function.
- [ ] Add all English and Simplified Chinese strings for the section, statuses, update window, actions, and download-open failure.
- [ ] Re-run focused source-contract tests and verify they pass.

## Task 7: Release Metadata Contract

**Files:**
- Create: `Tests/UpdateReleaseContractTests.swift`
- Modify locally only: ignored `Packaging` scripts that create and verify release assets.

- [ ] Write failing tests that validate an `update.json` fixture against the public version, require both translations, reject internal build-number prose, and require the release asset filename to be exactly `update.json`.
- [ ] Run `swift test --filter UpdateReleaseContractTests` and verify expected failure.
- [ ] Add a tracked, non-generated example fixture only if tests require it; otherwise build JSON inside the test. Adjust ignored local release tooling to generate and validate the asset without staging `Packaging`.
- [ ] Re-run focused tests and verify they pass.
- [ ] Confirm `git ls-files` contains neither `Packaging`, `.superpowers`, nor generated `update.json` assets.

## Task 8: Documentation

**Files:**
- Modify: `README.md`
- Modify: `Docs/README.zh-CN.md`
- Modify: `Sources/README.md`

- [ ] Add concise English and Chinese descriptions of automatic daily checks, manual checking, localized release changes, and GitHub-download behavior. Do not claim automatic installation.
- [ ] Update the source map to include `Sources/Core/Update` and the two App update components without restoring a development-heavy section.
- [ ] Run README link/path checks and `git diff --check`.

## Task 9: Full Verification

**Files:** all changed files

- [ ] Run `swift test` and require zero failures.
- [ ] Run `xcrun clang -fobjc-arc -fmodules -fsyntax-only Sources/Palette/main.m`.
- [ ] Run `plutil -lint Configuration/*.plist`.
- [ ] Run `ruby -c Casks/veloop.rb`.
- [ ] Run `git diff --check`.
- [ ] Inspect `git status --short` and `git diff --stat`; verify every changed line belongs to update checking.
- [ ] Run `git ls-files | rg '(^|/)(Packaging|\\.superpowers)(/|$)|(^|/)update\\.json$'` and require no generated/private paths.
- [ ] Review resource boundaries: no update imports or calls under `Sources/Core/Input`, `Sources/Core/Clipboard`, `Sources/Core/Overlay`, `Sources/Agent`, or `Sources/Palette`.
- [ ] Build and open the local app, verify the settings row in English and Chinese, and use an injected/local test manifest to exercise all three update-window actions without publishing a new Release.

## Completion Criteria

- All automated and manual checks above pass.
- Startup displays the control window before initiating update network work.
- Automatic checks run no more than once per 24 hours and never use a repeating timer.
- Manual checks remain available and bypass automatic suppressions.
- The update window exactly exposes the three approved actions.
- `Packaging`, `.superpowers`, and generated release assets remain untracked.
