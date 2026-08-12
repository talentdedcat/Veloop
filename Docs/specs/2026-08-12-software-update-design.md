# Veloop Software Update Design

**Date:** 2026-08-12

**Status:** Approved design pending written-spec review

## Objective

Add a native update-checking experience to Veloop without introducing automatic installation. Veloop checks GitHub Releases in the background, presents localized release notes when a newer version is available, and sends the user to the corresponding GitHub Release page to download it.

The update path must not block application startup, clipboard capture, permission refresh, or keyboard event handling.

## Scope

This feature includes:

- an automatic update check after application launch;
- a manual check in a new Software Update section of the settings window;
- a separate update window with localized release notes;
- Skip This Version, Remind Me Later, and Go to Download actions;
- structured update metadata attached to each GitHub Release;
- persistence for automatic-check timing and user decisions;
- English and Simplified Chinese interface text;
- automated coverage for update policy, validation, localization, and presentation contracts.

This feature does not include:

- downloading an update inside Veloop;
- replacing or relaunching the installed application;
- Sparkle or another automatic-update framework;
- parsing free-form GitHub Release notes;
- update work in the background Agent or global keyboard callback.

## Update Metadata

Each release includes an `update.json` asset with this schema:

```json
{
  "schemaVersion": 1,
  "version": "0.2.4",
  "releaseURL": "https://github.com/talentdedcat/Veloop/releases/tag/v0.2.4",
  "notes": {
    "en": ["Change one", "Change two"],
    "zh-Hans": ["修改一", "修改二"]
  }
}
```

GitHub Release notes remain English. Veloop does not derive application text from that body; it selects `notes.en` or `notes.zh-Hans` from the JSON according to the application's current language.

An update document is accepted only when all of these conditions hold:

- `schemaVersion` is `1`;
- `version` is a valid numeric dotted version and is newer than `AppConstants.version`;
- `releaseURL` uses HTTPS and its host is exactly `github.com`;
- the normalized path starts with `/talentdedcat/Veloop/releases/`;
- both English and Simplified Chinese note arrays exist and contain valid entries;
- the response remains within configured byte, item-count, and item-length limits.

Unsupported schemas, invalid versions, missing translations, unsafe URLs, oversized responses, and malformed JSON are rejected without presenting an update.

## Components

### Update Metadata Model

A Foundation-only model in `VeloopCore` decodes and validates `update.json`. It owns schema validation, release URL validation, localized-note selection, and bounded content rules. Keeping it free of AppKit makes the rules directly testable.

### Version Comparison

A dedicated numeric dotted-version type compares versions component by component. It does not use lexical string comparison. Equivalent trailing zeroes compare equally, so `0.2.3` and `0.2.3.0` do not create a false update.

### Update Preference Store

A small store backed by the existing `com.veloop.shared` `UserDefaults` suite records:

- the date of the last completed automatic check;
- the version skipped by the user;
- the version deferred by the user;
- the date until which that version is deferred.

The store accepts an injected `UserDefaults` and clock for deterministic tests. These values follow the existing uninstall policy: preserved with settings under normal preservation, removed by a full purge.

### Update Checker

The checker uses an ephemeral `URLSession` with a short timeout and no persistent URL cache. It fetches the release metadata on a utility task, enforces the response-size limit before decoding, validates the document, compares versions, and applies the preference policy.

The production metadata endpoint is the stable latest-asset URL `https://github.com/talentdedcat/Veloop/releases/latest/download/update.json`. HTTPS redirects used by GitHub's asset delivery are accepted, and the returned document's `releaseURL` must still pass repository validation.

The checker exposes separate automatic and manual entry points:

- automatic checks honor the 24-hour check interval, skipped version, deferred version, and per-process presentation guard;
- manual checks ignore the automatic interval, skipped version, and deferred-until date, allowing the user to inspect an available release at any time.

Only a completed automatic network attempt updates the last-check date. A check suppressed locally because it is too early does not change stored state.

### Settings Integration

The control window gains an independent Software Update section. It shows:

- the installed Veloop version;
- an idle, checking, up-to-date, update-available, or check-failed status;
- a Check for Updates button that remains available whenever no manual request is in progress.

Manual failure is presented inline in this section. Automatic network, parsing, or validation failure is silent and never interrupts launch.

### Update Window

When a usable newer release is found, Veloop presents one separate AppKit window. The window contains the new version, localized change list, and three actions:

- **Skip This Version:** stores the displayed version as skipped and closes the window. Later automatic checks do not show that version. A manual check can show it again.
- **Remind Me Later:** stores a deferral for the displayed version until 24 hours after the action and closes the window. Automatic checks may show it again after that time.
- **Go to Download:** opens the validated GitHub Release URL through `NSWorkspace` and closes the window.

A process-local guard prevents the same version from being presented repeatedly during one application run. The guard is cleared for an explicit manual check so the user can reopen the window.

The window reads localization when it is constructed. If the application language changes, the next presentation uses the newly selected language. No separate Release metadata request is required when the valid result remains available in memory.

## Application Flow

1. Veloop finishes its existing setup and presents the control window.
2. The app schedules an automatic update check without awaiting it on the launch path.
3. The update policy decides whether a network request is due.
4. The checker fetches and validates `update.json` away from the main actor.
5. If no newer eligible version exists, no window appears.
6. If an eligible version exists, the app presents the update window on the main actor.
7. The user's selected action is persisted and the window closes.

Manual checking follows the same validation path but reports progress and failure in the settings section and bypasses automatic suppression rules.

## Scheduling Rules

- Automatic checks run after launch and at most once per 24-hour period.
- There is no continuously running update timer.
- Remind Me Later suppresses the displayed version for exactly 24 hours from the action.
- Skip This Version suppresses automatic presentation until a different newer version is released.
- A newer version is not suppressed by a skip or deferral recorded for an older version.
- A manual check always performs a fresh request and can present a skipped or currently deferred version.
- Concurrent automatic and manual requests are coalesced so only one network fetch and one presentation can be active.

## Error Handling

Automatic checks fail silently after diagnostic logging. They must not show alerts, activate Veloop, or change keyboard behavior.

Manual checks distinguish these user-visible outcomes:

- Veloop is up to date;
- a newer version is available;
- the check could not be completed.

The interface does not expose raw transport or decoding errors. Logs omit clipboard data and release-note content.

Opening the download page is attempted only with the already validated URL. If macOS refuses to open it, the update window remains available and shows a localized inline error.

## Localization

All static interface strings are added to the existing English and Simplified Chinese localization files. Release changes come from `update.json`.

When the app language is Follow System, note selection uses the application's preferred localization resolved by macOS. A resolved Simplified Chinese localization selects `zh-Hans`; every other currently supported localization selects `en`. This matches the existing application-bundle fallback while both translations remain mandatory in the document.

## Resource and Privacy Constraints

- No update code runs in the Agent process, event tap, paste-cycle path, caret lookup, or clipboard monitor.
- No repeating timer is used for update checks.
- Network work is asynchronous and cannot delay the first control-window presentation.
- The response body is bounded before JSON decoding.
- The checker sends no history, settings, permission state, device identifier, or analytics.
- The only request is for public release metadata hosted by the Veloop GitHub repository.

## Release Workflow

The local release workflow creates and validates `update.json` alongside the DMG. The public GitHub Release receives both generated assets, while its written release notes remain English.

Repository policy remains unchanged:

- generated release metadata is uploaded as a Release asset;
- the local `Packaging` directory remains ignored and is not committed;
- `.superpowers` content is neither required nor committed.

## Verification

Tests cover:

- numeric version ordering and equivalent trailing zeroes;
- rejection of malformed and unsupported metadata;
- HTTPS and repository URL enforcement;
- response and release-note bounds;
- English, Simplified Chinese, and Follow System note selection;
- 24-hour automatic-check throttling;
- skipped and deferred versions;
- newer releases bypassing older suppression records;
- manual checks bypassing suppression;
- coalescing concurrent checks;
- each update-window action;
- manual status transitions and silent automatic failure;
- source contracts proving update checks are launched after the control window appears and do not enter Agent or input paths;
- release contracts ensuring `update.json` and DMG metadata refer to the same public version.

The final verification runs the complete Swift test suite, Objective-C Palette syntax checking, property-list validation, Cask syntax checking, and repository checks that prevent `Packaging`, `.superpowers`, or generated build artifacts from being committed.

## Acceptance Criteria

- A newer valid GitHub release produces the localized update window after launch without delaying Veloop startup.
- The window exactly offers Skip This Version, Remind Me Later, and Go to Download.
- Remind Me Later allows automatic presentation again after 24 hours.
- Skip This Version affects only that version and only automatic presentation.
- Manual checking remains available and can reopen a skipped or deferred update.
- The settings page reports manual progress and outcomes in the selected application language.
- Release notes shown in the app match the selected language, while GitHub Release prose remains English.
- Network and metadata failures do not interrupt normal clipboard or keyboard operation.
- No automatic download or installation occurs.
